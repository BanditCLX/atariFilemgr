// GEMDOSFilesystem.swift — AtariFileMgr
// High-level GEMDOS/FAT12 filesystem operations.
//
// This class sits on top of a DiskImage and provides:
//  - Directory listing
//  - File read/write
//  - Directory creation/deletion
//  - File copy, move, rename, delete
//  - Disk info (free space, etc.)
//
// All mutating operations keep both FAT copies in sync.
// The filesystem caches the boot sector, FAT, and does lazy sector reads.

import Foundation

final class GEMDOSFilesystem {

    // MARK: - State

    let image: any DiskImage
    private(set) var bootSector: BootSector
    private var fat: FAT12

    // MARK: - Init & Mount

    init(image: any DiskImage) throws {
        self.image = image

        // Read boot sector (logical sector 0)
        let bootData = try image.readSector(0)
        self.bootSector = try BootSector.parse(from: bootData)

        // Read first FAT
        let fatStart = bootSector.fatStartSector
        var fatBytes: [UInt8] = []
        for s in fatStart ..< fatStart + Int(bootSector.sectorsPerFAT) {
            let sector = try image.readSector(s)
            fatBytes.append(contentsOf: sector)
        }
        self.fat = FAT12(bytes: fatBytes, bootSector: bootSector)
    }

    // MARK: - Disk Info

    var totalBytes: Int    { image.geometry.totalBytes }
    var freeBytes: Int     { fat.freeBytesAvailable }
    var usedBytes: Int     { totalBytes - freeBytes }
    var clusterSize: Int   { Int(bootSector.sectorsPerCluster) * Int(bootSector.bytesPerSector) }

    // MARK: - Directory listing

    /// List all entries in the root directory.
    func listRootDirectory() throws -> [GEMDOSEntry] {
        var data = Data()
        for s in bootSector.rootDirStartSector ..< bootSector.rootDirStartSector + bootSector.rootDirSectorCount {
            data.append(try image.readSector(s))
        }
        return GEMDOSDirectory.parse(data: data,
                                     startSector: bootSector.rootDirStartSector,
                                     bytesPerSector: Int(bootSector.bytesPerSector))
    }

    /// List entries in a subdirectory given its starting cluster.
    func listDirectory(cluster: UInt16) throws -> [GEMDOSEntry] {
        let data = try readClusterChain(startCluster: cluster)
        let firstSector = fat.firstSector(of: cluster)
        return GEMDOSDirectory.parse(data: data,
                                     startSector: firstSector,
                                     bytesPerSector: Int(bootSector.bytesPerSector))
            .filter { $0.displayName != "." && $0.displayName != ".." }
    }

    // MARK: - File read

    /// Read the entire contents of a file entry.
    func readFile(_ entry: GEMDOSEntry) throws -> Data {
        guard entry.isFile else { throw GEMDOSError.notAFile(entry.displayName) }
        if entry.startCluster < 2 { return Data() }
        let raw = try readClusterChain(startCluster: entry.startCluster)
        // Truncate to actual file size
        return raw.prefix(Int(entry.fileSize))
    }

    /// Read up to `maxLength` bytes from the beginning of the file (reads first cluster only).
    func readFilePrefix(_ entry: GEMDOSEntry, maxLength: Int) throws -> Data {
        guard entry.isFile else { throw GEMDOSError.notAFile(entry.displayName) }
        if entry.startCluster < 2 { return Data() }
        
        let chain = fat.clusterChain(startingAt: entry.startCluster)
        guard let firstCluster = chain.first else { return Data() }
        
        let sectorsPerCluster = Int(bootSector.sectorsPerCluster)
        let firstSector = fat.firstSector(of: firstCluster)
        
        var result = Data()
        for s in firstSector ..< firstSector + sectorsPerCluster {
            result.append(try image.readSector(s))
            if result.count >= maxLength {
                break
            }
        }
        let limit = min(Int(entry.fileSize), maxLength)
        return result.prefix(limit)
    }

    // MARK: - File write (create or overwrite)

    /// Write data as a file named `name83` in the directory at `dirCluster`.
    /// Pass `dirCluster = 0` for the root directory.
    @discardableResult
    func writeFile(name: String, data: Data, inDirectoryCluster dirCluster: UInt16) throws -> GEMDOSEntry {
        let sanitised = Filename83.sanitise(name)
        guard let encoded = Filename83.encode(sanitised) else {
            throw GEMDOSError.invalidName(name)
        }

        // Check for duplicate
        let existing = dirCluster == 0 ? try listRootDirectory() : try listDirectory(cluster: dirCluster)
        if existing.contains(where: { $0.displayName.uppercased() == sanitised.uppercased() }) {
            throw GEMDOSError.fileAlreadyExists(sanitised)
        }

        // Allocate clusters for file data
        let clustersNeeded = max(1, (data.count + clusterSize - 1) / clusterSize)
        let startCluster: UInt16
        if data.isEmpty {
            startCluster = 0
        } else {
            startCluster = try fat.allocate(clusterCount: clustersNeeded)
            try writeClusterChain(data: data, startCluster: startCluster)
        }

        // Build directory entry
        let (fatDate, fatTime) = DateConverter.fatTimestamp(from: Date())
        var entry = GEMDOSEntry(
            id: UUID(),
            name83: Filename83.decode(nameBytes: encoded.name, extBytes: encoded.ext),
            attributes: .archive,
            fatDate: fatDate, fatTime: fatTime,
            startCluster: startCluster,
            fileSize: UInt32(data.count),
            directorySector: 0, directoryOffset: 0
        )

        // Write directory entry
        try appendDirectoryEntry(&entry, dirCluster: dirCluster)

        // Flush FAT
        try flushFAT()

        return entry
    }

    // MARK: - Create directory

    @discardableResult
    func createDirectory(name: String, inDirectoryCluster parentCluster: UInt16) throws -> GEMDOSEntry {
        let sanitised = Filename83.sanitise(name.uppercased())

        // Check duplicate
        let existing = parentCluster == 0 ? try listRootDirectory() : try listDirectory(cluster: parentCluster)
        if existing.contains(where: { $0.displayName.uppercased() == sanitised.uppercased() }) {
            throw GEMDOSError.fileAlreadyExists(sanitised)
        }

        // Allocate one cluster for directory data
        let newCluster = try fat.allocate(clusterCount: 1)
        let sectorSize = Int(bootSector.bytesPerSector)
        let sectorsPerCluster = Int(bootSector.sectorsPerCluster)
        let (fatDate, fatTime) = DateConverter.fatTimestamp(from: Date())

        // Write . and .. entries plus zeroes for the rest
        var dirData = Data()
        dirData.append(GEMDOSDirectory.dotEntry(cluster: newCluster, date: fatDate, time: fatTime))
        dirData.append(GEMDOSDirectory.dotDotEntry(parentCluster: parentCluster, date: fatDate, time: fatTime))
        let totalSize = sectorsPerCluster * sectorSize
        if dirData.count < totalSize {
            dirData.append(Data(repeating: 0x00, count: totalSize - dirData.count))
        }
        try writeClusterChain(data: dirData, startCluster: newCluster)

        // Build and add directory entry
        guard let encoded = Filename83.encode(sanitised) else {
            throw GEMDOSError.invalidName(sanitised)
        }
        var entry = GEMDOSEntry(
            id: UUID(),
            name83: Filename83.decode(nameBytes: encoded.name, extBytes: encoded.ext),
            attributes: .directory,
            fatDate: fatDate, fatTime: fatTime,
            startCluster: newCluster,
            fileSize: 0,
            directorySector: 0, directoryOffset: 0
        )
        try appendDirectoryEntry(&entry, dirCluster: parentCluster)
        try flushFAT()
        return entry
    }

    // MARK: - Delete

    /// Delete a file or empty directory.
    func delete(_ entry: GEMDOSEntry) throws {
        // Mark directory entry as deleted (first byte = 0xE5)
        var sector = try image.readSector(entry.directorySector)
        sector.writeUInt8(0xE5, at: entry.directoryOffset)
        try image.writeSector(entry.directorySector, data: sector)

        // Free clusters
        if entry.startCluster >= 2 {
            fat.freeChain(startingAt: entry.startCluster)
        }
        try flushFAT()
    }

    // MARK: - Rename

    /// Rename an entry in-place (same directory, same cluster).
    func rename(_ entry: GEMDOSEntry, to newName: String) throws {
        let sanitised = Filename83.sanitise(newName)
        guard let encoded = Filename83.encode(sanitised) else {
            throw GEMDOSError.invalidName(newName)
        }
        var sector = try image.readSector(entry.directorySector)
        let off = entry.directoryOffset
        for i in 0..<8 { sector.writeUInt8(encoded.name[i], at: off + i) }
        for i in 0..<3 { sector.writeUInt8(encoded.ext[i],  at: off + 8 + i) }
        try image.writeSector(entry.directorySector, data: sector)
    }

    // MARK: - Copy / Move

    /// Copy `entry` (file) into `destDirCluster`.
    func copyFile(_ entry: GEMDOSEntry, toDirectoryCluster destDirCluster: UInt16) throws {
        let data = try readFile(entry)
        try writeFile(name: entry.displayName, data: data, inDirectoryCluster: destDirCluster)
    }

    /// Move `entry` to `destDirCluster` (copy + delete from source).
    func moveFile(_ entry: GEMDOSEntry, toDirectoryCluster destDirCluster: UInt16) throws {
        try copyFile(entry, toDirectoryCluster: destDirCluster)
        try delete(entry)
    }

    // MARK: - Cluster I/O helpers

    /// Read the entire cluster chain for a given starting cluster.
    private func readClusterChain(startCluster: UInt16) throws -> Data {
        let chain = fat.clusterChain(startingAt: startCluster)
        var result = Data()
        let _ = Int(bootSector.bytesPerSector) // sectorSize used via readSector size
        let sectorsPerCluster = Int(bootSector.sectorsPerCluster)

        for cluster in chain {
            let firstSector = fat.firstSector(of: cluster)
            for s in firstSector ..< firstSector + sectorsPerCluster {
                result.append(try image.readSector(s))
            }
        }
        return result
    }

    /// Write data into a pre-allocated cluster chain.
    private func writeClusterChain(data: Data, startCluster: UInt16) throws {
        let chain = fat.clusterChain(startingAt: startCluster)
        let sectorSize = Int(bootSector.bytesPerSector)
        let sectorsPerCluster = Int(bootSector.sectorsPerCluster)
        var dataOffset = 0

        for cluster in chain {
            let firstSector = fat.firstSector(of: cluster)
            for s in firstSector ..< firstSector + sectorsPerCluster {
                var sectorData = Data(repeating: 0x00, count: sectorSize)
                let remaining = data.count - dataOffset
                if remaining > 0 {
                    let copyLen = min(sectorSize, remaining)
                    sectorData.replaceSubrange(
                        sectorData.startIndex ..< sectorData.startIndex + copyLen,
                        with: data[data.startIndex + dataOffset ..< data.startIndex + dataOffset + copyLen]
                    )
                    dataOffset += copyLen
                }
                try image.writeSector(s, data: sectorData)
            }
        }
    }

    // MARK: - Directory entry helpers

    /// Append a new directory entry to the root or a subdirectory.
    private func appendDirectoryEntry(_ entry: inout GEMDOSEntry, dirCluster: UInt16) throws {
        let entryData = GEMDOSDirectory.encode(entry)
        let sectorSize = Int(bootSector.bytesPerSector)

        if dirCluster == 0 {
            // Root directory: fixed size, scan for free slot
            for s in bootSector.rootDirStartSector ..< bootSector.rootDirStartSector + bootSector.rootDirSectorCount {
                var sector = try image.readSector(s)
                for offset in stride(from: 0, to: sectorSize, by: 32) {
                    let firstByte = sector.readUInt8(at: offset)
                    if firstByte == 0x00 || firstByte == 0xE5 {
                        // Free slot found
                        sector.replaceSubrange(
                            sector.startIndex + offset ..< sector.startIndex + offset + 32,
                            with: entryData
                        )
                        // Ensure end-of-directory marker follows if next slot is zero
                        if firstByte == 0xE5 && offset + 32 < sectorSize {
                            let nextByte = sector.readUInt8(at: offset + 32)
                            if nextByte != 0x00 && nextByte != 0xE5 {
                                // leave as-is; there are more entries after
                            }
                        }
                        try image.writeSector(s, data: sector)
                        entry = GEMDOSEntry(
                            id: entry.id, name83: entry.name83, attributes: entry.attributes,
                            fatDate: entry.fatDate, fatTime: entry.fatTime,
                            startCluster: entry.startCluster, fileSize: entry.fileSize,
                            directorySector: s, directoryOffset: offset
                        )
                        return
                    }
                }
            }
            throw GEMDOSError.directoryFull
        } else {
            // Subdirectory: may need to allocate more clusters
            let chain = fat.clusterChain(startingAt: dirCluster)
            for cluster in chain {
                let firstSector = fat.firstSector(of: cluster)
                let sectorsPerCluster = Int(bootSector.sectorsPerCluster)
                for sectorIdx in 0 ..< sectorsPerCluster {
                    let s = firstSector + sectorIdx
                    var sector = try image.readSector(s)
                    for offset in stride(from: 0, to: sectorSize, by: 32) {
                        let firstByte = sector.readUInt8(at: offset)
                        if firstByte == 0x00 || firstByte == 0xE5 {
                            sector.replaceSubrange(
                                sector.startIndex + offset ..< sector.startIndex + offset + 32,
                                with: entryData
                            )
                            try image.writeSector(s, data: sector)
                            entry = GEMDOSEntry(
                                id: entry.id, name83: entry.name83, attributes: entry.attributes,
                                fatDate: entry.fatDate, fatTime: entry.fatTime,
                                startCluster: entry.startCluster, fileSize: entry.fileSize,
                                directorySector: s, directoryOffset: offset
                            )
                            return
                        }
                    }
                }
            }
            // Need to grow directory: allocate one more cluster
            let lastCluster = chain.last ?? dirCluster
            let newCluster = try fat.allocate(clusterCount: 1)
            fat.setEntry(newCluster, for: lastCluster)     // link old end to new
            fat.setEntry(FAT12.eocMarker, for: newCluster) // new end-of-chain

            // Zero out new cluster
            let firstSector  = fat.firstSector(of: newCluster)
            let sectorsPerCluster = Int(bootSector.sectorsPerCluster)
            for sectorIdx in 0 ..< sectorsPerCluster {
                try image.writeSector(firstSector + sectorIdx, data: Data(repeating: 0x00, count: sectorSize))
            }

            // Write entry into first slot of new cluster
            var sector = try image.readSector(firstSector)
            sector.replaceSubrange(sector.startIndex ..< sector.startIndex + 32, with: entryData)
            try image.writeSector(firstSector, data: sector)
            entry = GEMDOSEntry(
                id: entry.id, name83: entry.name83, attributes: entry.attributes,
                fatDate: entry.fatDate, fatTime: entry.fatTime,
                startCluster: entry.startCluster, fileSize: entry.fileSize,
                directorySector: firstSector, directoryOffset: 0
            )
            try flushFAT()
        }
    }

    // MARK: - FAT flush

    /// Write the FAT back to both FAT copies on the disk.
    private func flushFAT() throws {
        let fatData = fat.rawData
        let sectorSize = Int(bootSector.bytesPerSector)
        let sectorsPerFAT = Int(bootSector.sectorsPerFAT)

        for copy in 0 ..< Int(bootSector.fatCount) {
            let startSector = bootSector.fatStartSector + copy * sectorsPerFAT
            for i in 0 ..< sectorsPerFAT {
                let offset = i * sectorSize
                let slice = fatData.subdata(in: fatData.startIndex + offset ..< fatData.startIndex + offset + sectorSize)
                try image.writeSector(startSector + i, data: slice)
            }
        }
    }

    // MARK: - Create blank formatted disk

    /// Format a blank disk image with a fresh FAT12 filesystem.
    static func format(image: any DiskImage, format: DiskFormat, volumeName: String = "ATARI") throws -> GEMDOSFilesystem {
        let geo = format.geometry
        let bpb = format.bpb
        let sectorSize = geo.bytesPerSector

        // 1. Write blank boot sector
        let bootSec = BootSector.makeBlank(format: format)
        try image.writeSector(0, data: bootSec.rawData)

        // 2. Write blank FATs (both copies)
        let fatSectors = Int(bpb.sectorsPerFAT)
        var fatBytes = [UInt8](repeating: 0x00, count: fatSectors * sectorSize)
        // FAT[0] = media descriptor, FAT[1] = 0xFF, FAT[2] = 0xFF  (cluster 1 = reserved)
        fatBytes[0] = bpb.mediaType
        fatBytes[1] = 0xFF
        fatBytes[2] = 0xFF

        let fat12 = FAT12(bytes: fatBytes, bootSector: bootSec)
        let fatData = fat12.rawData
        let fatStartSector = bootSec.fatStartSector

        for copy in 0 ..< 2 { // always 2 FAT copies
            let base = fatStartSector + copy * fatSectors
            for i in 0 ..< fatSectors {
                let offset = i * sectorSize
                let slice = fatData.subdata(in: fatData.startIndex + offset ..< fatData.startIndex + offset + sectorSize)
                try image.writeSector(base + i, data: slice)
            }
        }

        // 3. Write blank root directory
        let rootEntries = Int(bpb.rootEntryCount)
        let rootSectors = (rootEntries * 32 + sectorSize - 1) / sectorSize
        let rootStart   = bootSec.rootDirStartSector
        for s in rootStart ..< rootStart + rootSectors {
            try image.writeSector(s, data: Data(repeating: 0x00, count: sectorSize))
        }

        // 4. Write volume label in first root dir entry
        if !volumeName.isEmpty {
            var labelEntry = Data.filled(count: 32)
            let name = volumeName.uppercased().padding(toLength: 11, withPad: " ", startingAt: 0)
            let bytes = Array(name.utf8.prefix(11))
            for i in 0..<11 { labelEntry.writeUInt8(bytes[i], at: i) }
            labelEntry.writeUInt8(FileAttributes.volumeID.rawValue, at: 11)
            let (d, t) = DateConverter.fatTimestamp(from: Date())
            labelEntry.writeUInt16LE(t, at: 22)
            labelEntry.writeUInt16LE(d, at: 24)
            var rootSector0 = try image.readSector(rootStart)
            rootSector0.replaceSubrange(rootSector0.startIndex ..< rootSector0.startIndex + 32, with: labelEntry)
            try image.writeSector(rootStart, data: rootSector0)
        }

        // 5. Zero data area
        let firstData = rootStart + rootSectors
        for s in firstData ..< geo.totalSectors {
            try image.writeSector(s, data: Data(repeating: 0x00, count: sectorSize))
        }

        return try GEMDOSFilesystem(image: image)
    }

    /// Format a blank disk image with a custom floppy disk geometry.
    static func format(image: any DiskImage, geometry geo: DiskGeometry, volumeName: String = "ATARI") throws -> GEMDOSFilesystem {
        let sectorSize = geo.bytesPerSector

        // 1. Write blank boot sector
        let bootSec = BootSector.makeBlank(geometry: geo)
        try image.writeSector(0, data: bootSec.rawData)

        // 2. Write blank FATs (both copies)
        let fatSectors = Int(bootSec.sectorsPerFAT)
        var fatBytes = [UInt8](repeating: 0x00, count: fatSectors * sectorSize)
        fatBytes[0] = bootSec.mediaDescriptor
        fatBytes[1] = 0xFF
        fatBytes[2] = 0xFF

        let fat12 = FAT12(bytes: fatBytes, bootSector: bootSec)
        let fatData = fat12.rawData
        let fatStartSector = bootSec.fatStartSector

        for copy in 0 ..< 2 { // always 2 FAT copies
            let base = fatStartSector + copy * fatSectors
            for i in 0 ..< fatSectors {
                let offset = i * sectorSize
                let slice = fatData.subdata(in: fatData.startIndex + offset ..< fatData.startIndex + offset + sectorSize)
                try image.writeSector(base + i, data: slice)
            }
        }

        // 3. Write blank root directory
        let rootEntries = Int(bootSec.rootEntryCount)
        let rootSectors = (rootEntries * 32 + sectorSize - 1) / sectorSize
        let rootStart   = bootSec.rootDirStartSector
        for s in rootStart ..< rootStart + rootSectors {
            try image.writeSector(s, data: Data(repeating: 0x00, count: sectorSize))
        }

        // 4. Write volume label in first root dir entry
        if !volumeName.isEmpty {
            var labelEntry = Data.filled(count: 32)
            let name = volumeName.uppercased().padding(toLength: 11, withPad: " ", startingAt: 0)
            let bytes = Array(name.utf8.prefix(11))
            for i in 0..<11 { labelEntry.writeUInt8(bytes[i], at: i) }
            labelEntry.writeUInt8(FileAttributes.volumeID.rawValue, at: 11)
            let (d, t) = DateConverter.fatTimestamp(from: Date())
            labelEntry.writeUInt16LE(t, at: 22)
            labelEntry.writeUInt16LE(d, at: 24)
            var rootSector0 = try image.readSector(rootStart)
            rootSector0.replaceSubrange(rootSector0.startIndex ..< rootSector0.startIndex + 32, with: labelEntry)
            try image.writeSector(rootStart, data: rootSector0)
        }

        // 5. Zero data area
        let firstData = rootStart + rootSectors
        for s in firstData ..< geo.totalSectors {
            try image.writeSector(s, data: Data(repeating: 0x00, count: sectorSize))
        }

        return try GEMDOSFilesystem(image: image)
    }
}
