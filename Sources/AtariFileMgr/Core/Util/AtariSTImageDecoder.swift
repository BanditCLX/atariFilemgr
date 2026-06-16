// AtariSTImageDecoder.swift — AtariFileMgr
// Utility to decode classic Atari ST graphics formats into modern CGImage objects.

import Foundation
import CoreGraphics

public struct DecodedAtariSTImage {
    public let cgImage: CGImage
    public let formatName: String
    public let resolutionText: String
    public let palette: [UInt32] // 32-bit ARGB values
}

public final class AtariSTImageDecoder {

    // MARK: - STE/ST Color Decoding Helper

    /// Decodes a 16-bit Atari ST/STE color word into a 32-bit ARGB UInt32 pixel value.
    public static func decodeAtariColor(_ word: UInt16) -> UInt32 {
        // Red channel
        let rMsbs = UInt32((word >> 8) & 0x07)
        let rLsb = UInt32((word >> 11) & 0x01)
        let rVal = (rMsbs << 1) | rLsb
        let r = rVal * 17 // scale 0-15 to 0-255

        // Green channel
        let gMsbs = UInt32((word >> 4) & 0x07)
        let gLsb = UInt32((word >> 7) & 0x01)
        let gVal = (gMsbs << 1) | gLsb
        let g = gVal * 17

        // Blue channel
        let bMsbs = UInt32(word & 0x07)
        let bLsb = UInt32((word >> 3) & 0x01)
        let bVal = (bMsbs << 1) | bLsb
        let b = bVal * 17

        // Return ARGB format: Alpha is fully opaque (0xFF)
        return (0xFF << 24) | (r << 16) | (g << 8) | b
    }

    // MARK: - Decompression Helpers

    /// Decompresses standard PackBits (RLE) compressed data.
    public static func decompressPackBits(from data: Data, offset: Int, expectedSize: Int) -> Data {
        var output = Data()
        output.reserveCapacity(expectedSize)
        var i = offset
        while i < data.count && output.count < expectedSize {
            let cmd = Int8(bitPattern: data[i])
            i += 1
            if cmd >= 0 {
                // Copy cmd + 1 bytes literally
                let count = Int(cmd) + 1
                let copyCount = min(count, expectedSize - output.count)
                if i + copyCount <= data.count {
                    output.append(data[i..<(i + copyCount)])
                    i += copyCount
                } else {
                    break
                }
            } else if cmd != -128 {
                // Repeat next byte -cmd + 1 times
                let count = -Int(cmd) + 1
                if i < data.count {
                    let byte = data[i]
                    i += 1
                    let repeatCount = min(count, expectedSize - output.count)
                    output.append(contentsOf: repeatElement(byte, count: repeatCount))
                } else {
                    break
                }
            }
        }
        return output
    }

    /// Decompresses STAD RLE compressed data.
    public static func decompressSTAD(from data: Data, idByte: UInt8, packByte: UInt8, specialByte: UInt8, expectedSize: Int) -> Data {
        var output = Data()
        output.reserveCapacity(expectedSize)
        var i = 7 // STAD header is 7 bytes
        while i < data.count && output.count < expectedSize {
            let byte = data[i]
            i += 1
            if byte == idByte {
                if i < data.count {
                    let n = data[i]
                    i += 1
                    let repeatCount = min(Int(n) + 1, expectedSize - output.count)
                    output.append(contentsOf: repeatElement(packByte, count: repeatCount))
                }
            } else if byte == specialByte {
                if i + 1 < data.count {
                    let d = data[i]
                    let n = data[i + 1]
                    i += 2
                    let repeatCount = min(Int(n) + 1, expectedSize - output.count)
                    output.append(contentsOf: repeatElement(d, count: repeatCount))
                }
            } else {
                output.append(byte)
            }
        }
        return output
    }

    // MARK: - Main Entry Point

    /// Decodes an Atari ST graphics file from binary data.
    /// Supports: DEGAS (.PI1/2/3), DEGAS Elite (.PC1/2/3), NEOchrome (.NEO), STAD (.PAC), and Spectrum 512 (.SPU).
    public static func decode(data: Data, filename: String) -> DecodedAtariSTImage? {
        let ext = (filename as NSString).pathExtension.lowercased()

        if ext == "pi1" || ext == "pi2" || ext == "pi3" {
            return decodeDegas(data: data)
        }
        if ext == "pc1" || ext == "pc2" || ext == "pc3" {
            return decodeDegasElite(data: data)
        }
        if ext == "neo" {
            return decodeNeochrome(data: data)
        }
        if ext == "pac" || data.starts(with: [112, 77, 56, 53]) || data.starts(with: [112, 77, 56, 54]) { // "pM85" or "pM86"
            return decodeSTAD(data: data)
        }
        if ext == "spu" {
            return decodeSpectrum512SPU(data: data)
        }

        // Fallback detection by size or signature
        if data.count == 32034 {
            return decodeDegas(data: data)
        }
        if data.starts(with: [112, 77, 56, 53]) || data.starts(with: [112, 77, 56, 54]) {
            return decodeSTAD(data: data)
        }

        return nil
    }

    // MARK: - Format Decoders

    /// Decodes uncompressed DEGAS files.
    private static func decodeDegas(data: Data) -> DecodedAtariSTImage? {
        guard data.count >= 34 + 32000 else { return nil }
        let resolution = Int(data.readUInt16BE(at: 0))

        var palette = [UInt32]()
        for i in 0..<16 {
            let word = data.readUInt16BE(at: 2 + (i * 2))
            palette.append(decodeAtariColor(word))
        }

        let screenData = data.subdata(in: 34..<34+32000)
        guard let cgImg = decodePlanarScreen(data: screenData, resolution: resolution, palette: palette) else { return nil }

        let resText: String
        let paletteSlice: [UInt32]
        switch resolution {
        case 0: resText = "320x200 (16 colors)"; paletteSlice = palette
        case 1: resText = "640x200 (4 colors)"; paletteSlice = Array(palette.prefix(4))
        case 2: resText = "640x400 (Monochrome)"; paletteSlice = [0xFFFFFFFF, 0xFF000000]
        default: resText = "Unknown resolution"; paletteSlice = []
        }

        return DecodedAtariSTImage(
            cgImage: cgImg,
            formatName: "DEGAS uncompressed",
            resolutionText: resText,
            palette: paletteSlice
        )
    }

    /// Decodes compressed DEGAS Elite files.
    private static func decodeDegasElite(data: Data) -> DecodedAtariSTImage? {
        guard data.count >= 34 else { return nil }
        let resolution = Int(data.readUInt16BE(at: 0))

        var palette = [UInt32]()
        for i in 0..<16 {
            let word = data.readUInt16BE(at: 2 + (i * 2))
            palette.append(decodeAtariColor(word))
        }

        let decompressed = decompressPackBits(from: data, offset: 34, expectedSize: 32000)
        guard decompressed.count == 32000 else { return nil }

        guard let cgImg = decodePlanarScreen(data: decompressed, resolution: resolution, palette: palette) else { return nil }

        let resText: String
        let paletteSlice: [UInt32]
        switch resolution {
        case 0: resText = "320x200 (16 colors)"; paletteSlice = palette
        case 1: resText = "640x200 (4 colors)"; paletteSlice = Array(palette.prefix(4))
        case 2: resText = "640x400 (Monochrome)"; paletteSlice = [0xFFFFFFFF, 0xFF000000]
        default: resText = "Unknown resolution"; paletteSlice = []
        }

        return DecodedAtariSTImage(
            cgImage: cgImg,
            formatName: "DEGAS Elite compressed",
            resolutionText: resText,
            palette: paletteSlice
        )
    }

    /// Decodes NEOchrome files.
    private static func decodeNeochrome(data: Data) -> DecodedAtariSTImage? {
        guard data.count >= 128 + 32000 else { return nil }
        let resolution = Int(data.readUInt16BE(at: 2))

        var palette = [UInt32]()
        for i in 0..<16 {
            let word = data.readUInt16BE(at: 4 + (i * 2))
            palette.append(decodeAtariColor(word))
        }

        let screenData = data.subdata(in: 128..<128+32000)
        guard let cgImg = decodePlanarScreen(data: screenData, resolution: resolution, palette: palette) else { return nil }

        let resText: String
        let paletteSlice: [UInt32]
        switch resolution {
        case 0: resText = "320x200 (16 colors)"; paletteSlice = palette
        case 1: resText = "640x200 (4 colors)"; paletteSlice = Array(palette.prefix(4))
        case 2: resText = "640x400 (Monochrome)"; paletteSlice = [0xFFFFFFFF, 0xFF000000]
        default: resText = "Unknown resolution"; paletteSlice = []
        }

        return DecodedAtariSTImage(
            cgImage: cgImg,
            formatName: "NEOchrome",
            resolutionText: resText,
            palette: paletteSlice
        )
    }

    /// Decodes STAD (.PAC) files.
    private static func decodeSTAD(data: Data) -> DecodedAtariSTImage? {
        guard data.count >= 7 else { return nil }
        let signature = data.readASCIIString(at: 0, length: 4)
        guard signature == "pM85" || signature == "pM86" else { return nil }

        let idByte = data.readUInt8(at: 4)
        let packByte = data.readUInt8(at: 5)
        let specialByte = data.readUInt8(at: 6)

        let decompressed = decompressSTAD(from: data, idByte: idByte, packByte: packByte, specialByte: specialByte, expectedSize: 32000)
        guard decompressed.count == 32000 else { return nil }

        let formatText = signature == "pM85" ? "STAD horizontally packed" : "STAD vertically packed"

        if signature == "pM85" {
            guard let cgImg = decodePlanarScreen(data: decompressed, resolution: 2, palette: [0xFFFFFFFF, 0xFF000000]) else { return nil }
            return DecodedAtariSTImage(
                cgImage: cgImg,
                formatName: formatText,
                resolutionText: "640x400 (Monochrome)",
                palette: [0xFFFFFFFF, 0xFF000000]
            )
        } else {
            var pixels = [UInt32](repeating: 0xFFFFFFFF, count: 640 * 400)
            for b in 0..<4000 {
                let blockY = b % 50
                let blockX = b / 50
                for ly in 0..<8 {
                    let byteVal = decompressed[b * 8 + ly]
                    for px in 0..<8 {
                        let bit = (byteVal >> (7 - px)) & 1
                        let screenX = blockX * 8 + px
                        let screenY = blockY * 8 + ly
                        let color: UInt32 = (bit == 0) ? 0xFFFFFFFF : 0xFF000000
                        pixels[screenY * 640 + screenX] = color
                    }
                }
            }
            guard let cgImg = makeCGImage(width: 640, height: 400, pixels: pixels) else { return nil }
            return DecodedAtariSTImage(
                cgImage: cgImg,
                formatName: formatText,
                resolutionText: "640x400 (Monochrome)",
                palette: [0xFFFFFFFF, 0xFF000000]
            )
        }
    }

    /// Decodes uncompressed Spectrum 512 (.SPU) files.
    private static func decodeSpectrum512SPU(data: Data) -> DecodedAtariSTImage? {
        guard data.count >= 160 + 31840 + 19104 else { return nil }
        
        let screenOffset = 160
        let paletteOffset = 160 + 31840
        
        var pixels = [UInt32](repeating: 0xFF000000, count: 320 * 199)
        var previewPalette = [UInt32]() // Grab first scanline's palette for visual info in UI
        
        for y in 0..<199 {
            var scanlinePalette = [UInt32]()
            scanlinePalette.reserveCapacity(48)
            let linePaletteOffset = paletteOffset + y * 96
            for i in 0..<48 {
                let word = data.readUInt16BE(at: linePaletteOffset + (i * 2))
                let color = decodeAtariColor(word)
                scanlinePalette.append(color)
                if y == 100 && i < 16 { // Grab 16 colors from middle scanline for preview palette
                    previewPalette.append(color)
                }
            }
            
            let lineScreenOffset = screenOffset + y * 160
            for group in 0..<20 {
                let groupOffset = lineScreenOffset + group * 8
                let w0 = data.readUInt16BE(at: groupOffset)
                let w1 = data.readUInt16BE(at: groupOffset + 2)
                let w2 = data.readUInt16BE(at: groupOffset + 4)
                let w3 = data.readUInt16BE(at: groupOffset + 6)
                
                for p in 0..<16 {
                    let shift = 15 - p
                    let b0 = Int((w0 >> shift) & 1)
                    let b1 = Int((w1 >> shift) & 1)
                    let b2 = Int((w2 >> shift) & 1)
                    let b3 = Int((w3 >> shift) & 1)
                    let c = (b3 << 3) | (b2 << 2) | (b1 << 1) | b0
                    
                    let screenX = group * 16 + p
                    let paletteIdx = findIndex(x: screenX, c: c)
                    pixels[y * 320 + screenX] = scanlinePalette[paletteIdx]
                }
            }
        }
        
        guard let cgImg = makeCGImage(width: 320, height: 199, pixels: pixels) else { return nil }
        
        return DecodedAtariSTImage(
            cgImage: cgImg,
            formatName: "Spectrum 512 SPU",
            resolutionText: "320x199 (48 colors per scanline, 512 total)",
            palette: previewPalette.isEmpty ? Array(repeating: 0xFF000000, count: 16) : previewPalette
        )
    }

    private static func findIndex(x: Int, c: Int) -> Int {
        var x1 = 10 * c
        if (c & 1) != 0 {
            x1 = x1 - 5
        } else {
            x1 = x1 + 1
        }
        if x >= x1 && x < x1 + 160 {
            return c + 16
        } else if x >= x1 + 160 {
            return c + 32
        }
        return c
    }

    // MARK: - Planar Screen Decoder

    private static func decodePlanarScreen(data: Data, resolution: Int, palette: [UInt32]) -> CGImage? {
        switch resolution {
        case 0:
            var pixels = [UInt32](repeating: 0xFF000000, count: 320 * 200)
            for y in 0..<200 {
                let lineOffset = y * 160
                for group in 0..<20 {
                    let groupOffset = lineOffset + group * 8
                    let w0 = data.readUInt16BE(at: groupOffset)
                    let w1 = data.readUInt16BE(at: groupOffset + 2)
                    let w2 = data.readUInt16BE(at: groupOffset + 4)
                    let w3 = data.readUInt16BE(at: groupOffset + 6)
                    
                    for p in 0..<16 {
                        let shift = 15 - p
                        let b0 = Int((w0 >> shift) & 1)
                        let b1 = Int((w1 >> shift) & 1)
                        let b2 = Int((w2 >> shift) & 1)
                        let b3 = Int((w3 >> shift) & 1)
                        let c = (b3 << 3) | (b2 << 2) | (b1 << 1) | b0
                        
                        let color = (c < palette.count) ? palette[c] : 0xFF000000
                        pixels[y * 320 + group * 16 + p] = color
                    }
                }
            }
            return makeCGImage(width: 320, height: 200, pixels: pixels)
            
        case 1:
            var pixels = [UInt32](repeating: 0xFF000000, count: 640 * 200)
            for y in 0..<200 {
                let lineOffset = y * 160
                for group in 0..<40 {
                    let groupOffset = lineOffset + group * 4
                    let w0 = data.readUInt16BE(at: groupOffset)
                    let w1 = data.readUInt16BE(at: groupOffset + 2)
                    
                    for p in 0..<16 {
                        let shift = 15 - p
                        let b0 = Int((w0 >> shift) & 1)
                        let b1 = Int((w1 >> shift) & 1)
                        let c = (b1 << 1) | b0
                        
                        let color = (c < palette.count) ? palette[c] : 0xFF000000
                        pixels[y * 640 + group * 16 + p] = color
                    }
                }
            }
            return makeCGImage(width: 640, height: 200, pixels: pixels)
            
        case 2:
            var pixels = [UInt32](repeating: 0xFFFFFFFF, count: 640 * 400)
            for y in 0..<400 {
                let lineOffset = y * 80
                for group in 0..<40 {
                    let groupOffset = lineOffset + group * 2
                    let w0 = data.readUInt16BE(at: groupOffset)
                    
                    for p in 0..<16 {
                        let bit = (w0 >> (15 - p)) & 1
                        let color: UInt32 = (bit == 0) ? 0xFFFFFFFF : 0xFF000000
                        pixels[y * 640 + group * 16 + p] = color
                    }
                }
            }
            return makeCGImage(width: 640, height: 400, pixels: pixels)
            
        default:
            return nil
        }
    }

    // MARK: - CGImage Factory

    private static func makeCGImage(width: Int, height: Int, pixels: [UInt32]) -> CGImage? {
        var pixelData = pixels
        let dataCount = pixelData.count * MemoryLayout<UInt32>.size
        let data = Data(bytes: &pixelData, count: dataCount)
        
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
