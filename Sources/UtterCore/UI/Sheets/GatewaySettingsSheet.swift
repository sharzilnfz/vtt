import SwiftUI

@MainActor
public final class GatewaySettingsViewModel: ObservableObject {
    @Published public var baseURL: String = ""
    @Published public var apiKey: String = ""
    @Published public var model: String = ""
    @Published public var discoveredModels: [String] = []
    @Published public var isLoadingModels: Bool = false
    @Published public var statusMessage: String?
    @Published public var isError: Bool = false

    public init(config: RefinementEndpointConfig?) {
        if let config {
            if let endpoints = try? GatewayEndpoints(config.url.absoluteString) {
                self.baseURL = endpoints.baseURL.absoluteString
            } else {
                self.baseURL = config.url.absoluteString
            }
            self.apiKey = config.apiKey ?? ""
            self.model = config.model
        } else {
            self.baseURL = "http://localhost:20128/v1"
            self.model = "ag/gemini-3.8-flash-low"
            self.apiKey = RefinementService.readLocal9RouterKey() ?? ""
        }
    }
}

public struct GatewaySettingsSheet: View {
    @ObservedObject var state: DashboardState
    let isDark: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: GatewaySettingsViewModel

    public init(state: DashboardState, isDark: Bool) {
        self.state = state
        self.isDark = isDark
        self._vm = StateObject(wrappedValue: GatewaySettingsViewModel(config: state.settingsStore.config))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Modal Header
            HStack {
                Text("AI Refinement Gateway")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(UtterTheme.text1(isDark: isDark))

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(UtterIconButtonStyle(isDark: isDark))
                .focusEffectDisabled()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()
                .background(UtterTheme.borderSubtle(isDark: isDark))

            // Modal Content
            VStack(alignment: .leading, spacing: 16) {
                Text("Configure an OpenAI-compatible endpoint to automatically polish, punctuate, and format your transcripts when holding Option + Command.")
                    .font(.system(size: 12))
                    .foregroundColor(UtterTheme.text2(isDark: isDark))
                    .lineSpacing(2)

                // Base URL Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("BASE URL")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(UtterTheme.text3(isDark: isDark))

                    TextField("https://api.openai.com/v1", text: $vm.baseURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(UtterTheme.text1(isDark: isDark))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isDark ? UtterTheme.surfaceHover(isDark: true) : Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(UtterTheme.borderSubtle(isDark: isDark), lineWidth: 1)
                                )
                        )
                }

                // API Key Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("API KEY (OPTIONAL FOR LOCAL MODELS)")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(UtterTheme.text3(isDark: isDark))

                    SecureField("sk-...", text: $vm.apiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(UtterTheme.text1(isDark: isDark))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isDark ? UtterTheme.surfaceHover(isDark: true) : Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(UtterTheme.borderSubtle(isDark: isDark), lineWidth: 1)
                                )
                        )
                }

                // Model Selection / Input
                VStack(alignment: .leading, spacing: 4) {
                    Text("MODEL")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(UtterTheme.text3(isDark: isDark))

                    HStack(spacing: 8) {
                        TextField("gpt-4o-mini", text: $vm.model)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(UtterTheme.text1(isDark: isDark))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isDark ? UtterTheme.surfaceHover(isDark: true) : Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(UtterTheme.borderSubtle(isDark: isDark), lineWidth: 1)
                                    )
                            )

                        Button(action: loadModels) {
                            HStack(spacing: 4) {
                                if vm.isLoadingModels {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                                Text("Discover")
                            }
                        }
                        .buttonStyle(UtterGhostButtonStyle(isDark: isDark))
                        .focusEffectDisabled()
                        .disabled(vm.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLoadingModels)
                    }

                    if !vm.discoveredModels.isEmpty {
                        Menu {
                            ForEach(vm.discoveredModels, id: \.self) { item in
                                Button(item) {
                                    vm.model = item
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(vm.model.isEmpty ? "Select from \(vm.discoveredModels.count) discovered models" : "Model: \(vm.model)")
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(UtterTheme.text1(isDark: isDark))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isDark ? UtterTheme.surfaceHover(isDark: true) : Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(UtterTheme.borderSubtle(isDark: isDark), lineWidth: 1)
                                    )
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .focusEffectDisabled()
                        .padding(.top, 2)
                    }
                }

                // Status banner
                if let message = vm.statusMessage {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(vm.isError ? UtterTheme.stateConflict(isDark: isDark) : UtterTheme.stateSynced(isDark: isDark))
                            .frame(width: 6, height: 6)

                        Text(message)
                            .font(.system(size: 11))
                            .foregroundColor(vm.isError ? UtterTheme.stateConflict(isDark: isDark) : UtterTheme.stateSynced(isDark: isDark))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(vm.isError ? UtterTheme.stateConflictGlow(isDark: isDark).opacity(0.15) : UtterTheme.stateSyncedGlow(isDark: isDark).opacity(0.15))
                    )
                }

                Spacer(minLength: 8)

                // Actions Row
                HStack {
                    Button("Clear Config") {
                        state.settingsStore.clear()
                        vm.baseURL = ""
                        vm.apiKey = ""
                        vm.model = ""
                        vm.statusMessage = "Configuration cleared."
                        vm.isError = false
                        state.showTransientBanner("Gateway Cleared", type: .info)
                        Task {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            dismiss()
                        }
                    }
                    .buttonStyle(UtterGhostButtonStyle(isDark: isDark))
                    .focusEffectDisabled()

                    Spacer()

                    Button("Save Configuration") {
                        saveConfig()
                    }
                    .buttonStyle(UtterPrimaryButtonStyle(isDark: isDark))
                    .focusEffectDisabled()
                }
            }
            .padding(24)
        }
        .frame(width: 480)
        .background(UtterTheme.glassBg(isDark: isDark))
        .preferredColorScheme(isDark ? .dark : .light)
    }

    private func loadModels() {
        vm.isLoadingModels = true
        vm.statusMessage = "Querying endpoint for available models…"
        vm.isError = false

        let url = vm.baseURL
        let key = vm.apiKey

        Task {
            do {
                let models = try await RefinementService.discoverModels(baseURL: url, apiKey: key)
                await MainActor.run {
                    self.vm.discoveredModels = models
                    self.vm.isLoadingModels = false
                    if models.isEmpty {
                        self.vm.statusMessage = "No models reported by endpoint."
                    } else {
                        self.vm.statusMessage = "Found \(models.count) models. Pick one from the dropdown."
                        if self.vm.model.isEmpty, let first = models.first {
                            self.vm.model = first
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.vm.isLoadingModels = false
                    self.vm.isError = true
                    self.vm.statusMessage = "Failed to load models: \(error.localizedDescription)"
                }
            }
        }
    }

    private func saveConfig() {
        do {
            try state.settingsStore.save(baseURL: vm.baseURL, model: vm.model, apiKey: vm.apiKey)
            vm.statusMessage = "Configuration saved successfully."
            vm.isError = false
            state.showTransientBanner("Gateway Saved", type: .success)
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                dismiss()
            }
        } catch {
            vm.isError = true
            vm.statusMessage = "Save error: \(error.localizedDescription)"
        }
    }
}
