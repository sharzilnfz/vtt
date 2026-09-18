import Foundation

public struct RefinementEndpointConfig: Codable, Sendable, Equatable {
    public var url: URL
    public var apiKey: String? = nil
    public var model: String
    public var timeoutSeconds: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case url, model, timeoutSeconds
    }

    public init(
        url: URL = URL(string: "http://localhost:20128/v1")!,
        apiKey: String? = nil,
        model: String = "ag/gemini-3.8-flash-low",
        timeoutSeconds: TimeInterval = 5.0
    ) {
        self.url = url
        self.apiKey = apiKey
        self.model = model
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct AppConfiguration: Codable, Sendable, Equatable {
    public var refinementConfig: RefinementEndpointConfig
    public var playSounds: Bool
    public var revalidateTargetApp: Bool
    public var characterTypingDelayMicroseconds: UInt32
    public var maxTypingLengthForDirectKeyEvents: Int

    public init(
        refinementConfig: RefinementEndpointConfig = RefinementEndpointConfig(),
        playSounds: Bool = true,
        revalidateTargetApp: Bool = true,
        characterTypingDelayMicroseconds: UInt32 = 500,
        maxTypingLengthForDirectKeyEvents: Int = 300
    ) {
        self.refinementConfig = refinementConfig
        self.playSounds = playSounds
        self.revalidateTargetApp = revalidateTargetApp
        self.characterTypingDelayMicroseconds = characterTypingDelayMicroseconds
        self.maxTypingLengthForDirectKeyEvents = maxTypingLengthForDirectKeyEvents
    }
}
