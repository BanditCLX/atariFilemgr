// GEMDOSDirectory.swift — AtariFileMgr
// Reads and writes 32-byte GEMDOS/FAT12 directory entries.
//
// Directory entry layout (32 bytes):
//  Offset  Size  Description
//  0       8     Filename (space padded; 0xE5=deleted, 0x00=end)
//  8       3     Extension (space padded)
//  11      1     Attributes (bit flags)
//  12      10    Reserved (TOS may store upper cluster word and creation time here)
//  22      2     Last modified time (FAT encoded)
//  24      2     Last modified date (FAT encoded)
//  26      2     First cluster (low word)
//  28      4     File size in bytes

import Foundation

struct GEMDOSDirectory {

    static let entrySize: Int = 32

    // MARK: - Parse directory sector(s) into entries

    /// Parse all valid (non-deleted, non-end) entries from raw directory data.
    /// `startSector` is used to record where each entry came from.
    static func parse(data: Data, startSector: Int, bytesPerSector: Int) -> [GEMDOSEntry] {
        var entries: [GEMDOSEntry] = []
        let count = data.count / entrySize

        for i in 0 ..< count {
            let offset = i * entrySize
            guard offset + entrySize <= data.count else { break }

            let firstByte = data.readUInt8(at: offset)
            if firstByte == 0x00 { break }   // end of directory
            if firstByte == 0xE5 { continue } // deleted entry

            let nameBytes = data.readBytes(at: offset,     count: 8)
            let extBytes  = data.readBytes(at: offset + 8, count: 3)
            let attr      = data.readUInt8(at:  offset + 11)
            let time      = data.readUInt16LE(at: offset + 22)
            let date      = data.readUInt16LE(at: offset + 24)
            let cluster   = data.readUInt16LE(at: offset + 26)
            let fileSize  = data.readUInt32LE(at: offset + 28)

            let attributes = FileAttributes(rawValue: attr)

            // Skip volume labels for directory listing purposes
            if attributes.isVolumeLabel && !attributes.isDirectory { continue }

            // Compute which sector and byte offset this entry resides in
            let absoluteByte = offset  // offset within data
            let sectorIndex  = absoluteByte / bytesPerSector
            let byteInSector = absoluteByte % bytesPerSector

            let parsed = Filename83.decode(nameBytes: nameBytes, extBytes: extBytes)

            let entry = GEMDOSEntry(
                id:              UUID(),
                name83:          parsed,
                attributes:      attributes,
                fatDate:         date,
                fatTime:         time,
                startCluster:    cluster,
                fileSize:        fileSize,
                directorySector: startSector + sectorIndex,
                directoryOffset: byteInSector
            )
            entries.append(entry)
        }
        return entries
    }

    // MARK: - Encode a single entry into 32 bytes

    /// Encode a GEMDOSEntry into its 32-byte raw representation.
    static func encode(_ entry: GEMDOSEntry) -> Data {
        var raw = Data.filled(count: entrySize)
        let (nameBytes, extBytes) = Filename83.encode(entry.displayName) ??
                                    (Array(repeating: 0x20, count: 8), Array(repeating: 0x20, count: 3))

        for i in 0..<8 { raw.writeUInt8(nameBytes[i], at: i) }
        for i in 0..<3 { raw.writeUInt8(extBytes[i],  at: 8 + i) }
        raw.writeUInt8(entry.attributes.rawValue, at: 11)
        // Bytes 12…21: reserved, leave as zero
        raw.writeUInt16LE(entry.fatTime,       at: 22)
        raw.writeUInt16LE(entry.fatDate,       at: 24)
        raw.writeUInt16LE(entry.startCluster,  at: 26)
        raw.writeUInt32LE(entry.fileSize,      at: 28)
        return raw
    }

    // MARK: - Create a new blank directory sector

    /// Returns a zeroed-out sector (all zeros = empty directory, first byte 0x00 = end marker).
    static func blankSector(size: Int) -> Data {
        Data.filled(count: size, with: 0x00)
    }

    // MARK: - Create "." and ".." entries for subdirectories

    static func dotEntry(cluster: UInt16, date: UInt16, time: UInt16) -> Data {
        let e = GEMDOSEntry(
            id: UUID(),
            name83: Filename83.Parsed(name: ".", ext: ""),
            attributes: .directory,
            fatDate: date, fatTime: time,
            startCluster: cluster, fileSize: 0,
            directorySector: 0, directoryOffset: 0
        )
        // Encode name manually: "." = [0x2E, 0x20×7] + [0x20×3]
        var raw = encode(e)
        raw.writeUInt8(0x2E, at: 0)
        for i in 1..<8 { raw.writeUInt8(0x20, at: i) }
        for i in 0..<3 { raw.writeUInt8(0x20, at: 8+i) }
        return raw
    }

    static func dotDotEntry(parentCluster: UInt16, date: UInt16, time: UInt16) -> Data {
        var raw = Data.filled(count: entrySize, with: 0x20)
        raw.writeUInt8(0x2E, at: 0)
        raw.writeUInt8(0x2E, at: 1)
        for i in 2..<8  { raw.writeUInt8(0x20, at: i)   }
        for i in 0..<3  { raw.writeUInt8(0x20, at: 8+i) }
        raw.writeUInt8(FileAttributes.directory.rawValue, at: 11)
        raw.writeUInt16LE(time, at: 22)
        raw.writeUInt16LE(date, at: 24)
        raw.writeUInt16LE(parentCluster, at: 26)
        raw.writeUInt32LE(0, at: 28)
        return raw
    }
}
