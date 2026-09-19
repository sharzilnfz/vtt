import Foundation

public enum BuiltInSTTModel: String, Codable, Sendable, Identifiable {
    case v2

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = .v2
        _ = raw
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("v2")
    }

    public var displayName: String { "Parakeet 0.6B v2" }
    public var shortLabel: String { "0.6B v2" }
    public var detail: String { "English. 2.6% WER. 477-623 MB. Balanced." }
    public var memoryEstimate: String { "~500 MB" }
    public var languages: String { "English" }
}

public struct CustomSTTModel: Codable, Sendable, Equatable {
    public var repo: String
    public var displayName: String

    private enum CodingKeys: String, CodingKey {
        case repo
        case displayName
    }

    public init(repo: String, displayName: String? = nil) {
        self.repo = repo
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.displayName = displayName
        } else {
            self.displayName = repo
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let repo = try container.decode(String.self, forKey: .repo)
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? repo
        self.repo = repo
        self.displayName = displayName
    }

    public var canonicalURL: URL? {
        URL(string: "https://huggingface.co/\(repo)")
    }
}

public enum STTModelSelection: Codable, Sendable, Equatable {
    case builtIn(BuiltInSTTModel)
    case custom(CustomSTTModel)

    public var displayName: String {
        switch self {
        case .builtIn(let model): return model.displayName
        case .custom(let custom): return custom.displayName
        }
    }

    public var shortLabel: String {
        switch self {
        case .builtIn(let model): return model.shortLabel
        case .custom: return "Custom"
        }
    }

    public var effectiveBuiltIn: BuiltInSTTModel { .v2 }

    public var customRepo: String? {
        switch self {
        case .builtIn: return nil
        case .custom(let custom): return custom.repo
        }
    }
}

public enum STTModelLinkError: LocalizedError, Equatable {
    case empty
    case invalidFormat(String)
    case unsupportedHost(String)

    public var errorDescription: String? {
        switch self {
        case .empty: return "Paste a Hugging Face model link."
        case .invalidFormat(let input): return "Could not parse a model repo from \"\(input)\". Use https://huggingface.co/org/repo or org/repo."
        case .unsupportedHost(let host): return "Host \"\(host)\" is not a Hugging Face repo link."
        }
    }
}

@MainActor
public final class STTModelStore {
    public private(set) var selection: STTModelSelection
    private let defaults: UserDefaults
    private static let defaultsKey = "utter.stt.model.selection"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(STTModelSelection.self, from: data) {
            self.selection = STTModelStore.migrated(saved)
        } else {
            self.selection = .builtIn(.v2)
        }
    }

    private static func migrated(_ saved: STTModelSelection) -> STTModelSelection {
        switch saved {
        case .builtIn: return .builtIn(.v2)
        case .custom(let custom):
            let repo = (try? normalizeRepo(custom.repo)) ?? custom.repo
            return .custom(CustomSTTModel(repo: repo, displayName: custom.displayName))
        }
    }

    public func select(_ selection: STTModelSelection) {
        self.selection = STTModelStore.migrated(selection)
        persist()
    }

    public func selectBuiltIn() {
        select(.builtIn(.v2))
    }

    public func selectCustom(repo: String, displayName: String? = nil) throws {
        let normalized = try Self.normalizeRepo(repo)
        select(.custom(CustomSTTModel(repo: normalized, displayName: displayName)))
    }

    public func clearCustom() {
        selection = .builtIn(.v2)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    public nonisolated static func normalizeRepo(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw STTModelLinkError.empty }
        var candidate = trimmed
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https", "hf"].contains(scheme) {
            guard scheme != "http" && scheme != "https" || url.host != nil else {
                throw STTModelLinkError.invalidFormat(trimmed)
            }
            if scheme == "hf" {
                candidate = url.host.map { $0 + url.path } ?? url.path
            } else {
                guard let host = url.host?.lowercased() else { throw STTModelLinkError.invalidFormat(trimmed) }
                guard host == "huggingface.co" || host == "www.huggingface.co" || host == "hf.co" else {
                    throw STTModelLinkError.unsupportedHost(host)
                }
                candidate = url.path
                if let queryRange = candidate.range(of: "?") {
                    candidate = String(candidate[..<queryRange.lowerBound])
                }
            }
        } else if trimmed.lowercased().hasPrefix("huggingface.co/") {
            candidate = String(trimmed.dropFirst("huggingface.co/".count))
        } else if trimmed.lowercased().hasPrefix("www.huggingface.co/") {
            candidate = String(trimmed.dropFirst("www.huggingface.co/".count))
        }
        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if candidate.hasPrefix("tree/main/") {
            candidate = String(candidate.dropFirst("tree/main/".count))
        }
        var parts = candidate.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        if parts.count > 2 {
            if parts[0].lowercased() == "models" {
                parts.removeFirst()
            }
            if parts.count > 2 {
                parts = Array(parts.prefix(2))
            }
        }
        guard parts.count == 2 else { throw STTModelLinkError.invalidFormat(trimmed) }
        let org = parts[0].trimmingCharacters(in: .whitespaces)
        let repo = parts[1].trimmingCharacters(in: .whitespaces)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard !org.isEmpty, !repo.isEmpty,
              org.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              repo.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw STTModelLinkError.invalidFormat(trimmed)
        }
        return "\(org)/\(repo)"
    }

    public nonisolated static func canonicalURL(for repo: String) -> URL? {
        URL(string: "https://huggingface.co/\(repo)")
    }
}
