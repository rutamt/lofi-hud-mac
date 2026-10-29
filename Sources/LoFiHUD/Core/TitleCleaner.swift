import Foundation

/// Turns audio filenames into clean, title-cased display names.
enum TitleCleaner {
    private static let prefix = try! NSRegularExpression(
        pattern: #"^(y2mate\.com|ytmp3\.cc|snaptik)\s*[-_]?\s*"#, options: .caseInsensitive)
    private static let trackNumber = try! NSRegularExpression(
        pattern: #"^\d{1,3}\s*[\.\-_]\s*"#)
    private static let noise: [NSRegularExpression] = [
        #"\((?:official\s*(?:video|audio|music\s*video)|visualizer|lyrics|audio|320\s*kbps|hq|hd|4k)\)"#,
        #"\[(?:official\s*(?:video|audio|music\s*video)|visualizer|lyrics|audio|320\s*kbps|flac|hq|hd|4k|lofi\s*(?:beats|hip\s*hop|chill)?)\]"#,
    ].map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    private static let separators = try! NSRegularExpression(pattern: #"[-_]+"#)
    private static let whitespace = try! NSRegularExpression(pattern: #"\s+"#)

    static func clean(url: URL) -> String { clean(filename: url.lastPathComponent) }

    static func clean(filename: String) -> String {
        var name = (filename as NSString).deletingPathExtension
        name = replace(prefix, in: name, with: "")
        name = replace(trackNumber, in: name, with: "")
        for pattern in noise { name = replace(pattern, in: name, with: "") }
        name = replace(separators, in: name, with: " ")
        name = replace(whitespace, in: name, with: " ").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Unknown Track" : titleCase(name)
    }

    /// Python-style `str.title()`, except apostrophes don't start a new word ("Don't", not "Don'T").
    static func titleCase(_ s: String) -> String {
        var out = ""
        var prevIsWordChar = false
        for ch in s {
            if ch.isLetter {
                out += prevIsWordChar ? ch.lowercased() : ch.uppercased()
                prevIsWordChar = true
            } else {
                out.append(ch)
                prevIsWordChar = prevIsWordChar && (ch == "'" || ch == "’")
            }
        }
        return out
    }

    private static func replace(_ re: NSRegularExpression, in s: String, with t: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: t)
    }
}
