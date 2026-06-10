// BootSector.swift — AtariFileMgr
// Parses and creates Atari ST boot sectors (GEMDOS/FAT12 BPB).
//
// The Atari ST boot sector is 512 bytes:
//  Offset  Size  Field
//  0       3     Jump instruction (0x60 nn 0x90 or 0xEB nn 0x90)
//  3       8     OEM identifier string
//  11      2     Bytes per sector (LE, always 512)
//  13      1     Sectors per cluster
//  14      2     Reserved sectors (1 = just the boot sector)
//  16      1     Number of FAT copies (2)
//  17      2     Max root directory entries (112 for DS/DD, 224 for HD)
//  19      2     Total sector count (16-bit), 0 if > 65535
//  21      1     Media descriptor byte (0xF9 DS/DD, 0xF0 HD)
//  22      2     Sectors per FAT
//  24      2     Sectors per track
//  26      2     Number of heads (sides)
//  28      4     Hidden sectors (0)
//  32      4     Total sector count (32-bit), used if 16-bit field = 0
//  36      476   Boot code / reserved
//
// Bootable disks: the sum of all 256 words in the 512-byte sector must equal 0x1234.

import Foundation

struct BootSector {

    // MARK: - Parsed fields

    var bytesPerSector:    UInt16
    var sectorsPerCluster: UInt8
    var reservedSectors:   UInt16
    var fatCount:          UInt8
    var rootEntryCount:    UInt16
    var totalSectors16:    UInt16
    var mediaDescriptor:   UInt8
    var sectorsPerFAT:     UInt16
    var sectorsPerTrack:   UInt16
    var numberOfHeads:     UInt16
    var hiddenSectors:     UInt32
    var totalSectors32:    UInt32
    var oemName:           String
    var rawData:           Data     // full 512-byte sector

    // MARK: - Computed helpers

    var totalSectors: Int {
        totalSectors16 > 0 ? Int(totalSectors16) : Int(totalSectors32)
    }

    /// Sector number where the first FAT starts.
    var fatStartSector: Int { max(1, Int(reservedSectors)) }

    /// Sector number where the second FAT starts (if fatCount == 2).
    var fat2StartSector: Int { fatStartSector + Int(sectorsPerFAT) }

    /// Sector number where the root directory starts.
    var rootDirStartSector: Int {
        fatStartSector + Int(fatCount) * Int(sectorsPerFAT)
    }

    /// Number of sectors occupied by the root directory.
    var rootDirSectorCount: Int {
        (Int(rootEntryCount) * 32 + Int(bytesPerSector) - 1) / Int(bytesPerSector)
    }

    /// Sector number where the data area (clusters ≥ 2) starts.
    var firstDataSector: Int {
        rootDirStartSector + rootDirSectorCount
    }

    /// Total number of data clusters.
    var clusterCount: Int {
        (totalSectors - firstDataSector) / Int(sectorsPerCluster)
    }

    // MARK: - Parse

    /// Parse a boot sector from the first 512 bytes of the image.
    static func parse(from data: Data) throws -> BootSector {
        guard data.count >= 512 else {
            throw DiskImageError.invalidFormat("Boot sector too small (\(data.count) bytes)")
        }
        let sector = data.prefix(512)
        return BootSector(
            bytesPerSector:    sector.readUInt16LE(at: 11),
            sectorsPerCluster: sector.readUInt8(at: 13),
            reservedSectors:   sector.readUInt16LE(at: 14),
            fatCount:          sector.readUInt8(at: 16),
            rootEntryCount:    sector.readUInt16LE(at: 17),
            totalSectors16:    sector.readUInt16LE(at: 19),
            mediaDescriptor:   sector.readUInt8(at: 21),
            sectorsPerFAT:     sector.readUInt16LE(at: 22),
            sectorsPerTrack:   sector.readUInt16LE(at: 24),
            numberOfHeads:     sector.readUInt16LE(at: 26),
            hiddenSectors:     sector.readUInt32LE(at: 28),
            totalSectors32:    sector.readUInt32LE(at: 32),
            oemName:           sector.readASCIIString(at: 3, length: 8),
            rawData:           Data(sector)
        )
    }

    // MARK: - Create (new blank disk)

    /// Create a blank, formatted boot sector for the given disk format.
    static func makeBlank(format: DiskFormat) -> BootSector {
        let geo = format.geometry
        let bpb = format.bpb
        var raw = Data.filled(count: 512, with: 0x00)

        // Jump: BRA.S (short branch) over the BPB — typical TOS pattern
        raw.writeUInt8(0x60, at: 0)  // BRA.S opcode
        raw.writeUInt8(0x1C, at: 1)  // branch offset (skips over BPB)
        raw.writeUInt8(0x00, at: 2)

        // OEM name
        raw.writeASCIIString("ATARIFILEMGR"[...].prefix(8).description,
                             at: 3, length: 8)

        // BPB
        let totalSectors = UInt16(geo.totalSectors)
        raw.writeUInt16LE(UInt16(geo.bytesPerSector), at: 11)
        raw.writeUInt8(bpb.sectorsPerCluster, at: 13)
        raw.writeUInt16LE(1,  at: 14)  // reserved sectors
        raw.writeUInt8(2,     at: 16)  // 2 FATs
        raw.writeUInt16LE(bpb.rootEntryCount, at: 17)
        raw.writeUInt16LE(totalSectors, at: 19)
        raw.writeUInt8(bpb.mediaType, at: 21)
        raw.writeUInt16LE(bpb.sectorsPerFAT, at: 22)
        raw.writeUInt16LE(UInt16(geo.sectorsPerTrack), at: 24)
        raw.writeUInt16LE(UInt16(geo.sides), at: 26)
        raw.writeUInt32LE(0, at: 28)  // hidden sectors
        raw.writeUInt32LE(0, at: 32)  // total sectors 32-bit (0 = use 16-bit field)

        // Patch checksum to make the disk bootable (sum of words == 0x1234)
        raw = patchBootChecksum(raw)

        return (try? parse(from: raw)) ?? {
            fatalError("BootSector.makeBlank: internal parse failed")
        }()
    }

    /// Create a blank, formatted boot sector for a custom disk geometry.
    static func makeBlank(geometry geo: DiskGeometry) -> BootSector {
        let totalSectors = geo.totalSectors
        let isHD = geo.sectorsPerTrack >= 18 || totalSectors > 2000
        let isSS = geo.sides == 1
        
        let mediaType: UInt8 = isHD ? 0xF0 : (isSS ? 0xF8 : 0xF9)
        let sectorsPerCluster: UInt8 = isHD ? 1 : 2
        let rootEntryCount: UInt16 = isHD ? 224 : 112
        let sectorsPerFAT: UInt16 = isHD ? 9 : 5
        
        var raw = Data.filled(count: 512, with: 0x00)

        // Jump: BRA.S (short branch) over the BPB — typical TOS pattern
        raw.writeUInt8(0x60, at: 0)  // BRA.S opcode
        raw.writeUInt8(0x1C, at: 1)  // branch offset (skips over BPB)
        raw.writeUInt8(0x00, at: 2)

        // OEM name
        raw.writeASCIIString("ATARIFILEMGR"[...].prefix(8).description,
                             at: 3, length: 8)

        // BPB
        raw.writeUInt16LE(UInt16(geo.bytesPerSector), at: 11)
        raw.writeUInt8(sectorsPerCluster, at: 13)
        raw.writeUInt16LE(1,  at: 14)  // reserved sectors
        raw.writeUInt8(2,     at: 16)  // 2 FATs
        raw.writeUInt16LE(rootEntryCount, at: 17)
        raw.writeUInt16LE(UInt16(geo.totalSectors), at: 19)
        raw.writeUInt8(mediaType, at: 21)
        raw.writeUInt16LE(sectorsPerFAT, at: 22)
        raw.writeUInt16LE(UInt16(geo.sectorsPerTrack), at: 24)
        raw.writeUInt16LE(UInt16(geo.sides), at: 26)
        raw.writeUInt32LE(0, at: 28)  // hidden sectors
        raw.writeUInt32LE(0, at: 32)  // total sectors 32-bit (0 = use 16-bit field)

        // Patch checksum to make the disk bootable (sum of words == 0x1234)
        raw = patchBootChecksum(raw)

        return (try? parse(from: raw)) ?? {
            fatalError("BootSector.makeBlank: internal parse failed")
        }()
    }

    // MARK: - Bootable checksum

    /// Compute the current word-sum of a 512-byte boot sector.
    static func bootChecksum(_ data: Data) -> UInt16 {
        precondition(data.count >= 512)
        var sum: UInt32 = 0
        for i in stride(from: 0, to: 512, by: 2) {
            let word = UInt32(data.readUInt16BE(at: i))
            sum = (sum + word) & 0xFFFF
        }
        return UInt16(sum)
    }

    /// Adjust the last two bytes of a boot sector so the checksum equals 0x1234.
    static func patchBootChecksum(_ data: Data) -> Data {
        var d = data
        // Zero out the patch bytes first
        d.writeUInt16BE(0x0000, at: 510)
        let current = bootChecksum(d)
        // We need: current + patch == 0x1234 (mod 0x10000)
        let patch = UInt16((0x1234 &- UInt32(current)) & 0xFFFF)
        d.writeUInt16BE(patch, at: 510)
        return d
    }

    /// Returns true if this boot sector has a valid Atari boot checksum.
    var isBootable: Bool {
        Self.bootChecksum(rawData) == 0x1234
    }

    // MARK: - Serialise changes back into rawData

    /// Write the current BPB fields back into rawData.
    mutating func serialise() {
        rawData.writeUInt16LE(bytesPerSector,    at: 11)
        rawData.writeUInt8(sectorsPerCluster,    at: 13)
        rawData.writeUInt16LE(reservedSectors,   at: 14)
        rawData.writeUInt8(fatCount,             at: 16)
        rawData.writeUInt16LE(rootEntryCount,    at: 17)
        rawData.writeUInt16LE(totalSectors16,    at: 19)
        rawData.writeUInt8(mediaDescriptor,      at: 21)
        rawData.writeUInt16LE(sectorsPerFAT,     at: 22)
        rawData.writeUInt16LE(sectorsPerTrack,   at: 24)
        rawData.writeUInt16LE(numberOfHeads,     at: 26)
        rawData.writeUInt32LE(hiddenSectors,     at: 28)
        rawData.writeUInt32LE(totalSectors32,    at: 32)
    }
}
