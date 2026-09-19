import Foundation
import UtterCore

private final class GatewayStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let status: Int
        let payload: String
        if url.path.contains("denied") {
            status = 401
            payload = "{}"
        } else if url.path.contains("malformed") {
            status = 200
            payload = "{}"
        } else if url.path.hasSuffix("/models") {
            precondition(request.httpMethod == "GET")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer session-secret")
            status = 200
            payload = #"{"data":[{"id":"provider/exact-model:free"},{"id":"Other.ID"},{"id":"Other.ID"}]}"#
        } else {
            precondition(request.httpMethod == "POST")
            precondition(url.path.hasSuffix("/v1/chat/completions"))
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer session-secret")
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }
                    body.append(contentsOf: bytes.prefix(count))
                }
            }
            let json = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
            let model = json["model"] as! String
            status = 200
            payload = "{\"choices\":[{\"message\":{\"content\":\"\(model)\"}}]}"
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
func runGatewayRegressionTests() async throws {
    for suffix in ["", "/", "/v1", "/v1/", "/v1/chat/completions", "/v1/chat/completions/"] {
        let endpoints = try GatewayEndpoints("https://gateway.invalid\(suffix)")
        precondition(endpoints.modelsURL.absoluteString == "https://gateway.invalid/v1/models")
        precondition(endpoints.completionsURL.absoluteString == "https://gateway.invalid/v1/chat/completions")
    }
    let existing = try GatewayEndpoints("https://gateway.invalid/custom/chat/completions")
    precondition(existing.completionsURL.absoluteString == "https://gateway.invalid/custom/chat/completions")
    precondition(existing.modelsURL.absoluteString == "https://gateway.invalid/custom/models")
    let prefixed = try GatewayEndpoints("http://gateway.invalid:9876/proxy/v1/chat/completions")
    precondition(prefixed.modelsURL.absoluteString == "http://gateway.invalid:9876/proxy/v1/models")
    for invalid in ["", "localhost:9876", "ftp://gateway.invalid", "https:///", "https://user:secret@gateway.invalid", "https://gateway.invalid?key=secret", "https://gateway.invalid#fragment", "https://gateway.invalid:70000"] {
        do {
            _ = try GatewayEndpoints(invalid)
            preconditionFailure("Accepted invalid URL")
        } catch GatewayError.invalidURL {}
    }
    let suite = "Utter-gateway-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = RefinementSettingsStore(defaults: defaults)
    store.clear()
    precondition(store.config == nil)
    try store.save(baseURL: "https://gateway.invalid", model: "first/model", apiKey: "session-secret")
    let restored = RefinementSettingsStore(defaults: defaults)
    precondition(restored.config?.model == "first/model")
    precondition(restored.config?.apiKey == "session-secret")
    let encoded = try JSONEncoder().encode(store.config!)
    precondition(!String(decoding: encoded, as: UTF8.self).contains("session-secret"))
    let previous = store.config
    do {
        try store.save(baseURL: "https://gateway.invalid", model: " ", apiKey: "")
        preconditionFailure("Accepted empty model")
    } catch GatewayError.missingModel {}
    precondition(store.config == previous)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GatewayStubProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let models = try await RefinementService.discoverModels(baseURL: "https://gateway.invalid", apiKey: "session-secret", session: session)
    precondition(models == ["Other.ID", "provider/exact-model:free"])
    let service = RefinementService(settings: store, session: session)
    let first = await service.refine(rawText: "raw")
    precondition(first == "first/model")
    try store.save(baseURL: "https://gateway.invalid/proxy", model: "second/model", apiKey: "session-secret")
    let second = await service.refine(rawText: "raw")
    precondition(second == "second/model")
    for path in ["denied", "malformed"] {
        do {
            _ = try await RefinementService.discoverModels(baseURL: "https://gateway.invalid/\(path)", apiKey: "session-secret", session: session)
            preconditionFailure("Accepted invalid model response")
        } catch is GatewayError {}
        try store.save(baseURL: "https://gateway.invalid/\(path)", model: "second/model", apiKey: "session-secret")
        let fallback = await service.refine(rawText: "raw preserved")
        precondition(fallback == "raw preserved")
    }
    store.clear()
    precondition(store.config == nil)

    if let routerKey = RefinementService.readLocal9RouterKey() {
        precondition(!routerKey.isEmpty)
        let liveConfig = RefinementEndpointConfig(
            url: URL(string: "http://localhost:20128/v1/chat/completions")!,
            apiKey: routerKey,
            model: "ag/gemini-3.8-flash-low",
            timeoutSeconds: 10
        )
        let liveService = RefinementService(config: liveConfig)
        let liveResult = await liveService.refine(rawText: "um so i have two items first apple and second banana")
        print("✔ Live 9router refinement: \(liveResult)")
        precondition(!liveResult.isEmpty)
        precondition(liveResult != "raw preserved")
    }

    print("Gateway regression tests passed")
}
