// DataExtensions.swift — AtariFileMgr
// Low-level byte-order helpers for Data buffers.
// All Atari ST FAT structures use little-endian byte order.
// MSA file header fields use big-endian byte order.

import Foundation

// MARK: - Read helpers

extension Data {

    /// Read a single byte (UInt8) at the given offset.
    func readUInt8(at offset: Int) -> UInt8 {
        precondition(offset < count, "DataExtensions: readUInt8 offset \(offset) out of bounds (\(count))")
        return self[startIndex + offset]
    }

    /// Read a 16-bit little-endian unsigned integer.
    func readUInt16LE(at offset: Int) -> UInt16 {
        precondition(offset + 1 < count, "DataExtensions: readUInt16LE out of bounds")
        let lo = UInt16(self[startIndex + offset])
        let hi = UInt16(self[startIndex + offset + 1])
        return (hi << 8) | lo
    }

    /// Read a 16-bit big-endian unsigned integer (used for MSA header).
    func readUInt16BE(at offset: Int) -> UInt16 {
        precondition(offset + 1 < count, "DataExtensions: readUInt16BE out of bounds")
        let hi = UInt16(self[startIndex + offset])
        let lo = UInt16(self[startIndex + offset + 1])
        return (hi << 8) | lo
    }

    /// Read a 32-bit little-endian unsigned integer.
    func readUInt32LE(at offset: Int) -> UInt32 {
        precondition(offset + 3 < count, "DataExtensions: readUInt32LE out of bounds")
        let b0 = UInt32(self[startIndex + offset])
        let b1 = UInt32(self[startIndex + offset + 1])
        let b2 = UInt32(self[startIndex + offset + 2])
        let b3 = UInt32(self[startIndex + offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    /// Read a 32-bit big-endian unsigned integer.
    func readUInt32BE(at offset: Int) -> UInt32 {
        precondition(offset + 3 < count, "DataExtensions: readUInt32BE out of bounds")
        let b0 = UInt32(self[startIndex + offset])
        let b1 = UInt32(self[startIndex + offset + 1])
        let b2 = UInt32(self[startIndex + offset + 2])
        let b3 = UInt32(self[startIndex + offset + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    /// Read a fixed-length byte array as a String, trimming trailing spaces and null bytes.
    func readASCIIString(at offset: Int, length: Int) -> String {
        let bytes = Array(self[startIndex + offset ..< startIndex + offset + length])
        let s = String(bytes: bytes, encoding: .isoLatin1) ?? ""
        return s.trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
    }

    /// Read a fixed-length byte array.
    func readBytes(at offset: Int, count: Int) -> [UInt8] {
        Array(self[startIndex + offset ..< startIndex + offset + count])
    }
}

// MARK: - Write helpers

extension Data {

    /// Write a single byte at the given offset.
    mutating func writeUInt8(_ value: UInt8, at offset: Int) {
        self[startIndex + offset] = value
    }

    /// Write a 16-bit little-endian unsigned integer.
    mutating func writeUInt16LE(_ value: UInt16, at offset: Int) {
        self[startIndex + offset]     = UInt8(value & 0xFF)
        self[startIndex + offset + 1] = UInt8(value >> 8)
    }

    /// Write a 16-bit big-endian unsigned integer (used for MSA header).
    mutating func writeUInt16BE(_ value: UInt16, at offset: Int) {
        self[startIndex + offset]     = UInt8(value >> 8)
        self[startIndex + offset + 1] = UInt8(value & 0xFF)
    }

    /// Write a 32-bit little-endian unsigned integer.
    mutating func writeUInt32LE(_ value: UInt32, at offset: Int) {
        self[startIndex + offset]     = UInt8(value & 0xFF)
        self[startIndex + offset + 1] = UInt8((value >> 8)  & 0xFF)
        self[startIndex + offset + 2] = UInt8((value >> 16) & 0xFF)
        self[startIndex + offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    /// Write an ASCII string into a fixed-length field, padded with spaces.
    mutating func writeASCIIString(_ s: String, at offset: Int, length: Int) {
        let bytes = Array(s.utf8.prefix(length))
        for i in 0 ..< length {
            self[startIndex + offset + i] = i < bytes.count ? bytes[i] : 0x20 // space pad
        }
    }
}

// MARK: - Convenience factory

extension Data {
    /// Create a Data buffer of `count` bytes, all set to `fill`.
    static func filled(count: Int, with fill: UInt8 = 0x00) -> Data {
        Data(repeating: fill, count: count)
    }
}
