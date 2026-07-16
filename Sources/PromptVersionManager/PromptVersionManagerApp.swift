import SwiftUI
import PromptVersionCore

@main
struct PromptVersionManagerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 940, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建 Prompt") {
                    model.presentedSheet = .create
                }
                .keyboardShortcut("n")
            }
            CommandMenu("Prompt") {
                Button("保存新版本") {
                    model.presentedSheet = .newVersion
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.selectedPrompt == nil)

                Button("刷新") {
                    model.refresh()
                }
                .keyboardShortcut("r")
            }
        }
    }
}
