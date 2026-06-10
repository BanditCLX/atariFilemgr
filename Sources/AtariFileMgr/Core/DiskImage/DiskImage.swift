// DiskImage.swift — AtariFileMgr
// Protocol and base types for all supported disk image formats.
// Both .st (raw) and .msa (compressed) conform to DiskImage.

import Foundation

// MARK: - Errors

enum DiskImageError: LocalizedError {
    case fileNotFound(URL)
    case invalidFormat(String)
    case unknownGeometry(Int)
    case sectorOutOfRange(Int)
    case readOnly
    case ioError(Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):    return "File not found: \(url.lastPathComponent)"
        case .invalidFormat(let msg):   return "Invalid disk image format: \(msg)"
        case .unknownGeometry(let size): return "Cannot determine disk geometry for \(size) bytes"
        case .sectorOutOfRange(let s):  return "Sector \(s) is out of range"
        case .readOnly:                 return "Disk image is read-only"
        case .ioError(let err):         return "I/O error: \(err.localizedDescription)"
        }
    }
}

// MARK: - DiskImage protocol

/// A disk image that provides sector-level read/write access.
/// The image is held entirely in memory (Data) for editing; save to disk explicitly.
protocol DiskImage: AnyObject {

    /// Human-readable format name, e.g. "MSA" or "ST (raw)"
    var formatName: String { get }

    /// Disk geometry (tracks, sides, sectors per track).
    var geometry: DiskGeometry { get }

    /// Whether the image has unsaved changes.
    var isModified: Bool { get set }

    /// URL of the file this image was loaded from, if any.
    var sourceURL: URL? { get set }

    // MARK: Sector I/O

    /// Read one 512-byte sector by logical sector index.
    func readSector(_ logicalSector: Int) throws -> Data

    /// Write one 512-byte sector by logical sector index.
    func writeSector(_ logicalSector: Int, data: Data) throws

    // MARK: Persistence

    /// Load a disk image from a file URL (class method factory).
    static func load(from url: URL) throws -> Self

    /// Serialise the entire image to raw bytes (format-specific encoding).
    func serialise() throws -> Data

    /// Save (overwrite) the source file, or to a new URL.
    func save(to url: URL) throws
}

// MARK: - Default implementations

extension DiskImage {

    func save(to url: URL) throws {
        do {
            let data = try serialise()
            try data.write(to: url, options: .atomic)
            sourceURL = url
            isModified = false
        } catch {
            throw DiskImageError.ioError(error)
        }
    }

    /// Read all sectors as a flat raw Data buffer (used internally by the filesystem layer).
    func rawData() throws -> Data {
        var result = Data(capacity: geometry.totalBytes)
        for i in 0 ..< geometry.totalSectors {
            result.append(try readSector(i))
        }
        return result
    }

    /// Overwrite all sectors from a flat raw Data buffer.
    func writeAll(from data: Data) throws {
        let sectorSize = geometry.bytesPerSector
        for i in 0 ..< geometry.totalSectors {
            let start = i * sectorSize
            let sector = data.subdata(in: data.startIndex + start ..< data.startIndex + start + sectorSize)
            try writeSector(i, data: sector)
        }
    }
}

// MARK: - DiskImageFormat detection

enum DiskImageFormat {
    case st
    case msa
    case dim
    case ahd

    static func detect(url: URL) -> DiskImageFormat? {
        switch url.pathExtension.lowercased() {
        case "st":  return .st
        case "msa": return .msa
        case "dim": return .dim
        case "ahd": return .ahd
        default:    return nil
        }
    }
}
