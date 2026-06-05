import SwiftUI
import AppKit
import KairuCore

/// アプリ内の設定画面。プロバイダを選んで API キーを貼り付けるだけで使える。
/// キーは本人のみ読めるファイル（credentials.json, 権限600）に保管する。
struct SettingsView: View {
    @ObservedObject var model: AppModel
    var onSaved: () -> Void

    private let customTag = "__custom__"

    @State private var provider: Provider = .claude
    @State private var apiKey: String = ""
    @State private var modelTag: String = ""
    @State private var customModel: String = ""
    @State private var systemPrompt: String = AppConfig.defaultSystemPrompt
    @State private var resurrect = LaunchAgent.isEnabled
    @State private var annoy = true
    @State private var saved = false

    private var effectiveModel: String {
        let m = modelTag == customTag
            ? customModel.trimmingCharacters(in: .whitespacesAndNewlines)
            : modelTag
        return m.isEmpty ? provider.defaultModel : m
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("MacKairu 設定").font(.system(size: 16, weight: .bold))
                providerSection
                apiKeySection
                modelSection
                promptSection
                resurrectSection
                annoySection
                characterSection
                Divider()
                footer
            }
            .padding(20)
        }
        .frame(width: 440)
        .onAppear { loadCurrent() }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI プロバイダ").font(.system(size: 12, weight: .semibold))
            Picker("", selection: $provider) {
                ForEach(Provider.allCases) { p in Text(p.label).tag(p) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .onChange(of: provider) { _, newValue in
                modelTag = newValue.models.first ?? customTag
                customModel = ""
                apiKey = Credentials.get(for: newValue) ?? ""
            }
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("API キー").font(.system(size: 12, weight: .semibold))
                Spacer()
                Link("キーを取得 ↗", destination: URL(string: provider.keyURL)!)
                    .font(.system(size: 11))
            }
            HStack(spacing: 6) {
                SecureField("ここに API キーを貼り付け", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Button("貼り付け") {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        apiKey = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            Text("キーは本人のみ読めるファイル（~/.config/mac-concierge/credentials.json、権限600）に保存。送信先は選んだ提供元の API のみ（HTTPS）。config.json や会話ログには残しません。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("モデル").font(.system(size: 12, weight: .semibold))
            Picker("", selection: $modelTag) {
                ForEach(provider.models, id: \.self) { m in
                    let note = provider.modelNote(m)
                    Text(note.isEmpty ? m : "\(m)（\(note)）").tag(m)
                }
                Divider()
                Text("カスタム（手入力）…").tag(customTag)
            }
            .labelsHidden()
            if modelTag == customTag {
                TextField("モデル ID を入力", text: $customModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("AI への指示（システムプロンプト）").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("既定に戻す") { systemPrompt = AppConfig.defaultSystemPrompt }
                    .font(.system(size: 11))
            }
            TextEditor(text: $systemPrompt)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 150)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
            Text("会話のたびに、この指示＋これまでの会話が AI に送られます。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var resurrectSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $resurrect) {
                Text("消えても15分ごとに復活する（しつこいカイル）")
                    .font(.system(size: 12, weight: .semibold))
            }
            .onChange(of: resurrect) { _, on in
                if on { LaunchAgent.enable() } else { LaunchAgent.disable() }
            }
            Text("オンにすると、終了しても 15 分以内にまた現れます（ログイン時にも自動起動）。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var annoySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $annoy) {
                Text("おせっかい（うざ）モード")
                    .font(.system(size: 12, weight: .semibold))
            }
            .onChange(of: annoy) { _, on in
                UserDefaults.standard.set(on, forKey: "annoyMode")
            }
            Text("勝手に泳いで動く・たまに話しかける・終了しようとすると引き止める。オフで全部おとなしくなります。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var characterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("キャラクター").font(.system(size: 12, weight: .semibold))
            Picker("", selection: Binding(
                get: { model.character == .girl ? Character.dolphin : model.character },
                set: { model.setCharacter($0) })) {
                ForEach(Character.selectable) { c in
                    Text("\(c.emoji) \(c.label)").tag(c)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if model.character == .girl {
                HStack(spacing: 8) {
                    Text("裏キャラ 💗（チャットに「裏モード」で切替）")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button("画像を選ぶ") { model.chooseGirlImage() }.font(.system(size: 11))
                    Button("AIで生成") { model.generateGirlImage() }.font(.system(size: 11))
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("終了") { KairuQuit.request() }
                .font(.system(size: 11))
            if saved {
                Label("保存しました", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(.green)
            }
            Spacer()
            Button("保存して使う") { save() }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func loadCurrent() {
        resurrect = LaunchAgent.isEnabled
        let d = UserDefaults.standard
        annoy = d.object(forKey: "annoyMode") == nil ? true : d.bool(forKey: "annoyMode")
        if let c = model.config {
            provider = c.provider
            apiKey = c.apiKey
            systemPrompt = c.systemPrompt ?? AppConfig.defaultSystemPrompt
            if c.provider.models.contains(c.model) {
                modelTag = c.model
            } else {
                modelTag = customTag
                customModel = c.model
            }
        } else {
            provider = .claude
            modelTag = Provider.claude.defaultModel
            systemPrompt = AppConfig.defaultSystemPrompt
        }
    }

    private func save() {
        let prompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let cfg = AppConfig(
            provider: provider,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: effectiveModel,
            systemPrompt: prompt.isEmpty ? AppConfig.defaultSystemPrompt : prompt)
        cfg.save()
        model.reloadConfig()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onSaved() }
    }
}
