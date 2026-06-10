// DateConverter.swift — AtariFileMgr
// Converts between Atari ST / MS-DOS FAT timestamp format and Swift Date.
//
// FAT Date encoding (16-bit):
//   Bits [15:9]  Year - 1980 (0-127, so 1980-2107)
//   Bits  [8:5]  Month (1-12)
//   Bits  [4:0]  Day   (1-31)
//
// FAT Time encoding (16-bit):
//   Bits [15:11] Hour   (0-23)
//   Bits  [10:5] Minute (0-59)
//   Bits   [4:0] Second / 2 (0-29, i.e., resolution is 2 seconds)

import Foundation

struct DateConverter {

    private static var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    // MARK: - Decode

    /// Decode a FAT date+time word pair into a Swift Date.
    static func date(fatDate: UInt16, fatTime: UInt16) -> Date {
        let year   = Int((fatDate >> 9) & 0x7F) + 1980
        let month  = Int((fatDate >> 5) & 0x0F)
        let day    = Int(fatDate & 0x1F)

        let hour   = Int((fatTime >> 11) & 0x1F)
        let minute = Int((fatTime >> 5)  & 0x3F)
        let second = Int(fatTime & 0x1F) * 2

        // Clamp values to valid ranges (disk may have corrupt timestamps)
        var comps = DateComponents()
        comps.year   = max(1980, year)
        comps.month  = max(1, min(12, month == 0 ? 1 : month))
        comps.day    = max(1, min(31, day   == 0 ? 1 : day))
        comps.hour   = min(23, hour)
        comps.minute = min(59, minute)
        comps.second = min(58, second)
        comps.timeZone = TimeZone(identifier: "UTC")

        return calendar.date(from: comps) ?? Date()
    }

    // MARK: - Encode

    /// Encode a Swift Date into FAT date and time words.
    static func fatTimestamp(from date: Date) -> (fatDate: UInt16, fatTime: UInt16) {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        let year   = max(0, (comps.year ?? 1980) - 1980)
        let month  = comps.month  ?? 1
        let day    = comps.day    ?? 1
        let hour   = comps.hour   ?? 0
        let minute = comps.minute ?? 0
        let second = (comps.second ?? 0) / 2  // 2-second resolution

        let fatDate = UInt16((year  & 0x7F) << 9)
                    | UInt16((month & 0x0F) << 5)
                    | UInt16( day   & 0x1F)

        let fatTime = UInt16((hour   & 0x1F) << 11)
                    | UInt16((minute & 0x3F) << 5)
                    | UInt16( second & 0x1F)

        return (fatDate, fatTime)
    }

    // MARK: - Formatting

    static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yy HH:mm"
        return f
    }()

    static func displayString(fatDate: UInt16, fatTime: UInt16) -> String {
        let d = date(fatDate: fatDate, fatTime: fatTime)
        return displayFormatter.string(from: d)
    }
}
