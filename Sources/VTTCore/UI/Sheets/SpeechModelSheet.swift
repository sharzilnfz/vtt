import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class SpeechModelViewModel: ObservableObject {
    @Published public var selected: STTModelSelection
    @Published public var customLink: String = ""
    @Published public var statusMessage: String?
    @Published public var isError: Bool = false
    @Published public var isValidating: Bool = false
    @Published public var downloadProgress: Double = 0
    @Published public var isDownloading: Bool = false

    private let store: STTModelStore
    public var onApply: ((STTModelSelection) -> Void)?

    public init(store: STTModelStore) {
        self.store = store
        self.selected = store.selection
        if case .custom(let custom) = store.selection {
            self.customLink = "https://huggingface.co/\(custom.repo)"
        }
    }

    public func chooseBuiltIn() {
        selected = .builtIn(.v2)
        statusMessage = nil
        isError = false
    }

    public func validateLink() {
        let input = customLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            isError = true
            statusMessage = "Paste a Hugging Face link first."
            return
        }
        do {
            let repo = try STTModelStore.normalizeRepo(input)
            isError = false
            statusMessage = "Valid repo: \(repo). Uses the Parakeet 0.6B v2 layout."
            selected = .custom(CustomSTTModel(repo: repo))
        } catch {
            isError = true
            statusMessage = error.localizedDescription
        }
    }

    public func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                    let text: String? = {
                        if let url = item as? URL { return url.absoluteString }
                        if let str = item as? String { return str }
                        if let data = item as? Data {
                            if let url = URL(dataRepresentation: data, relativeTo: nil) { return url.absoluteString }
                            return String(data: data, encoding: .utf8)
                        }
                        return nil
                    }()
                    guard let text, !text.isEmpty else { return }
                    Task { @MainActor [weak self, text] in
                        self?.customLink = text
                        self?.validateLink()
                    }
                }
                return true
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                    let text: String? = {
                        if let str = item as? String { return str }
                        if let data = item as? Data { return String(data: data, encoding: .utf8) }
                        return nil
                    }()
                    guard let text, !text.isEmpty else { return }
                    Task { @MainActor [weak self, text] in
                        self?.customLink = text
                        self?.validateLink()
                    }
                }
                return true
            }
        }
        return false
    }

    public func apply() {
        if case .custom = selected {
            validateLink()
            guard !isError else { return }
        }
        store.select(selected)
        onApply?(selected)
    }
}

public struct SpeechModelSheet: View {
    @ObservedObject var state: DashboardState
    let isDark: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: SpeechModelViewModel

    public init(state: DashboardState, isDark: Bool) {
        self.state = state
        self.isDark = isDark
        let store = state.sttStore ?? STTModelStore()
        self._vm = StateObject(wrappedValue: SpeechModelViewModel(store: store))
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Speech Model")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(VTTTheme.text1(isDark: isDark))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(VTTTheme.text2(isDark: isDark))
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 6).fill(VTTTheme.surfaceHover(isDark: isDark)))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider().background(VTTTheme.borderSubtle(isDark: isDark))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("On-device CoreML transcription with Parakeet 0.6B v2. Paste a Hugging Face link or drop it below to use a compatible custom model instead.")
                        .font(.system(size: 12))
                        .foregroundColor(VTTTheme.text2(isDark: isDark))
                        .lineSpacing(2)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("BUILT IN")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(VTTTheme.text3(isDark: isDark))
                        builtInRow()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("CUSTOM MODEL LINK")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(VTTTheme.text3(isDark: isDark))
                        TextField("https://huggingface.co/org/repo or org/repo", text: $vm.customLink)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(VTTTheme.text1(isDark: isDark))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isDark ? VTTTheme.surfaceHover(isDark: true) : .white)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(VTTTheme.borderSubtle(isDark: isDark), lineWidth: 1))
                            )
                            .onDrop(of: [.url, .plainText], isTargeted: nil) { providers in
                                vm.handleDroppedProviders(providers)
                            }
                            .onSubmit { vm.validateLink() }

                        HStack(spacing: 8) {
                            Button("Validate") { vm.validateLink() }
                                .buttonStyle(VTTGhostButtonStyle(isDark: isDark))
                                .focusEffectDisabled()

                            Spacer()
                            Text("Drop a link anywhere here")
                                .font(.system(size: 11))
                                .foregroundColor(VTTTheme.text3(isDark: isDark))
                        }

                        if vm.isDownloading {
                            ProgressView(value: vm.downloadProgress, total: 1.0)
                                .progressViewStyle(.linear)
                        }

                        if let message = vm.statusMessage {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(vm.isError ? VTTTheme.stateConflict(isDark: isDark) : VTTTheme.stateSynced(isDark: isDark))
                                    .frame(width: 6, height: 6)
                                Text(message)
                                    .font(.system(size: 11))
                                    .foregroundColor(vm.isError ? VTTTheme.stateConflict(isDark: isDark) : VTTTheme.stateSynced(isDark: isDark))
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(vm.isError ? VTTTheme.stateConflictGlow(isDark: isDark).opacity(0.15) : VTTTheme.stateSyncedGlow(isDark: isDark).opacity(0.15))
                            )
                        }
                    }

                    HStack {
                        Button("Use v2 Default") {
                            vm.chooseBuiltIn()
                        }
                        .buttonStyle(VTTGhostButtonStyle(isDark: isDark))
                        .focusEffectDisabled()
                        Spacer()
                        Button("Save and Reload") {
                            vm.apply()
                            state.refreshSpeechModelDisplay()
                            state.showTransientBanner("Speech model updated", type: .success)
                            Task {
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                dismiss()
                            }
                        }
                        .buttonStyle(VTTPrimaryButtonStyle(isDark: isDark))
                        .focusEffectDisabled()
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 520, height: 560)
        .background(VTTTheme.glassBg(isDark: isDark))
        .preferredColorScheme(isDark ? .dark : .light)
        .onDrop(of: [.url, .plainText], isTargeted: nil) { providers in
            vm.handleDroppedProviders(providers)
        }
        .onAppear { [state, vm] in
            vm.onApply = { [weak state] selection in
                state?.onSpeechModelChanged?(selection)
            }
        }
    }

    private func builtInRow() -> some View {
        let model = BuiltInSTTModel.v2
        let isSelected: Bool = {
            if case .builtIn = vm.selected { return true }
            return false
        }()
        return Button(action: { vm.chooseBuiltIn() }) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? VTTTheme.stateSynced(isDark: isDark) : VTTTheme.text3(isDark: isDark))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(VTTTheme.text1(isDark: isDark))
                        Text(model.memoryEstimate)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(VTTTheme.text2(isDark: isDark))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(VTTTheme.surfaceHover(isDark: isDark)))
                    }
                    Text("\(model.detail) Languages: \(model.languages).")
                        .font(.system(size: 11))
                        .foregroundColor(VTTTheme.text3(isDark: isDark))
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? VTTTheme.stateSyncedGlow(isDark: isDark).opacity(0.12) : VTTTheme.surfaceHover(isDark: isDark).opacity(0.4))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? VTTTheme.stateSynced(isDark: isDark).opacity(0.5) : VTTTheme.borderSubtle(isDark: isDark), lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}
