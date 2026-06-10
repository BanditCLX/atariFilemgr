// STDiskImage.swift — AtariFileMgr
// Implements the raw Atari ST .st disk image format.
//
// An .st file is a flat, uncompressed sector dump with no header.
// The geometry is inferred from the file size.
// Sectors are stored in logical order: track/side/sector.

import Foundation

final class STDiskImage: DiskImage {

    // MARK: - Properties

    var formatName = "ST (raw)"
    let geometry: DiskGeometry
    var isModified: Bool = false
    var sourceURL: URL?

    /// Flat in-memory buffer holding all sectors.
    private var raw: Data

    // MARK: - Init

    init(geometry: DiskGeometry) {
        self.geometry = geometry
        self.raw = Data(repeating: 0xE5, count: geometry.totalBytes)
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
        guard logicalSector >= 0 && logicalSector < geometry.totalSectors else {
            throw DiskImageError.sectorOutOfRange(logicalSector)
        }
        precondition(data.count == geometry.bytesPerSector,
                     "writeSector: data must be exactly \(geometry.bytesPerSector) bytes")
        let offset = logicalSector * geometry.bytesPerSector
        raw.replaceSubrange(raw.startIndex + offset ..< raw.startIndex + offset + geometry.bytesPerSector,
                            with: data)
        isModified = true
    }

    // MARK: - Load

    static func load(from url: URL) throws -> STDiskImage {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DiskImageError.ioError(error)
        }

        let ext = url.pathExtension.lowercased()
        if ext == "dim" && data.count >= 32 && data[0] == 0x42 && data[1] == 0x42 {
            // Parse F-Copy Pro .dim format
            let compression = data.readUInt8(at: 3)
            guard compression == 0 else {
                throw DiskImageError.invalidFormat("Compressed DIM files are not supported.")
            }
            let sidesField = data.readUInt8(at: 6)
            let sides = Int(sidesField) + 1
            let sectors = Int(data.readUInt8(at: 8))
            let startTrack = Int(data.readUInt8(at: 10))
            let endTrack = Int(data.readUInt8(at: 12))
            let tracks = endTrack - startTrack + 1

            guard tracks > 0, sides > 0, sectors > 0 else {
                throw DiskImageError.invalidFormat("Invalid DIM geometry fields.")
            }

            // Estimate sector size (standard is 512, but we can compute it)
            let calcSectors = sectors * tracks * sides
            let bytesPerSector = (data.count - 32) / calcSectors
            guard [128, 256, 512, 1024].contains(bytesPerSector) else {
                throw DiskImageError.invalidFormat("Invalid calculated sector size for DIM: \(bytesPerSector)")
            }

            let expectedPayloadSize = calcSectors * bytesPerSector
            guard data.count >= 32 + expectedPayloadSize else {
                throw DiskImageError.invalidFormat("DIM file size is smaller than geometry specifies.")
            }

            let geo = DiskGeometry(tracks: tracks, sides: sides, sectorsPerTrack: sectors, bytesPerSector: bytesPerSector)
            let image = STDiskImage(geometry: geo)
            image.raw = data.subdata(in: data.startIndex + 32 ..< data.startIndex + 32 + expectedPayloadSize)
            image.formatName = "Double Image (DIM)"
            image.sourceURL = url
            image.isModified = false
            return image

        } else if ext == "ahd" {
            // Parse AHDI .ahd hard disk partition image
            guard data.count >= 512 else {
                throw DiskImageError.invalidFormat("AHD file is too small")
            }
            
            // Primary partition table is in Sector 0.
            // Partition 1 starts at offset 448 (0x1C0)
            let pOffset = 448
            let pId = data.readASCIIString(at: pOffset + 1, length: 3)
            
            guard pId == "GEM" || pId == "BGM" else {
                throw DiskImageError.invalidFormat("No GEM or BGM partition found in AHD primary slot. ID: '\(pId)'")
            }
            
            let startSector = Int(data.readUInt32BE(at: pOffset + 4))
            let sizeSectors = Int(data.readUInt32BE(at: pOffset + 8))
            
            guard startSector > 0, sizeSectors > 0 else {
                throw DiskImageError.invalidFormat("Invalid partition table entries in AHD file.")
            }
            
            let partitionStartByte = startSector * 512
            let partitionSizeByte = sizeSectors * 512
            
            guard data.count >= partitionStartByte + 512 else {
                throw DiskImageError.invalidFormat("AHD file is missing partition start sector.")
            }
            
            guard data.count >= partitionStartByte + partitionSizeByte else {
                throw DiskImageError.invalidFormat("AHD file is smaller than partition size.")
            }
            
            // Parse BPB from partition's boot sector to get actual geometry values if possible
            let bootSectorData = data.subdata(in: data.startIndex + partitionStartByte ..< data.startIndex + partitionStartByte + 512)
            
            let bps = Int(bootSectorData.readUInt16LE(at: 11))
            let spt = Int(bootSectorData.readUInt16LE(at: 24))
            let heads = Int(bootSectorData.readUInt16LE(at: 26))
            
            let geo: DiskGeometry
            if [128, 256, 512, 1024].contains(bps), spt > 0, heads > 0 {
                let calculatedTracks = sizeSectors / (heads * spt)
                geo = DiskGeometry(tracks: calculatedTracks, sides: heads, sectorsPerTrack: spt, bytesPerSector: bps)
            } else {
                // Fallback geometry: flat mapping
                geo = DiskGeometry(tracks: sizeSectors, sides: 1, sectorsPerTrack: 1, bytesPerSector: 512)
            }
            
            let image = STDiskImage(geometry: geo)
            image.raw = data.subdata(in: data.startIndex + partitionStartByte ..< data.startIndex + partitionStartByte + partitionSizeByte)
            image.formatName = "AHD Hard Disk Partition"
            image.sourceURL = url
            image.isModified = false
            return image
        } else {
            // Standard raw ST format (or .dim without magic number)
            guard let geo = DiskGeometry.detect(fileSize: data.count, fileData: data) else {
                throw DiskImageError.unknownGeometry(data.count)
            }

            let image = STDiskImage(geometry: geo)
            var fileData = data
            if fileData.count < geo.totalBytes {
                let paddingCount = geo.totalBytes - fileData.count
                fileData.append(Data(repeating: 0xE5, count: paddingCount))
            }
            image.raw = fileData
            if ext == "dim" {
                image.formatName = "ST (raw) [renamed .dim]"
            }
            image.sourceURL = url
            image.isModified = false
            return image
        }
    }

    // MARK: - Serialise / Save

    func serialise() throws -> Data { raw }
}
