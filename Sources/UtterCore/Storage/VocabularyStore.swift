import Foundation

public final class VocabularyStore: @unchecked Sendable {
    private struct CompiledAlias: Sendable {
        let pattern: String
        let replacement: String
        let regex: NSRegularExpression?
    }

    private let lock = NSLock()
    private var aliases: [String: String] = [:]
    private var compiledList: [CompiledAlias] = []
    private let fileURL: URL?

    public static var defaultFileURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("utter", isDirectory: true).appendingPathComponent("vocabulary.json")
    }

    public init(initialAliases: [String: String] = [:], fileURL: URL? = nil) {
        self.fileURL = fileURL
        var loaded = initialAliases
        if initialAliases.isEmpty, let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            if let data = try? Data(contentsOf: fileURL),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                loaded = decoded
            }
        }
        self.aliases = loaded
        self.rebuildCompiledListLocked()
    }

    public func setAlias(from: String, to: String) {
        lock.lock()
        aliases[from.lowercased()] = to
        rebuildCompiledListLocked()
        lock.unlock()
    }

    public func removeAlias(from: String) {
        lock.lock()
        aliases.removeValue(forKey: from.lowercased())
        rebuildCompiledListLocked()
        lock.unlock()
    }

    public var allAliases: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return aliases
    }

    public func applyAliases(to input: String) -> String {
        lock.lock()
        let currentCompiled = compiledList
        lock.unlock()

        guard !currentCompiled.isEmpty else { return input }

        var output = input
        for item in currentCompiled {
            guard let regex = item.regex else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(
                in: output,
                options: [],
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: item.replacement)
            )
        }
        return output
    }

    private func rebuildCompiledListLocked() {
        var list: [CompiledAlias] = []
        for (pattern, replacement) in aliases {
            let regexPattern = "\\b\(NSRegularExpression.escapedPattern(for: pattern))\\b"
            let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive)
            list.append(CompiledAlias(pattern: pattern, replacement: replacement, regex: regex))
        }
        compiledList = list
        persistIfNeededLocked()
    }

    private func persistIfNeededLocked() {
        guard let fileURL else { return }
        let snapshot = aliases
        Task.detached(priority: .utility) {
            do {
                let dir = fileURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: dir.path) {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
            } catch {}
        }
    }
}
