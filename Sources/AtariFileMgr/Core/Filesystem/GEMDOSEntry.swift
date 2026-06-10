// GEMDOSEntry.swift — AtariFileMgr
// Model for a single file or directory entry in an Atari ST GEMDOS filesystem.
// Each entry corresponds to one 32-byte directory record.

import Foundation

// MARK: - Attribute flags

struct FileAttributes: OptionSet, Hashable {
    let rawValue: UInt8

    static let readOnly  = FileAttributes(rawValue: 0x01)
    static let hidden    = FileAttributes(rawValue: 0x02)
    static let system    = FileAttributes(rawValue: 0x04)
    static let volumeID  = FileAttributes(rawValue: 0x08)
    static let directory = FileAttributes(rawValue: 0x10)
    static let archive   = FileAttributes(rawValue: 0x20)

    var isDirectory: Bool { contains(.directory) }
    var isFile: Bool      { !contains(.directory) && !contains(.volumeID) }
    var isVolumeLabel: Bool { contains(.volumeID) }
}

// MARK: - GEMDOSEntry

/// Represents one file or folder entry visible in the disk image.
struct GEMDOSEntry: Identifiable, Hashable {

    // MARK: - Stored properties

    let id: UUID        // stable SwiftUI identifier (not persisted)

    var name83: Filename83.Parsed   // 8.3 parsed name
    var attributes: FileAttributes
    var fatDate: UInt16             // packed Atari FAT date
    var fatTime: UInt16             // packed Atari FAT time
    var startCluster: UInt16        // first cluster of file data (0 = empty)
    var fileSize: UInt32            // size in bytes (0 for directories)

    /// Sector-level location of this entry (for in-place editing)
    var directorySector: Int        // which sector this 32-byte entry lives in
    var directoryOffset: Int        // byte offset within that sector (0, 32, 64, …)

    // MARK: - Convenience

    var displayName: String  { name83.displayName }
    var isDirectory: Bool    { attributes.isDirectory }
    var isFile: Bool         { attributes.isFile }

    var modifiedDate: Date {
        DateConverter.date(fatDate: fatDate, fatTime: fatTime)
    }

    var sizeString: String {
        if isDirectory { return "<DIR>" }
        let sz = Int(fileSize)
        if sz < 1024       { return "\(sz) B" }
        if sz < 1024*1024  { return String(format: "%.1f KB", Double(sz)/1024) }
        return String(format: "%.1f MB", Double(sz)/(1024*1024))
    }

    var dateString: String {
        DateConverter.displayString(fatDate: fatDate, fatTime: fatTime)
    }

    // MARK: - Hashable / Equatable

    static func == (lhs: GEMDOSEntry, rhs: GEMDOSEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - GEMDOSError

enum GEMDOSError: LocalizedError {
    case diskFull
    case directoryFull
    case fileNotFound(String)
    case fileAlreadyExists(String)
    case invalidName(String)
    case notADirectory(String)
    case notAFile(String)
    case corruptFilesystem(String)
    case nameTooLong(String)

    var errorDescription: String? {
        switch self {
        case .diskFull:                    return "Disk is full"
        case .directoryFull:               return "Directory is full (max entries reached)"
        case .fileNotFound(let n):         return "File not found: \(n)"
        case .fileAlreadyExists(let n):    return "File already exists: \(n)"
        case .invalidName(let n):          return "Invalid filename: \(n)"
        case .notADirectory(let n):        return "\(n) is not a directory"
        case .notAFile(let n):             return "\(n) is not a file"
        case .corruptFilesystem(let msg):  return "Corrupt filesystem: \(msg)"
        case .nameTooLong(let n):          return "Name too long (max 8.3): \(n)"
        }
    }
}
