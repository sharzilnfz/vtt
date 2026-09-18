import ApplicationServices
import CoreGraphics
import Foundation

public typealias KeySynthesizing = KeySynthesizer

public final class KeySynthesizer: Sendable {
    public init() {}

    public func type(text: String, characterDelayMicroseconds: UInt32 = 1200) -> Bool {
        guard !text.isEmpty, (CGPreflightPostEventAccess() || AXIsProcessTrusted()),
              let source = CGEventSource(stateID: .combinedSessionState) ?? CGEventSource(stateID: .hidSystemState) else { return false }
        var events: [(CGEvent, CGEvent)] = []
        for scalar in text.unicodeScalars {
            let virtualKey: CGKeyCode
            switch scalar.value {
            case 10, 13:
                virtualKey = 36
            case 9:
                virtualKey = 48
            default:
                virtualKey = 0
            }
            let units = Array(String(scalar).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
                return false
            }
            down.flags = []
            up.flags = []
            units.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
            }
            events.append((down, up))
        }
        // Allocate every event before posting so a failed allocation cannot duplicate a typed prefix on fallback.
        for (down, up) in events {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            if characterDelayMicroseconds > 0 { usleep(characterDelayMicroseconds) }
        }
        return true
    }
}
