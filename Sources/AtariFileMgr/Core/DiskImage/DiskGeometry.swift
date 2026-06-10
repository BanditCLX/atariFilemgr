// DiskGeometry.swift — AtariFileMgr
// Represents the physical and logical geometry of an Atari ST floppy disk.
// Handles sector address translation and format detection from file size.

import Foundation

// MARK: - Disk Format presets

enum DiskFormat: String, CaseIterable, Identifiable {
    case ss_dd_9 = "SS/DD 360 KB"    // Single-sided, 9 sectors/track — 80 tracks × 1 side × 9 sec
    case ds_dd_9 = "DS/DD 720 KB"    // Double-sided, 9 sectors/track — standard Atari ST
    case ds_dd_10 = "DS/DD 800 KB"   // Double-sided, 10 sectors/track
    case ds_dd_11 = "DS/HD 880 KB"   // Double-sided, 11 sectors/track (boosted density)
    case ds_hd_18 = "DS/HD 1.44 MB"  // Double-sided high-density

    var id: String { rawValue }

    var geometry: DiskGeometry {
        switch self {
        case .ss_dd_9:  return DiskGeometry(tracks: 80, sides: 1, sectorsPerTrack: 9)
        case .ds_dd_9:  return DiskGeometry(tracks: 80, sides: 2, sectorsPerTrack: 9)
        case .ds_dd_10: return DiskGeometry(tracks: 80, sides: 2, sectorsPerTrack: 10)
        case .ds_dd_11: return DiskGeometry(tracks: 80, sides: 2, sectorsPerTrack: 11)
        case .ds_hd_18: return DiskGeometry(tracks: 80, sides: 2, sectorsPerTrack: 18)
        }
    }

    /// Default BPB parameters for this format.
    var bpb: BPBDefaults {
        switch self {
        case .ss_dd_9:
            return BPBDefaults(mediaType: 0xF8, sectorsPerFAT: 3, rootEntryCount: 112,
                               sectorsPerCluster: 2)
        case .ds_dd_9:
            return BPBDefaults(mediaType: 0xF9, sectorsPerFAT: 5, rootEntryCount: 112,
                               sectorsPerCluster: 2)
        case .ds_dd_10:
            return BPBDefaults(mediaType: 0xF9, sectorsPerFAT: 5, rootEntryCount: 112,
                               sectorsPerCluster: 2)
        case .ds_dd_11:
            return BPBDefaults(mediaType: 0xF9, sectorsPerFAT: 5, rootEntryCount: 112,
                               sectorsPerCluster: 2)
        case .ds_hd_18:
            return BPBDefaults(mediaType: 0xF0, sectorsPerFAT: 9, rootEntryCount: 224,
                               sectorsPerCluster: 1)
        }
    }

    struct BPBDefaults {
        let mediaType: UInt8
        let sectorsPerFAT: UInt16
        let rootEntryCount: UInt16
        let sectorsPerCluster: UInt8
    }
}

// MARK: - DiskGeometry

struct DiskGeometry: Equatable {
    let tracks: Int           // total track count (typically 80)
    let sides: Int            // 1 = single-sided, 2 = double-sided
    let sectorsPerTrack: Int  // 9, 10, 11, or 18
    let bytesPerSector: Int   // always 512 for Atari ST

    init(tracks: Int, sides: Int, sectorsPerTrack: Int, bytesPerSector: Int = 512) {
        self.tracks = tracks
        self.sides = sides
        self.sectorsPerTrack = sectorsPerTrack
        self.bytesPerSector = bytesPerSector
    }

    /// Total logical sector count on this disk.
    var totalSectors: Int { tracks * sides * sectorsPerTrack }

    /// Total byte capacity.
    var totalBytes: Int { totalSectors * bytesPerSector }

    // MARK: - Sector addressing

    /// Convert a logical sector index (0-based) to physical (track, side, sector).
    /// Atari ST interleaving: sectors are sequential per-track across sides.
    /// Logical order: track0/side0 … track0/side1 … track1/side0 … etc.
    func physical(logicalSector: Int) -> (track: Int, side: Int, sector: Int) {
        let sectorsPerCylinder = sides * sectorsPerTrack
        let track  = logicalSector / sectorsPerCylinder
        let remain = logicalSector % sectorsPerCylinder
        let side   = remain / sectorsPerTrack
        let sector = (remain % sectorsPerTrack) + 1  // 1-based physical sector
        return (track, side, sector)
    }

    /// Convert physical (track, side, sector) to a logical sector index.
    func logical(track: Int, side: Int, sector: Int) -> Int {
        track * sides * sectorsPerTrack + side * sectorsPerTrack + (sector - 1)
    }

    /// Byte offset of a logical sector in a flat raw image.
    func byteOffset(of logicalSector: Int) -> Int {
        logicalSector * bytesPerSector
    }

    // MARK: - Detection from file size

    /// Detect geometry from a raw `.st` file size and optional file data.
    static func detect(fileSize: Int, fileData: Data? = nil) -> DiskGeometry? {
        // 1. Try to read BPB from boot sector if data is available
        if let data = fileData, data.count >= 30 {
            let bps = Int(data.readUInt16LE(at: 11))
            let spt = Int(data.readUInt16LE(at: 24))
            let heads = Int(data.readUInt16LE(at: 26))
            let totalSec = Int(data.readUInt16LE(at: 19))
            
            // Validate BPB values before accepting them (support truncated files)
            if [128, 256, 512, 1024].contains(bps),
               spt > 0 && spt <= 27,
               heads == 1 || heads == 2,
               totalSec > 0,
               fileSize <= bps * totalSec && fileSize >= 512 {
                let tracks = totalSec / (heads * spt)
                if tracks >= 70 && tracks <= 90 {
                    return DiskGeometry(tracks: tracks, sides: heads, sectorsPerTrack: spt, bytesPerSector: bps)
                }
            }
        }

        // 2. Try exact match from presets
        for format in DiskFormat.allCases {
            if format.geometry.totalBytes == fileSize { return format.geometry }
        }

        // 3. Try to infer by calculation (Delphi-inspired scan)
        if fileSize % 512 == 0 {
            let totalSectors = fileSize / 512
            let sides = totalSectors >= 1100 ? 2 : 1
            
            // First search pass: exact geometry match
            for endTrack in 70...90 {
                for spt in 8...27 {
                    if endTrack * sides * spt == totalSectors {
                        return DiskGeometry(tracks: endTrack, sides: sides, sectorsPerTrack: spt)
                    }
                }
            }
            
            // Second search pass: closest geometry match
            var closestSpt = 9
            var closestTracks = 80
            var closestDiff = Int.max
            for endTrack in 70...90 {
                for spt in 8...27 {
                    let calculated = endTrack * sides * spt
                    let diff = totalSectors - calculated
                    if diff >= 0 && diff < closestDiff {
                        closestDiff = diff
                        closestSpt = spt
                        closestTracks = endTrack
                    }
                }
            }
            return DiskGeometry(tracks: closestTracks, sides: sides, sectorsPerTrack: closestSpt)
        }
        return nil
    }

    // MARK: - Convenience

    var description: String {
        let kb = totalBytes / 1024
        return sides == 2 ? "DS \(sectorsPerTrack)s/tr – \(kb) KB" : "SS \(sectorsPerTrack)s/tr – \(kb) KB"
    }
}
