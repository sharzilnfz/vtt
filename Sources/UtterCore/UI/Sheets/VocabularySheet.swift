import SwiftUI

@MainActor
public final class VocabularyViewModel: ObservableObject {
    @Published public var spokenPhrase: String = ""
    @Published public var replacementText: String = ""
    @Published public var activeAliases: [String: String] = [:]

    public init(aliases: [String: String] = [:]) {
        self.activeAliases = aliases
    }
}

public struct VocabularySheet: View {
    @ObservedObject var state: DashboardState
    let isDark: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: VocabularyViewModel

    public init(state: DashboardState, isDark: Bool) {
        self.state = state
        self.isDark = isDark
        self._vm = StateObject(wrappedValue: VocabularyViewModel(aliases: state.vocabularyStore?.allAliases ?? [:]))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Modal Header
            HStack {
                Text("Custom Vocabulary")
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
                Text("Map spoken phrases to technical jargon, acronyms, or custom formatting. Replacements are applied automatically immediately upon speech recognition.")
                    .font(.system(size: 12))
                    .foregroundColor(UtterTheme.text2(isDark: isDark))
                    .lineSpacing(2)

                // Add Row
                VStack(alignment: .leading, spacing: 6) {
                    Text("ADD NEW ALIAS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(UtterTheme.text3(isDark: isDark))

                    HStack(spacing: 8) {
                        TextField("When you say (e.g. PR)", text: $vm.spokenPhrase)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundColor(UtterTheme.text1(isDark: isDark))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isDark ? UtterTheme.surfaceHover(isDark: true) : Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(UtterTheme.borderSubtle(isDark: isDark), lineWidth: 1)
                                    )
                            )

                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(UtterTheme.text3(isDark: isDark))

                        TextField("Replace with (e.g. pull request)", text: $vm.replacementText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundColor(UtterTheme.text1(isDark: isDark))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isDark ? UtterTheme.surfaceHover(isDark: true) : Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(UtterTheme.borderSubtle(isDark: isDark), lineWidth: 1)
                                    )
                            )

                        Button("Add") {
                            addAlias()
                        }
                        .buttonStyle(UtterPrimaryButtonStyle(isDark: isDark))
                        .focusEffectDisabled()
                        .disabled(vm.spokenPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.replacementText.isEmpty)
                    }
                }

                // Active List
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("ACTIVE ALIASES")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(UtterTheme.text3(isDark: isDark))

                        Spacer()

                        Text("\(vm.activeAliases.count) configured")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(UtterTheme.text3(isDark: isDark))
                    }

                    ScrollView(.vertical) {
                        if vm.activeAliases.isEmpty {
                            Text("No custom vocabulary aliases configured yet.")
                                .font(.system(size: 12))
                                .foregroundColor(UtterTheme.text3(isDark: isDark))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 32)
                        } else {
                            LazyVStack(spacing: 4) {
                                ForEach(Array(vm.activeAliases.keys.sorted()), id: \.self) { key in
                                    HStack {
                                        Text(key)
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundColor(UtterTheme.text1(isDark: isDark))

                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(UtterTheme.text3(isDark: isDark))

                                        Text(vm.activeAliases[key] ?? "")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(UtterTheme.stateSynced(isDark: isDark))

                                        Spacer()

                                        Button(action: { removeAlias(key) }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                                .foregroundColor(UtterTheme.text3(isDark: isDark))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(UtterTheme.surfaceHover(isDark: isDark).opacity(0.6))
                                    )
                                }
                            }
                        }
                    }
                    .frame(height: 160)
                }

                Spacer(minLength: 4)

                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
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

    private func reloadAliases() {
        vm.activeAliases = state.vocabularyStore?.allAliases ?? [:]
    }

    private func addAlias() {
        let from = vm.spokenPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = vm.replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else { return }

        state.vocabularyStore?.setAlias(from: from, to: to)
        vm.spokenPhrase = ""
        vm.replacementText = ""
        reloadAliases()
    }

    private func removeAlias(_ key: String) {
        state.vocabularyStore?.removeAlias(from: key)
        reloadAliases()
    }
}
