// Filename83.swift — AtariFileMgr
// Handles encoding and decoding of Atari ST GEMDOS 8.3 filenames.
//
// GEMDOS rules:
//  - Filenames are uppercase (GEMDOS is not case-sensitive)
//  - Name: 8 bytes, padded with spaces (0x20)
//  - Extension: 3 bytes, padded with spaces (0x20)
//  - First byte 0xE5 = deleted entry; 0x00 = end of directory
//  - Forbidden characters: " * + , . / : ; < = > ? [ \ ] | 0x00-0x1F
//  - Dots in the display name are not stored; they separate name from ext

import Foundation

struct Filename83 {

    // MARK: - Types

    struct Parsed: Equatable {
        let name: String   // 1-8 chars, uppercase, no trailing spaces
        let ext:  String   // 0-3 chars, uppercase, no trailing spaces

        /// Full display name like "AUTOEXEC.BAT" or "FOLDER"
        var displayName: String {
            ext.isEmpty ? name : "\(name).\(ext)"
        }
    }

    // MARK: - Forbidden chars set (printable only; control chars blocked by UInt8 range check)

    private static let forbidden: Set<Character> = [
        " ", "\"", "*", "+", ",", ".", "/", ":",
        ";", "<", "=", ">", "?", "[", "\\", "]", "|"
    ]

    // MARK: - Decode (disk → Swift)

    /// Decode an 8-byte name + 3-byte extension from a raw directory entry.
    static func decode(nameBytes: [UInt8], extBytes: [UInt8]) -> Parsed {
        // Replace 0x05 (Kanji/special first byte) with 0xE5 for display
        var nb = nameBytes
        if nb.first == 0x05 { nb[0] = 0xE5 }

        let nameStr = String(bytes: nb, encoding: .isoLatin1)?.trimmingCharacters(in: .init(charactersIn: " ")) ?? ""
        let extStr  = String(bytes: extBytes, encoding: .isoLatin1)?.trimmingCharacters(in: .init(charactersIn: " ")) ?? ""
        return Parsed(name: nameStr, ext: extStr)
    }

    /// Decode from a full 11-byte raw field (first 8 = name, last 3 = ext).
    static func decode(raw11: [UInt8]) -> Parsed {
        precondition(raw11.count >= 11)
        return decode(nameBytes: Array(raw11[0..<8]), extBytes: Array(raw11[8..<11]))
    }

    // MARK: - Encode (Swift → disk)

    /// Encode a display name (e.g. "MYFILE.TXT") into raw 8+3 bytes.
    /// Returns nil if the name is invalid.
    static func encode(_ displayName: String) -> (name: [UInt8], ext: [UInt8])? {
        let upper = displayName.uppercased()
        let parts = upper.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let nameStr = String(parts[0])
        let extStr  = parts.count > 1 ? String(parts[1]) : ""

        guard !nameStr.isEmpty, nameStr.count <= 8, extStr.count <= 3 else { return nil }
        guard isValid(nameStr) && isValid(extStr) else { return nil }

        var nameBytes = [UInt8](repeating: 0x20, count: 8)
        var extBytes  = [UInt8](repeating: 0x20, count: 3)

        for (i, c) in nameStr.utf8.prefix(8).enumerated() { nameBytes[i] = c }
        for (i, c) in extStr.utf8.prefix(3).enumerated()  { extBytes[i]  = c }

        return (nameBytes, extBytes)
    }

    // MARK: - Validation

    /// Check whether a name component (without dot) is valid for GEMDOS 8.3.
    static func isValid(_ component: String) -> Bool {
        guard !component.isEmpty else { return true }   // empty ext is ok
        for c in component {
            if forbidden.contains(c) { return false }
            // Reject control characters
            for scalar in c.unicodeScalars where scalar.value < 0x20 { return false }
        }
        return true
    }

    /// Validate and sanitise a macOS filename for import into the image.
    /// Returns a cleaned-up 8.3 name that GEMDOS can use.
    static func sanitise(_ input: String) -> String {
        let upper = input.uppercased()
        // Split on last dot
        let dotIdx = upper.lastIndex(of: ".") ?? upper.endIndex
        var nameStr = String(upper[upper.startIndex ..< dotIdx])
        var extStr  = dotIdx < upper.endIndex ? String(upper[upper.index(after: dotIdx)...]) : ""

        // Remove forbidden characters and control characters
        let isPrintable: (Character) -> Bool = { c in
            !forbidden.contains(c) && (c.unicodeScalars.first?.value ?? 0) >= 0x20
        }
        nameStr = nameStr.filter(isPrintable)
        extStr  = extStr.filter(isPrintable)

        // Truncate
        nameStr = String(nameStr.prefix(8))
        extStr  = String(extStr.prefix(3))

        // Must have at least one name char
        if nameStr.isEmpty { nameStr = "FILE" }

        return extStr.isEmpty ? nameStr : "\(nameStr).\(extStr)"
    }

    // MARK: - Name conflict resolution

    /// Generate a unique name when `baseName` already exists in `existingNames`.
    /// Appends ~1, ~2, etc. to the name (Windows style).
    static func uniqueName(base: String, existing: Set<String>) -> String {
        if !existing.contains(base) { return base }
        let parts = base.split(separator: ".", maxSplits: 1)
        let stem  = String(parts[0])
        let ext   = parts.count > 1 ? ".\(parts[1])" : ""
        for n in 1...999 {
            let suffix = "~\(n)"
            let truncated = String(stem.prefix(8 - suffix.count)) + suffix
            let candidate = "\(truncated)\(ext)"
            if !existing.contains(candidate) { return candidate }
        }
        return base // fallback (should never happen)
    }
}

// Note: Character.asciiValue is available in Swift 5.1+ (Foundation)
