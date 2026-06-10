// FAT12.swift — AtariFileMgr
// FAT12 (File Allocation Table, 12-bit entries) reader/writer.
//
// FAT12 stores one 12-bit value per cluster.
// Clusters 0 and 1 are reserved; data starts at cluster 2.
//
// Packing: entries are packed in groups of two into three bytes:
//   Let n be an even cluster index:
//     fat[n/2*3+0]          = lo byte of entry[n]
//     fat[n/2*3+1] & 0x0F   = hi nibble of entry[n]
//     fat[n/2*3+1] >> 4     = lo nibble of entry[n+1]
//     fat[n/2*3+2]          = hi byte of entry[n+1]
//
// Special values:
//   0x000 = free cluster
//   0xFF7 = bad cluster
//   0xFF8…0xFFF = end-of-chain marker

import Foundation

final class FAT12 {

    // MARK: - Constants

    static let freeCluster:    UInt16 = 0x000
    static let badCluster:     UInt16 = 0xFF7
    static let endOfChain:     UInt16 = 0xFF8   // any value >= this is EOC
    static let minEOC:         UInt16 = 0xFF8
    static let eocMarker:      UInt16 = 0xFFF   // what we write as EOC

    // MARK: - State

    /// Raw FAT bytes (may span multiple sectors; this is the first FAT copy).
    private var bytes: [UInt8]

    /// Boot sector info needed for cluster ↔ sector mapping.
    let bootSector: BootSector

    // MARK: - Init

    init(bytes: [UInt8], bootSector: BootSector) {
        self.bytes = bytes
        self.bootSector = bootSector
    }

    // MARK: - Entry access

    /// Read the 12-bit FAT entry for cluster `n`.
    func entry(for cluster: UInt16) -> UInt16 {
        let n = Int(cluster)
        let byteIndex = (n * 3) / 2
        guard byteIndex + 1 < bytes.count else { return Self.eocMarker }

        if n % 2 == 0 {
            // Even: lower 8 bits at byteIndex, upper 4 bits at low nibble of byteIndex+1
            let lo = UInt16(bytes[byteIndex])
            let hi = UInt16(bytes[byteIndex + 1] & 0x0F)
            return (hi << 8) | lo
        } else {
            // Odd: lower 4 bits at high nibble of byteIndex, upper 8 bits at byteIndex+1
            let lo = UInt16(bytes[byteIndex] >> 4)
            let hi = UInt16(bytes[byteIndex + 1])
            return (hi << 4) | lo
        }
    }

    /// Write a 12-bit FAT entry for cluster `n`.
    func setEntry(_ value: UInt16, for cluster: UInt16) {
        let n = Int(cluster)
        let byteIndex = (n * 3) / 2
        guard byteIndex + 1 < bytes.count else { return }

        if n % 2 == 0 {
            bytes[byteIndex]     = UInt8(value & 0xFF)
            bytes[byteIndex + 1] = (bytes[byteIndex + 1] & 0xF0) | UInt8((value >> 8) & 0x0F)
        } else {
            bytes[byteIndex]     = (bytes[byteIndex] & 0x0F) | UInt8((value & 0x0F) << 4)
            bytes[byteIndex + 1] = UInt8(value >> 4)
        }
    }

    // MARK: - Chain traversal

    /// Returns true if `entry` is an end-of-chain marker.
    static func isEndOfChain(_ entry: UInt16) -> Bool {
        entry >= minEOC
    }

    /// Follow the cluster chain starting from `startCluster`.
    /// Returns all cluster numbers in order (including startCluster).
    func clusterChain(startingAt startCluster: UInt16) -> [UInt16] {
        guard startCluster >= 2 else { return [] }
        var chain: [UInt16] = []
        var current = startCluster
        var visited = Set<UInt16>()

        while !Self.isEndOfChain(current) && current != Self.freeCluster {
            guard !visited.contains(current) else { break }  // cycle guard
            visited.insert(current)
            chain.append(current)
            current = entry(for: current)
        }
        return chain
    }

    // MARK: - Free cluster search

    /// Find the first free cluster (>= 2).
    func firstFreeCluster() -> UInt16? {
        let total = bootSector.clusterCount + 2  // cluster indices start at 2
        for i in 2 ..< total {
            if entry(for: UInt16(i)) == Self.freeCluster { return UInt16(i) }
        }
        return nil
    }

    /// Count total free clusters.
    func freeClusterCount() -> Int {
        let total = bootSector.clusterCount + 2
        var count = 0
        for i in 2 ..< total {
            if entry(for: UInt16(i)) == Self.freeCluster { count += 1 }
        }
        return count
    }

    /// Free bytes remaining on the disk.
    var freeBytesAvailable: Int {
        freeClusterCount() * Int(bootSector.sectorsPerCluster) * Int(bootSector.bytesPerSector)
    }

    // MARK: - Allocation

    /// Allocate `clusterCount` contiguous or scattered clusters and chain them.
    /// Returns the starting cluster of the new chain, or throws if disk is full.
    func allocate(clusterCount: Int) throws -> UInt16 {
        var chain: [UInt16] = []
        let total = bootSector.clusterCount + 2

        for i in 2 ..< total {
            let idx = UInt16(i)
            if entry(for: idx) == Self.freeCluster {
                chain.append(idx)
                if chain.count == clusterCount { break }
            }
        }

        guard chain.count == clusterCount else {
            throw GEMDOSError.diskFull
        }

        // Link the chain
        for i in 0 ..< chain.count - 1 {
            setEntry(chain[i + 1], for: chain[i])
        }
        setEntry(Self.eocMarker, for: chain.last!)
        return chain[0]
    }

    /// Free all clusters in the chain starting at `startCluster`.
    func freeChain(startingAt startCluster: UInt16) {
        let chain = clusterChain(startingAt: startCluster)
        for cluster in chain {
            setEntry(Self.freeCluster, for: cluster)
        }
    }

    // MARK: - Cluster ↔ Sector mapping

    /// First logical sector of a given cluster (cluster 2 = first data cluster).
    func firstSector(of cluster: UInt16) -> Int {
        bootSector.firstDataSector + (Int(cluster) - 2) * Int(bootSector.sectorsPerCluster)
    }

    // MARK: - Serialisation

    /// Return the raw FAT bytes (to be written back to the disk image).
    var rawBytes: [UInt8] { bytes }

    /// Return the raw FAT as Data (sector-aligned).
    var rawData: Data {
        let sectorSize = Int(bootSector.bytesPerSector)
        let fatBytes   = Int(bootSector.sectorsPerFAT) * sectorSize
        var result = Data(bytes)
        if result.count < fatBytes {
            result.append(Data(repeating: 0, count: fatBytes - result.count))
        }
        return result.prefix(fatBytes)
    }
}
