// AtariCompressionDetector.swift — AtariFileMgr
// Identifies retro Atari ST packer formats and parses archive files.

import Foundation

public struct CompressionFormat {
    public let name: String
    public let isCrunchedFile: Bool // Single file crunched (like ICE!, ATM5, RNC)
    public let isArchive: Bool      // Multi-file archive (like LZH, ARC, ZIP)
    public var filesInside: [String] = []
}

public final class AtariCompressionDetector {

    public static func detect(data: Data) -> CompressionFormat? {
        guard data.count >= 4 else { return nil }
        
        let sig32 = (UInt32(data[0]) << 24) | (UInt32(data[1]) << 16) | (UInt32(data[2]) << 8) | UInt32(data[3])
        
        // 0. GEMDOS Executable checks for decruncher stubs / packed executables
        if data.count >= 16 && (data[0] == 0x60 && data[1] == 0x1A) {
            let searchLimit = min(data.count, 512)
            let searchData = data.prefix(searchLimit)
            
            // Check for Pack-Ice decruncher string "Pack-Ice"
            if let headerString = String(data: searchData.prefix(min(128, searchData.count)), encoding: .ascii) {
                if headerString.contains("Pack-Ice") {
                    return CompressionFormat(name: "Pack-Ice Packed Executable", isCrunchedFile: true, isArchive: false)
                }
                if headerString.contains("ATOM") {
                    return CompressionFormat(name: "Atomik Cruncher v3.x Executable", isCrunchedFile: true, isArchive: false)
                }
                if headerString.contains("ATM5") {
                    return CompressionFormat(name: "Atomik Cruncher v3.5+ Executable", isCrunchedFile: true, isArchive: false)
                }
                if headerString.contains("ATM3") {
                    return CompressionFormat(name: "Atomik Cruncher v3.x Executable", isCrunchedFile: true, isArchive: false)
                }
                if headerString.contains("ATM8") {
                    return CompressionFormat(name: "Atomik Cruncher Executable (ATM8)", isCrunchedFile: true, isArchive: false)
                }
                if headerString.contains("ATM9") {
                    return CompressionFormat(name: "Atomik Cruncher Executable (ATM9)", isCrunchedFile: true, isArchive: false)
                }
            }
            
            // RNC
            let rnc1 = Data([0x52, 0x4e, 0x43, 0x01]) // "RNC\x01"
            let rnc2 = Data([0x52, 0x4e, 0x43, 0x02]) // "RNC\x02"
            if searchData.range(of: rnc1) != nil {
                return CompressionFormat(name: "Rob Northen Executable (Method 1)", isCrunchedFile: true, isArchive: false)
            }
            if searchData.range(of: rnc2) != nil {
                return CompressionFormat(name: "Rob Northen Executable (Method 2)", isCrunchedFile: true, isArchive: false)
            }
            
            // StoneCracker
            let s300 = Data([0x53, 0x33, 0x30, 0x30]) // "S300"
            let s400 = Data([0x53, 0x34, 0x30, 0x30]) // "S400"
            let s404 = Data([0x53, 0x34, 0x30, 0x34]) // "S404"
            let ays = Data([0x41, 0x59, 0x53, 0x21])  // "AYS!"
            let zulu = Data([0x5a, 0x55, 0x4c, 0x55]) // "ZULU"
            
            if searchData.range(of: s300) != nil {
                return CompressionFormat(name: "StoneCracker Executable (S300)", isCrunchedFile: true, isArchive: false)
            }
            if searchData.range(of: s400) != nil || searchData.range(of: s404) != nil {
                return CompressionFormat(name: "StoneCracker Executable (S400+)", isCrunchedFile: true, isArchive: false)
            }
            if searchData.range(of: ays) != nil {
                return CompressionFormat(name: "StoneCracker Executable (AYS!)", isCrunchedFile: true, isArchive: false)
            }
            if searchData.range(of: zulu) != nil {
                return CompressionFormat(name: "StoneCracker Executable (ZULU)", isCrunchedFile: true, isArchive: false)
            }
        }
        
        // 1. Pack-Ice (ICE!)
        if (sig32 & 0xFFFFFF00) == 0x49636500 || sig32 == 0x49434521 {
            return CompressionFormat(name: "Pack-Ice (ICE!)", isCrunchedFile: true, isArchive: false)
        }
        
        // 2. Atomik Cruncher (ATOM/ATM5/ATM3/ATM8/ATM9)
        if sig32 == 0x41544f4d { // "ATOM"
            return CompressionFormat(name: "Atomik Cruncher v3.x (ATOM)", isCrunchedFile: true, isArchive: false)
        }
        if sig32 == 0x41544d35 { // "ATM5"
            return CompressionFormat(name: "Atomik Cruncher v3.5+ (ATM5)", isCrunchedFile: true, isArchive: false)
        }
        if sig32 == 0x41544d33 { // "ATM3"
            return CompressionFormat(name: "Atomik Cruncher v3.x (ATM3)", isCrunchedFile: true, isArchive: false)
        }
        if sig32 == 0x41544d38 { // "ATM8"
            return CompressionFormat(name: "Atomik Cruncher (ATM8)", isCrunchedFile: true, isArchive: false)
        }
        if sig32 == 0x41544d39 { // "ATM9"
            return CompressionFormat(name: "Atomik Cruncher (ATM9)", isCrunchedFile: true, isArchive: false)
        }
        
        // 3. Rob Northen Compression (RNC1 / RNC2)
        if sig32 == 0x524e4301 { // "RNC\x01"
            return CompressionFormat(name: "Rob Northen (Method 1)", isCrunchedFile: true, isArchive: false)
        }
        if sig32 == 0x524e4302 { // "RNC\x02"
            return CompressionFormat(name: "Rob Northen (Method 2)", isCrunchedFile: true, isArchive: false)
        }
        
        // 4. StoneCracker (S300, S400, AYS!, Z&G!, ZULU)
        if sig32 == 0x53333030 { // "S300"
            return CompressionFormat(name: "StoneCracker v3.00", isCrunchedFile: true, isArchive: false)
        }
        if sig32 == 0x53343030 || sig32 == 0x53343034 { // "S400", "S404"
            return CompressionFormat(name: "StoneCracker v4.00+", isCrunchedFile: true, isArchive: false)
        }
        if sig32 == 0x41595321 { // "AYS!"
            return CompressionFormat(name: "StoneCracker (AYS!)", isCrunchedFile: true, isArchive: false)
        }
        if sig32 == 0x5a554c55 { // "ZULU"
            return CompressionFormat(name: "StoneCracker (ZULU)", isCrunchedFile: true, isArchive: false)
        }
        
        // 5. Fire Packer
        if sig32 == 0x46495245 { // "FIRE"
            return CompressionFormat(name: "Fire Packer", isCrunchedFile: true, isArchive: false)
        }
        
        // 6. Master Packer
        if sig32 == 0x4d504321 { // "MPC!"
            return CompressionFormat(name: "Master Packer (MPC!)", isCrunchedFile: true, isArchive: false)
        }
        
        // 7. Medway Boys LZ77 / Packer (known signatures/identifiers)
        if sig32 == 0x4d445759 { // "MDWY"
            return CompressionFormat(name: "Medway Boys Packer (MDWY)", isCrunchedFile: true, isArchive: false)
        }
        
        // 8. Standard Archive Formats (LZH, ARC, ZIP, ZOO)
        // LZH/LHA signature starts at offset 2 (e.g. "-lh0-", "-lh5-", etc.)
        if data.count >= 7 {
            let offset2Sig = String(data: data[2..<7], encoding: .ascii) ?? ""
            if offset2Sig.hasPrefix("-lh") || offset2Sig.hasPrefix("-lz") {
                let files = parseLzhFilenames(data: data)
                return CompressionFormat(name: "LZH/LHA Archive", isCrunchedFile: false, isArchive: true, filesInside: files)
            }
        }
        
        // ZIP Archive
        if sig32 == 0x504b0304 { // "PK\x03\x04"
            let files = parseZipFilenames(data: data)
            return CompressionFormat(name: "ZIP Archive", isCrunchedFile: false, isArchive: true, filesInside: files)
        }
        
        // ARC Archive (Starts with 0x1A followed by method byte 1..9)
        if data[0] == 0x1A && data[1] >= 1 && data[1] <= 9 {
            let files = parseArcFilenames(data: data)
            return CompressionFormat(name: "ARC Archive", isCrunchedFile: false, isArchive: true, filesInside: files)
        }
        
        // ZOO Archive
        if sig32 == 0x5a4f4f20 { // "ZOO "
            return CompressionFormat(name: "ZOO Archive", isCrunchedFile: false, isArchive: true)
        }
        
        return nil
    }

    // MARK: - Archive Parsers

    private static func parseZipFilenames(data: Data) -> [String] {
        var filenames: [String] = []
        var offset = 0
        while offset + 30 <= data.count {
            let sig = (UInt32(data[offset]) << 24) | (UInt32(data[offset+1]) << 16) | (UInt32(data[offset+2]) << 8) | UInt32(data[offset+3])
            if sig == 0x504b0304 { // Local file header
                let compSize = Int((UInt32(data[offset+21]) << 24) | (UInt32(data[offset+20]) << 16) | (UInt32(data[offset+19]) << 8) | UInt32(data[offset+18]))
                let nameLen = Int((UInt16(data[offset+27]) << 8) | UInt16(data[offset+26]))
                let extraLen = Int((UInt16(data[offset+29]) << 8) | UInt16(data[offset+28]))
                
                if offset + 30 + nameLen <= data.count {
                    let nameData = data[(offset+30)..<(offset+30+nameLen)]
                    if let name = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .ascii) {
                        if !name.hasSuffix("/") {
                            filenames.append(name)
                        }
                    }
                }
                offset += 30 + nameLen + extraLen + compSize
            } else {
                break
            }
        }
        return filenames
    }

    private static func parseLzhFilenames(data: Data) -> [String] {
        var filenames: [String] = []
        var offset = 0
        while offset + 22 <= data.count {
            let headerSize = Int(data[offset])
            if headerSize == 0 { break } // End of archive
            
            let methodData = data[(offset+2)..<min(offset+7, data.count)]
            let method = String(data: methodData, encoding: .ascii) ?? ""
            if !method.hasPrefix("-lh") && !method.hasPrefix("-lz") {
                break // Invalid LZH method
            }
            
            let compSize = Int((UInt32(data[offset+10]) << 24) | (UInt32(data[offset+9]) << 16) | (UInt32(data[offset+8]) << 8) | UInt32(data[offset+7]))
            let nameLen = Int(data[offset+21])
            
            if offset + 22 + nameLen <= data.count {
                let nameData = data[(offset+22)..<(offset+22+nameLen)]
                if let name = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .ascii) {
                    filenames.append(name)
                }
            }
            offset += headerSize + 2 + compSize
        }
        return filenames
    }

    private static func parseArcFilenames(data: Data) -> [String] {
        var filenames: [String] = []
        var offset = 0
        while offset + 29 <= data.count {
            guard data[offset] == 0x1A else { break }
            let method = data[offset+1]
            if method == 0 { break } // End of archive
            
            let nameData = data[(offset+2)..<(offset+15)]
            var nameBytes: [UInt8] = []
            for b in nameData {
                if b == 0 { break }
                nameBytes.append(b)
            }
            if let name = String(bytes: nameBytes, encoding: .ascii) {
                filenames.append(name)
            }
            
            let compSize = Int((UInt32(data[offset+18]) << 24) | (UInt32(data[offset+17]) << 16) | (UInt32(data[offset+16]) << 8) | UInt32(data[offset+15]))
            offset += 29 + compSize
        }
        return filenames
    }
}
