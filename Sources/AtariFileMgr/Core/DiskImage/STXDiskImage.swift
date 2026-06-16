// STXDiskImage.swift — AtariFileMgr
// Implements the Pasti .stx disk image reader.
//
// The .stx format is a low-level floppy preservation format that stores physical
// track layouts, fuzzy/weak bits, and FDC metadata. It is opened as a Read-Only format.
// During loading, we extract the sectors, normalize them to 512 bytes, and assemble
// them into a flat virtual memory buffer to allow normal GEMDOS filesystem browsing.

import Foundation

final class STXDiskImage: DiskImage {

    // MARK: - Properties

    var formatName = "STX (Pasti - Read Only)"
    let geometry: DiskGeometry
    var isModified: Bool = false
    var sourceURL: URL?

    /// Flat raw sector data buffer assembled from STX sectors.
    private var raw: Data

    // MARK: - Init

    init(geometry: DiskGeometry, raw: Data) {
        self.geometry = geometry
        self.raw = raw
    }

    // MARK: - Sector I/O

    func readSector(_ logicalSector: Int) throws -> Data {
        guard logicalSector >= 0 && logicalSector < geometry.totalSectors else {
            throw DiskImageError.sectorOutOfRange(logicalSector)
        }
        let offset = logicalSector * geometry.bytesPerSector
        return raw.subdata(in: raw.startIndex + offset ..< raw.startIndex + offset + geometry.bytesPerSector)
    }

    func writeSector(_ logicalSector: Int, data: Data) throws {
        throw DiskImageError.readOnly
    }

    // MARK: - Persistence

    static func load(from url: URL) throws -> STXDiskImage {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DiskImageError.ioError(error)
        }

        guard data.count >= 16 else {
            throw DiskImageError.invalidFormat("File too small to contain a header.")
        }

        let sig = data.readBytes(at: 0, count: 4)
        guard sig == [0x52, 0x53, 0x59, 0x00] else {
            throw DiskImageError.invalidFormat("Invalid STX signature (expected 'RSY\\0').")
        }

        let version = data.readUInt16LE(at: 4)
        guard version == 3 else {
            throw DiskImageError.invalidFormat("Unsupported Pasti version \(version). Only version 3 is supported.")
        }

        let trackCount = Int(data.readUInt8(at: 10))

        // Structures for parsing
        struct SectorDesc {
            let offset: UInt32
            let bitPos: UInt16
            let readTime: UInt16
            let addrTrack: UInt8
            let addrHead: UInt8
            let addrNumber: UInt8
            let addrSize: UInt8
            let crc: UInt16
            let flags: UInt8
            let reserved: UInt8

            var sectorSize: Int { 128 << addrSize }
        }

        struct TrackRecord {
            let recordSize: UInt32
            let fuzzyCount: UInt32
            let sectorCount: UInt16
            let flags: UInt16
            let trackLen: UInt16
            let sideNumber: UInt8
            let type: UInt8
            let offset: Int

            var side: Int { Int(sideNumber >> 7) }
            var trackNum: Int { Int(sideNumber & 0x7F) }
        }

        var trackRecords: [TrackRecord] = []
        var allSectors: [(track: Int, side: Int, desc: SectorDesc, data: Data)] = []

        var maxTrack = 0
        var maxSide = 0
        var maxSectorNumber = 0

        var p = 16
        for _ in 0..<trackCount {
            guard p + 16 <= data.count else {
                throw DiskImageError.invalidFormat("Unexpected EOF reading track descriptor.")
            }

            let recordSize = data.readUInt32LE(at: p)
            let fuzzyCount = data.readUInt32LE(at: p + 4)
            let sectorCount = data.readUInt16LE(at: p + 8)
            let flags = data.readUInt16LE(at: p + 10)
            let trackLen = data.readUInt16LE(at: p + 12)
            let sideNumber = data.readUInt8(at: p + 14)
            let type = data.readUInt8(at: p + 15)

            let trk = TrackRecord(
                recordSize: recordSize,
                fuzzyCount: fuzzyCount,
                sectorCount: sectorCount,
                flags: flags,
                trackLen: trackLen,
                sideNumber: sideNumber,
                type: type,
                offset: p
            )
            trackRecords.append(trk)

            maxTrack = max(maxTrack, trk.trackNum)
            maxSide = max(maxSide, trk.side)

            // Read sector descriptors and payloads
            var sp = p + 16
            var sectorDescs: [SectorDesc] = []

            if (flags & 1) != 0 {
                for _ in 0..<Int(sectorCount) {
                    guard sp + 16 <= p + Int(recordSize) else {
                        throw DiskImageError.invalidFormat("Unexpected EOF reading sector descriptors.")
                    }

                    let offset = data.readUInt32LE(at: sp)
                    let bitPos = data.readUInt16LE(at: sp + 4)
                    let readTime = data.readUInt16LE(at: sp + 6)
                    let addrTrack = data.readUInt8(at: sp + 8)
                    let addrHead = data.readUInt8(at: sp + 9)
                    let addrNumber = data.readUInt8(at: sp + 10)
                    let addrSize = data.readUInt8(at: sp + 11)
                    let crc = data.readUInt16LE(at: sp + 12)
                    let sflags = data.readUInt8(at: sp + 14)
                    let reserved = data.readUInt8(at: sp + 15)

                    let desc = SectorDesc(
                        offset: offset, bitPos: bitPos, readTime: readTime,
                        addrTrack: addrTrack, addrHead: addrHead, addrNumber: addrNumber,
                        addrSize: addrSize, crc: crc, flags: sflags, reserved: reserved
                    )
                    sectorDescs.append(desc)
                    maxSectorNumber = max(maxSectorNumber, Int(addrNumber))
                    sp += 16
                }
            }

            let pimage = p + 16 + (16 * Int(sectorCount)) + Int(fuzzyCount)

            for desc in sectorDescs {
                let sectorSize = desc.sectorSize
                let srcStart = pimage + Int(desc.offset)
                let srcEnd = srcStart + sectorSize
                guard srcEnd <= p + Int(recordSize) && srcEnd <= data.count else {
                    throw DiskImageError.invalidFormat("Sector data offset out of bounds.")
                }

                let sectorData = data.subdata(in: srcStart..<srcEnd)
                allSectors.append((track: trk.trackNum, side: trk.side, desc: desc, data: sectorData))
            }

            p += Int(recordSize)
        }

        // Auto-detect geometry
        let sides = max(1, maxSide + 1)
        let sectorsPerTrack = max(9, maxSectorNumber)
        let tracks = max(80, maxTrack + 1)

        let geometry = DiskGeometry(tracks: tracks, sides: sides, sectorsPerTrack: sectorsPerTrack)

        // Assemble flat sector buffer (empty/unwritten sectors defaulted to 0xE5)
        var flatData = Data(repeating: 0xE5, count: geometry.totalBytes)

        for item in allSectors {
            guard item.desc.addrNumber >= 1 && Int(item.desc.addrNumber) <= sectorsPerTrack else {
                continue // Skip invalid sector numbers
            }
            guard item.track >= 0 && item.track < tracks && item.side >= 0 && item.side < sides else {
                continue
            }

            let logicalIndex = geometry.logical(track: item.track, side: item.side, sector: Int(item.desc.addrNumber))
            let offset = logicalIndex * geometry.bytesPerSector

            // Normalize sector size to exactly 512 bytes
            var normalizedData = item.data
            if normalizedData.count < 512 {
                normalizedData.append(Data(repeating: 0xE5, count: 512 - normalizedData.count))
            } else if normalizedData.count > 512 {
                normalizedData = normalizedData.subdata(in: normalizedData.startIndex..<normalizedData.startIndex + 512)
            }

            flatData.replaceSubrange(offset..<offset + 512, with: normalizedData)
        }

        let image = STXDiskImage(geometry: geometry, raw: flatData)
        image.sourceURL = url
        image.isModified = false
        return image
    }

    func serialise() throws -> Data {
        throw DiskImageError.readOnly
    }

    func save(to url: URL) throws {
        throw DiskImageError.readOnly
    }
}
