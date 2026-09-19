import Foundation

public struct GatewayEndpoints: Sendable, Equatable {
    public let baseURL: URL
    public let modelsURL: URL
    public let completionsURL: URL

    public init(_ input: String) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty, !host.contains(where: { $0.isWhitespace }),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else {
            throw GatewayError.invalidURL
        }
        components.scheme = scheme
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/chat/completions") {
            path.removeLast("/chat/completions".count)
        } else if !path.hasSuffix("/v1") {
            path += "/v1"
        }
        components.percentEncodedPath = path
        guard let baseURL = components.url else { throw GatewayError.invalidURL }
        self.baseURL = baseURL
        modelsURL = baseURL.appendingPathComponent("models")
        completionsURL = baseURL.appendingPathComponent("chat/completions")
    }
}

public enum GatewayError: LocalizedError {
    case invalidURL
    case missingModel
    case httpStatus(Int)
    case invalidModels
    case connectionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Bad URL."
        case .missingModel: "Pick a model."
        case .httpStatus(let status): "Error \(status)."
        case .invalidModels: "No models."
        case .connectionFailed: "No connection."
        }
    }
}
