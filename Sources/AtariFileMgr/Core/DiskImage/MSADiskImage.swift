// MSADiskImage.swift — AtariFileMgr
// Implements the Magic Shadow Archiver (.msa) disk image format.
//
// MSA Header (10 bytes, all fields big-endian):
//   0x0E0F       magic word
//   sectorsPerTrack  UInt16
//   sides            UInt16  (0 = 1 side, 1 = 2 sides)
//   startTrack       UInt16  (0-based)
//   endTrack         UInt16  (0-based, inclusive)
//
// Body: alternating tracks T0S0, T0S1, T1S0, T1S1, ...
// Each track block:
//   dataLength   UInt16 (big-endian)
//   data         [dataLength bytes]
//
// Compression: RLE with marker byte 0xE5
//   Uncompressed:  dataLength == sectorsPerTrack * 512
//   Compressed:    dataLength < sectorsPerTrack * 512
//
// RLE encoding:
//   Normal byte  b  (b != 0xE5): copy as-is
//   [0xE5][byte][word count]:    emit `byte` repeated `count` times
//   Special case: [0xE5][0xE5][0x0001]: literal 0xE5

import Foundation

final class MSADiskImage: DiskImage {

    // MARK: - Constants

    private static let magic: UInt16 = 0x0E0F
    private static let rleMarker: UInt8 = 0xE5

    // MARK: - Properties

    let formatName = "MSA (Magic Shadow Archiver)"
    let geometry: DiskGeometry
    var isModified: Bool = false
    var sourceURL: URL?

    /// Decoded raw sectors stored as a flat buffer (same as STDiskImage).
    private var raw: Data

    // MARK: - Init

    init(geometry: DiskGeometry) {
        self.geometry = geometry
        self.raw = Data(repeating: 0xE5, count: geometry.totalBytes)
    }

    // MARK: - Sector I/O (delegates to flat buffer)

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
        let offset = logicalSector * geometry.bytesPerSector
        raw.replaceSubrange(raw.startIndex + offset ..< raw.startIndex + offset + geometry.bytesPerSector,
                            with: data)
        isModified = true
    }

    // MARK: - Load & Decode

    static func load(from url: URL) throws -> MSADiskImage {
        let fileData: Data
        do {
            fileData = try Data(contentsOf: url)
        } catch {
            throw DiskImageError.ioError(error)
        }

        guard fileData.count >= 10 else {
            throw DiskImageError.invalidFormat("File too small for MSA header")
        }
        guard fileData.readUInt16BE(at: 0) == magic else {
            throw DiskImageError.invalidFormat("MSA magic number mismatch")
        }

        let sectorsPerTrack = Int(fileData.readUInt16BE(at: 2))
        let sidesField      = Int(fileData.readUInt16BE(at: 4))
        let startTrack      = Int(fileData.readUInt16BE(at: 6))
        let endTrack        = Int(fileData.readUInt16BE(at: 8))
        let sides           = sidesField + 1
        let _ = endTrack - startTrack + 1  // tracks (used via endTrack + 1 below)

        let geo = DiskGeometry(tracks: endTrack + 1,
                               sides: sides,
                               sectorsPerTrack: sectorsPerTrack)

        let image = MSADiskImage(geometry: geo)

        // Fill with 0xE5 (unformatted), then overwrite decoded track data
        image.raw = Data(repeating: 0xE5, count: geo.totalBytes)

        var cursor = 10  // byte position in fileData
        let trackDataSize = sectorsPerTrack * 512

        for trackIdx in startTrack ... endTrack {
            for side in 0 ..< sides {
                guard cursor + 2 <= fileData.count else {
                    throw DiskImageError.invalidFormat("Unexpected end of MSA file at track \(trackIdx) side \(side)")
                }
                let dataLen = Int(fileData.readUInt16BE(at: cursor))
                cursor += 2

                guard cursor + dataLen <= fileData.count else {
                    throw DiskImageError.invalidFormat("MSA track data truncated at track \(trackIdx) side \(side)")
                }
                let trackData = fileData.subdata(in: fileData.startIndex + cursor ..< fileData.startIndex + cursor + dataLen)
                cursor += dataLen

                let decodedTrack: Data
                if dataLen == trackDataSize {
                    decodedTrack = trackData  // uncompressed
                } else {
                    decodedTrack = try Self.rleDecompress(trackData, expectedSize: trackDataSize)
                }

                // Write decoded track into flat raw buffer
                let firstLogical = geo.logical(track: trackIdx, side: side, sector: 1)
                let byteOffset   = firstLogical * geo.bytesPerSector
                image.raw.replaceSubrange(
                    image.raw.startIndex + byteOffset ..<
                    image.raw.startIndex + byteOffset + trackDataSize,
                    with: decodedTrack
                )
            }
        }

        image.sourceURL = url
        image.isModified = false
        return image
    }

    // MARK: - Serialise & Encode

    func serialise() throws -> Data {
        var result = Data()

        let spt   = geometry.sectorsPerTrack
        let sides = geometry.sides
        let tracks = geometry.tracks
        let trackDataSize = spt * geometry.bytesPerSector

        // MSA header (big-endian)
        var header = Data(count: 10)
        header.writeUInt16BE(Self.magic,      at: 0)
        header.writeUInt16BE(UInt16(spt),     at: 2)
        header.writeUInt16BE(UInt16(sides-1), at: 4)
        header.writeUInt16BE(0,               at: 6)  // startTrack
        header.writeUInt16BE(UInt16(tracks-1), at: 8) // endTrack
        result.append(header)

        for trackIdx in 0 ..< tracks {
            for side in 0 ..< sides {
                let firstLogical = geometry.logical(track: trackIdx, side: side, sector: 1)
                let byteOffset   = firstLogical * geometry.bytesPerSector
                let trackData    = raw.subdata(in: raw.startIndex + byteOffset ..<
                                                  raw.startIndex + byteOffset + trackDataSize)

                let compressed   = Self.rleCompress(trackData)

                if compressed.count < trackDataSize {
                    // Write compressed block
                    var lenWord = Data(count: 2)
                    lenWord.writeUInt16BE(UInt16(compressed.count), at: 0)
                    result.append(lenWord)
                    result.append(compressed)
                } else {
                    // Write uncompressed block
                    var lenWord = Data(count: 2)
                    lenWord.writeUInt16BE(UInt16(trackDataSize), at: 0)
                    result.append(lenWord)
                    result.append(trackData)
                }
            }
        }
        return result
    }

    // MARK: - RLE Decompression

    private static func rleDecompress(_ data: Data, expectedSize: Int) throws -> Data {
        var output = Data()
        output.reserveCapacity(expectedSize)
        var i = data.startIndex

        while i < data.endIndex {
            let byte = data[i]
            i = data.index(after: i)

            if byte != rleMarker {
                output.append(byte)
            } else {
                // Need at least 3 more bytes: [byte][wordHi][wordLo]
                guard i < data.endIndex else {
                    throw DiskImageError.invalidFormat("RLE: unexpected end after marker")
                }
                let fillByte = data[i]
                i = data.index(after: i)
                guard i < data.endIndex else {
                    throw DiskImageError.invalidFormat("RLE: unexpected end reading count (hi)")
                }
                let countHi = UInt16(data[i])
                i = data.index(after: i)
                guard i < data.endIndex else {
                    throw DiskImageError.invalidFormat("RLE: unexpected end reading count (lo)")
                }
                let countLo = UInt16(data[i])
                i = data.index(after: i)

                let count = (countHi << 8) | countLo
                for _ in 0 ..< count {
                    output.append(fillByte)
                }
            }
        }

        guard output.count == expectedSize else {
            throw DiskImageError.invalidFormat(
                "RLE: decoded \(output.count) bytes, expected \(expectedSize)")
        }
        return output
    }

    // MARK: - RLE Compression

    private static func rleCompress(_ data: Data) -> Data {
        var output = Data()
        output.reserveCapacity(data.count)
        var i = data.startIndex

        while i < data.endIndex {
            let byte = data[i]
            // Count run length
            var runEnd = i
            while runEnd < data.endIndex && data[runEnd] == byte && data.distance(from: i, to: runEnd) < 0xFFFF {
                runEnd = data.index(after: runEnd)
            }
            let runLen = data.distance(from: i, to: runEnd)

            // Decide whether to RLE-encode this run
            // RLE encoding costs 4 bytes (marker + byte + 2-byte count)
            // Worth it for runs of 5+ identical bytes, or if byte == 0xE5 (must always encode)
            let mustEncode = byte == rleMarker
            if mustEncode || runLen >= 5 {
                output.append(rleMarker)
                output.append(byte)
                output.append(UInt8((runLen >> 8) & 0xFF))
                output.append(UInt8(runLen & 0xFF))
            } else {
                for _ in 0 ..< runLen { output.append(byte) }
            }
            i = runEnd
        }
        return output
    }
}
