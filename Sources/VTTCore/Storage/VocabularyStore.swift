import Foundation

public final class VocabularyStore: @unchecked Sendable {
    private let lock = NSLock()
    private var aliases: [String: String] = [:]

    public init(initialAliases: [String: String] = [:]) {
        self.aliases = initialAliases
    }

    public func setAlias(from: String, to: String) {
        lock.lock()
        defer { lock.unlock() }
        aliases[from.lowercased()] = to
    }

    public func removeAlias(from: String) {
        lock.lock()
        defer { lock.unlock() }
        aliases.removeValue(forKey: from.lowercased())
    }

    public var allAliases: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return aliases
    }

    public func applyAliases(to input: String) -> String {
        lock.lock()
        let currentAliases = aliases
        lock.unlock()

        guard !currentAliases.isEmpty else { return input }

        var output = input
        for (pattern, replacement) in currentAliases {
            let regexPattern = "\\b\(NSRegularExpression.escapedPattern(for: pattern))\\b"
            if let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) {
                let range = NSRange(output.startIndex..<output.endIndex, in: output)
                output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
            }
        }
        return output
    }
}
