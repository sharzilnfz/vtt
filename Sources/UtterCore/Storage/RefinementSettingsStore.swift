import Foundation
import Security

@MainActor
public final class RefinementSettingsStore {
    public private(set) var config: RefinementEndpointConfig?
    private let defaults: UserDefaults
    private static let defaultsKey = "refinement.gateway.settings"
    private static let keychainService = "utter.refinement.gateway"
    private static let keychainAccount = "apiKey"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           var saved = try? JSONDecoder().decode(RefinementEndpointConfig.self, from: data),
           let endpoints = try? GatewayEndpoints(saved.url.absoluteString),
           !saved.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saved.url = endpoints.baseURL
            saved.apiKey = Self.readKeychain()
            config = saved
        }
    }

    public func save(baseURL: String, model: String, apiKey: String) throws {
        let endpoints = try GatewayEndpoints(baseURL)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw GatewayError.missingModel }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = RefinementEndpointConfig(
            url: endpoints.baseURL,
            apiKey: key.isEmpty ? nil : key,
            model: model
        )
        let data = try JSONEncoder().encode(updated)
        defaults.set(data, forKey: Self.defaultsKey)
        if key.isEmpty {
            Self.deleteKeychain()
        } else {
            Self.writeKeychain(key)
        }
        config = updated
    }

    public func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
        Self.deleteKeychain()
        config = nil
    }

    private static func writeKeychain(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty else { return nil }
        return string
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
