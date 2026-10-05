import DesignSystem
import ProjectModel
import SwiftUI

public struct ShellView: View {
    @Bindable var store: WorkspaceStore
    let editor: EditorController

    public init(store: WorkspaceStore, editor: EditorController) {
        self.store = store
        self.editor = editor
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(
                    min: Metrics.sidebarMinWidth,
                    ideal: Metrics.sidebarIdealWidth,
                    max: Metrics.sidebarMaxWidth
                )
        } detail: {
            BodyView(store: store, editor: editor)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    StatusBarView(store: store)
                }
        }
        .navigationTitle(store.activeDocument?.displayName ?? "ide-swift")
        .navigationSubtitle(store.activeDocument?.displayPath ?? store.root?.lastPathComponent ?? "")
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .toolbar { HeaderView(store: store) }
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { store.isSidebarVisible ? .all : .detailOnly },
            set: { store.isSidebarVisible = $0 != .detailOnly }
        )
    }
}
