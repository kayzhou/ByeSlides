import ByeSlidesCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("通用", systemImage: "gearshape") }
            EditorSettings()
                .tabItem { Label("编辑", systemImage: "pencil.line") }
            ReaderSettings()
                .tabItem { Label("阅读", systemImage: "book") }
            TypingSoundSettings()
                .tabItem { Label("键音", systemImage: "speaker.wave.2") }
            ShortcutSettings()
                .tabItem { Label("快捷键", systemImage: "keyboard") }
        }
        .frame(width: 540, height: 440)
        .padding(12)
        .tint(Color(nsColor: EditorStyle.emphasis))
    }
}

private struct GeneralSettings: View {
    @AppStorage(AppPreferences.launch.key) private var launch = AppPreferences.launch.defaultValue
    @AppStorage(AppPreferences.openingMode.key) private var openingMode = AppPreferences.openingMode.defaultValue
    @AppStorage(TypographySetting.pageMargin.key) private var pageMargin = TypographySetting.pageMargin.defaultValue

    var body: some View {
        Form {
            Section("启动与文稿") {
                Picker("直接启动时", selection: $launch) {
                    ForEach(LaunchAction.allCases) { Text($0.title).tag($0) }
                }
                Picker("打开文稿时的初始模式", selection: $openingMode) {
                    ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("每日文稿") {
                    Button("在 Finder 中显示") { revealDailyNotes() }
                }
            }
            Section("页面") {
                Stepper("正文两侧留白　\(pageMargin) pt", value: $pageMargin, in: TypographySetting.pageMargin.range, step: 4)
                    .monospacedDigit()
                Text("留白同时应用于编辑与阅读，正文宽度随窗口调整。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("恢复通用默认值") {
                launch = AppPreferences.launch.defaultValue
                openingMode = AppPreferences.openingMode.defaultValue
                pageMargin = TypographySetting.pageMargin.defaultValue
            }
        }
        .formStyle(.grouped)
    }

    private func revealDailyNotes() {
        let folder = ByeSlidesAppDelegate.dailyNotesFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        } catch {
            NSApp.presentError(error)
        }
    }
}

private struct EditorSettings: View {
    @AppStorage(TypographySetting.editorFontSize.key) private var size = TypographySetting.editorFontSize.defaultValue
    @AppStorage(TypographySetting.editorLineSpacing.key) private var spacing = TypographySetting.editorLineSpacing.defaultValue
    @AppStorage(AppPreferences.highlightLine.key) private var highlightLine = AppPreferences.highlightLine.defaultValue
    @AppStorage(AppPreferences.showWordCount.key) private var showWordCount = AppPreferences.showWordCount.defaultValue
    @AppStorage(AppPreferences.continueLists.key) private var continueLists = AppPreferences.continueLists.defaultValue

    var body: some View {
        Form {
            Section("排版") {
                FontSizeStepper(size: $size, setting: TypographySetting.editorFontSize, unit: "pt")
                LineSpacingStepper(spacing: $spacing, setting: TypographySetting.editorLineSpacing)
            }
            Section("写作") {
                Toggle("用浅蓝色高亮光标所在行", isOn: $highlightLine)
                Toggle("显示底部字数", isOn: $showWordCount)
                Toggle("按回车时续写 Markdown 列表", isOn: $continueLists)
            }
            Button("恢复编辑默认值") {
                size = TypographySetting.editorFontSize.defaultValue
                spacing = TypographySetting.editorLineSpacing.defaultValue
                highlightLine = AppPreferences.highlightLine.defaultValue
                showWordCount = AppPreferences.showWordCount.defaultValue
                continueLists = AppPreferences.continueLists.defaultValue
            }
        }
        .formStyle(.grouped)
    }
}

private struct ReaderSettings: View {
    @AppStorage(TypographySetting.readerFontSize.key) private var size = TypographySetting.readerFontSize.defaultValue
    @AppStorage(TypographySetting.readerLineSpacing.key) private var spacing = TypographySetting.readerLineSpacing.defaultValue
    @AppStorage(AppPreferences.readerJustifies.key) private var justifies = AppPreferences.readerJustifies.defaultValue
    @AppStorage(AppPreferences.readerSpacedScripts.key) private var spacedScripts = AppPreferences.readerSpacedScripts.defaultValue
    @AppStorage(AppPreferences.readerHangingPunctuation.key) private var hangingPunctuation = AppPreferences.readerHangingPunctuation.defaultValue
    @AppStorage(AppPreferences.remoteImages.key) private var remoteImages = AppPreferences.remoteImages.defaultValue

    var body: some View {
        Form {
            Section("排版") {
                FontSizeStepper(size: $size, setting: TypographySetting.readerFontSize, unit: "px")
                LineSpacingStepper(spacing: $spacing, setting: TypographySetting.readerLineSpacing)
                Toggle("段落两端对齐", isOn: $justifies)
                Toggle("在中英文之间自动留空", isOn: $spacedScripts)
                Toggle("允许行末标点悬挂", isOn: $hangingPunctuation)
            }
            Section("图片") {
                Picker("远程图片", selection: $remoteImages) {
                    ForEach(RemoteImagePolicy.allCases) { Text($0.title).tag($0) }
                }
                Text("自动载入会在打开阅读模式时连接图片服务器。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("恢复阅读默认值") {
                size = TypographySetting.readerFontSize.defaultValue
                spacing = TypographySetting.readerLineSpacing.defaultValue
                justifies = AppPreferences.readerJustifies.defaultValue
                spacedScripts = AppPreferences.readerSpacedScripts.defaultValue
                hangingPunctuation = AppPreferences.readerHangingPunctuation.defaultValue
                remoteImages = AppPreferences.remoteImages.defaultValue
            }
        }
        .formStyle(.grouped)
    }
}

private struct TypingSoundSettings: View {
    @AppStorage(AppPreferences.typingSound.key) private var enabled = AppPreferences.typingSound.defaultValue
    @AppStorage(AppPreferences.typingTone.key) private var tone = AppPreferences.typingTone.defaultValue
    @AppStorage(AppPreferences.typingVolume.key) private var volume = AppPreferences.typingVolume.defaultValue

    var body: some View {
        Form {
            Section("机械键盘音") {
                Toggle("编辑时播放键音", isOn: $enabled)
                Picker("音色", selection: $tone) {
                    ForEach(TypingTone.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(tone.description).font(.callout).foregroundStyle(.secondary)
                LabeledContent("音量") {
                    Slider(value: $volume, in: 0...1, step: 0.05) { Text("键音音量") }
                        .labelsHidden()
                    Text(volume.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                Button {
                    Task { await TypingSound.shared.preview(tone, volume: volume) }
                } label: {
                    Label("试听键音", systemImage: "play.circle")
                }
                .disabled(volume <= 0)
            }
            Button("恢复键音默认值") {
                enabled = AppPreferences.typingSound.defaultValue
                tone = AppPreferences.typingTone.defaultValue
                volume = AppPreferences.typingVolume.defaultValue
            }
        }
        .formStyle(.grouped)
        .onChange(of: tone, stopPreview)
        .onChange(of: volume, stopPreview)
        .onDisappear(perform: stopPreview)
    }

    private func stopPreview() {
        Task { await TypingSound.shared.stopPreview() }
    }
}

private struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section("文稿") {
                LabeledContent("新建", value: "⌘N")
                LabeledContent("打开", value: "⌘O")
                LabeledContent("存储", value: "⌘S")
                LabeledContent("打印", value: "⌘P")
            }
            Section("编辑与阅读") {
                LabeledContent("编辑模式", value: "⌘1")
                LabeledContent("阅读模式", value: "⌘2")
                LabeledContent("放大 / 缩小显示", value: "⌘= / ⌘-")
                LabeledContent("恢复默认大小", value: "⌘0")
                LabeledContent("查找", value: "⌘F")
                LabeledContent("查找与替换", value: "⌥⌘F")
                LabeledContent("粗体 / 斜体 / 链接", value: "⌘B / ⌘I / ⌘K")
                LabeledContent("列表缩进 / 减少缩进", value: "Tab / ⇧Tab")
            }
            Section("应用") {
                LabeledContent("设置", value: "⌘,")
            }
        }
        .monospacedDigit()
        .formStyle(.grouped)
    }
}

private struct FontSizeStepper: View {
    @Binding var size: Int
    let setting: TypographySetting
    let unit: String

    var body: some View {
        Stepper("字号　\(size) \(unit)", value: $size, in: setting.range)
            .monospacedDigit()
    }
}

private struct LineSpacingStepper: View {
    @Binding var spacing: Int
    let setting: TypographySetting

    var body: some View {
        Stepper(value: $spacing, in: setting.range) {
            Text("行距　\(Double(spacing) / 10, specifier: "%.1f") 倍")
        }
        .monospacedDigit()
    }
}
