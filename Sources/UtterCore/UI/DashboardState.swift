import AppKit
import AVFoundation
import Combine
import SwiftUI

@preconcurrency import ApplicationServices

public enum UtterAppTheme: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light
    case system

    public var id: String { rawValue }
}

public struct ActivityItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let subtitle: String?
    public let timestamp: Date
    public let kind: ActivityKind
    public let rawText: String?
    public let refinedText: String?

    public enum ActivityKind: Sendable, Equatable {
        case transcript
        case refinement
    }

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        timestamp: Date = Date(),
        kind: ActivityKind = .transcript,
        rawText: String? = nil,
        refinedText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.timestamp = timestamp
        self.kind = kind
        self.rawText = rawText
        self.refinedText = refinedText
    }
}

@MainActor
public final class DashboardState: ObservableObject {
    public let safetyBuffer: SafetyBuffer
    public let settingsStore: RefinementSettingsStore
    public let statsStore: StatsStore?
    public let vocabularyStore: VocabularyStore?
    public let sttStore: STTModelStore?
    public weak var coordinator: DictationCoordinator?

    @Published public var modelState: ModelLoadState = .loading
    @Published public var micAuthorized: Bool = false
    @Published public var accessTrusted: Bool = false
    @Published public var activeTheme: UtterAppTheme = .dark
    @Published public var activities: [ActivityItem] = []
    @Published public var isRecording: Bool = false
    @Published public var audioLevel: Float = 0.0
    @Published public var isTranscribing: Bool = false
    @Published public var bannerMessage: String?
    @Published public var bannerType: BannerType = .info
    @Published public var speechModelLabel: String = "Parakeet 0.6B v2"
    private var bannerTask: Task<Void, Never>?

    // Modals
    @Published public var showGatewaySheet: Bool = false
    @Published public var showVocabularySheet: Bool = false
    @Published public var showSpeechSheet: Bool = false
    @Published public var selectedTranscript: Transcript?

    public enum BannerType {
        case info
        case warning
        case error
        case success
    }

    public var isDarkMode: Bool {
        switch activeTheme {
        case .dark: return true
        case .light: return false
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    public var permissionsReady: Bool {
        micAuthorized && accessTrusted
    }

    public var abbreviatedSpeechModelLabel: String {
        let label = speechModelLabel
        if label.isEmpty { return "Parakeet" }
        if label.localizedCaseInsensitiveContains("Parakeet") {
            return "Parakeet"
        }
        if label.count > 10 {
            return String(label.prefix(10))
        }
        return label
    }

    public var onRetryModel: (() -> Void)?
    public var onPermissionsChanged: (() -> Void)?
    public var onSpeechModelChanged: ((STTModelSelection) -> Void)?

    public init(
        safetyBuffer: SafetyBuffer,
        settingsStore: RefinementSettingsStore,
        statsStore: StatsStore? = nil,
        vocabularyStore: VocabularyStore? = nil,
        coordinator: DictationCoordinator? = nil,
        sttStore: STTModelStore? = nil
    ) {
        self.safetyBuffer = safetyBuffer
        self.settingsStore = settingsStore
        self.statsStore = statsStore
        self.vocabularyStore = vocabularyStore
        self.coordinator = coordinator
        self.sttStore = sttStore

        // Load theme preference or default to dark
        let savedTheme = UserDefaults.standard.string(forKey: "utter.theme") ?? "dark"
        self.activeTheme = UtterAppTheme(rawValue: savedTheme) ?? .dark

        refreshPermissions()
        refreshActivitiesFromTranscripts()
        refreshSpeechModelDisplay()
    }

    public func refreshSpeechModelDisplay() {
        if let selection = sttStore?.selection {
            speechModelLabel = selection.displayName
        }
    }

    public func setTheme(_ theme: UtterAppTheme) {
        activeTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "utter.theme")
    }

    public func toggleTheme() {
        setTheme(isDarkMode ? .light : .dark)
    }

    public func refreshPermissions() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        micAuthorized = (status == .authorized)
        accessTrusted = AXIsProcessTrusted()
    }

    public func requestMicrophone() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            Task { [weak self] in
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                self?.refreshPermissions()
                self?.onPermissionsChanged?()
            }
        } else {
            openPrivacySettings("Microphone")
        }
    }

    public func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if !AXIsProcessTrusted() {
            openPrivacySettings("Accessibility")
        }
        refreshPermissions()
        onPermissionsChanged?()
    }

    public func openPrivacySettings(_ category: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(category)") else { return }
        NSWorkspace.shared.open(url)
    }

    public func refreshActivitiesFromTranscripts() {
        let items = safetyBuffer.allItems
        for transcript in items.reversed() {
            if let index = activities.firstIndex(where: { $0.id == transcript.id }) {
                if transcript.refinedText != nil && activities[index].refinedText == nil {
                    let refinedPreview = transcript.refinedText!.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                    let shortPreview = String(refinedPreview.prefix(45))
                    activities[index] = ActivityItem(
                        id: transcript.id,
                        title: shortPreview.isEmpty ? activities[index].title : shortPreview,
                        subtitle: activities[index].subtitle,
                        timestamp: activities[index].timestamp,
                        kind: .refinement,
                        rawText: transcript.rawText,
                        refinedText: transcript.refinedText
                    )
                }
            } else {
                let textToPreview = transcript.refinedText ?? transcript.rawText
                let preview = textToPreview.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                let shortPreview = String(preview.prefix(45))
                activities.insert(
                    ActivityItem(
                        id: transcript.id,
                        title: shortPreview.isEmpty ? "Dictation recorded" : shortPreview,
                        subtitle: transcript.targetApplication?.bundleIdentifier ?? "Direct Insertion",
                        timestamp: transcript.createdAt,
                        kind: transcript.refinedText != nil ? .refinement : .transcript,
                        rawText: transcript.rawText,
                        refinedText: transcript.refinedText
                    ),
                    at: 0
                )
            }
        }
    }

    public func addActivity(title: String, subtitle: String? = nil, kind: ActivityItem.ActivityKind = .transcript) {
        let item = ActivityItem(title: title, subtitle: subtitle, timestamp: Date(), kind: kind)
        activities.insert(item, at: 0)
        if activities.count > 50 {
            activities.removeLast()
        }
    }

    public func clearActivities() {
        activities.removeAll()
        safetyBuffer.clear()
    }

    public func copyLastTranscript() {
        if let last = safetyBuffer.lastTranscript {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(last.textToInsert, forType: .string)
            showTransientBanner("Copied last transcript", type: .success)
        }
    }

    public func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showTransientBanner("Copied to clipboard", type: .success)
    }

    public func showTransientBanner(_ message: String, type: BannerType = .info, duration: TimeInterval = 2.5) {
        bannerTask?.cancel()
        bannerMessage = message
        bannerType = type
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self, self.bannerMessage == message else { return }
            self.bannerMessage = nil
        }
    }
}
