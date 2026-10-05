import AppKit
import Foundation
import Shell
import SwiftUI

@main
struct IdeSwiftApp: App {
    @State private var store = WorkspaceStore()
    @State private var editor = EditorController()

    var body: some Scene {
        WindowGroup {
            ShellView(store: store, editor: editor)
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1320, height: 860)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { IdeCommands(store: store, editor: editor) }
    }
}

struct IdeCommands: Commands {
    @Bindable var store: WorkspaceStore
    let editor: EditorController

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Abrir Arquivo…") { presentOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Reload do Workspace") { store.reload() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Salvar") { store.saveActive() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(store.activeDocument == nil)
            Button("Salvar Todos") { store.documents.forEach { store.save($0.id) } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!store.hasUnsavedChanges)
        }

        CommandGroup(after: .textEditing) {
            Button("Localizar…") { editor.showFindBar() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!editor.hasEditor)

            Button("Ir para Linha…") { presentGoToLine() }
                .keyboardShortcut("l", modifiers: .control)
                .disabled(!editor.hasEditor)

            Button("Comentar/Descomentar") { editor.toggleComment() }
                .keyboardShortcut("/", modifiers: .command)
                .disabled(!editor.hasEditor)

            Divider()

            Button(store.isSidebarVisible ? "Ocultar Sidebar" : "Mostrar Sidebar") {
                store.isSidebarVisible.toggle()
            }
            .keyboardShortcut("x", modifiers: [.command, .control])
        }

        CommandGroup(after: .toolbar) {
            Button(store.isSidebarVisible ? "Ocultar Sidebar" : "Mostrar Sidebar") {
                store.isSidebarVisible.toggle()
            }
            .keyboardShortcut("x", modifiers: [.command, .control])
        }

        CommandMenu("Build") {
            Button("Build") { store.startBuild() }
                .keyboardShortcut("b", modifiers: [.command, .control])
            Button(store.isRunning ? "Stop" : "Run") { store.toggleRunning() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.activeDocument == nil)
            Button("Parar") { store.stopRunning() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!store.isRunning)
        }
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = store.root
        if panel.runModal() == .OK {
            panel.urls.forEach { store.open($0) }
        }
    }

    private func presentGoToLine() {
        let alert = NSAlert()
        alert.messageText = "Ir para linha"
        alert.informativeText = "Número da linha (1–\(store.activeDocument?.lineCount ?? 0))"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.stringValue = "\(store.activeDocument?.selection.line ?? 1)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Ir")
        alert.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn, let line = Int(field.stringValue) else { return }
        editor.goToLine(line)
    }
}
