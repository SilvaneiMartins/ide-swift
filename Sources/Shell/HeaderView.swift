import DesignSystem
import SwiftUI

/// Componente 2 de 4 — Header.
///
/// Minimalista por decisão: só ícone, sem rótulo, sem moldura — é o que as
/// referências de design usam. A configuração fica no grupo `.navigation`
/// porque em `.principal` a janela unificada usa o slot para o título e o
/// item simplesmente não aparece.
struct HeaderView: ToolbarContent {
    @Bindable var store: WorkspaceStore

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            NativeToolbarButton(symbol: "play.fill", help: "Run (⌘R)") {
                store.startRunning()
            }
            .disabled(store.activeDocument == nil)

            NativeToolbarButton(symbol: "stop.fill", help: "Stop (⌘.)") {
                store.stopRunning()
            }
            .disabled(!store.isRunning)

            NativeToolbarButton(symbol: "hammer", help: "Build (⌃⌘B)") {
                store.startBuild()
            }
        }

        ToolbarItem(placement: .navigation) {
            ConfigurationPicker(selection: $store.configuration)
        }

        ToolbarItem(placement: .primaryAction) {
            NativeToolbarButton(symbol: "sidebar.left", help: "Mostrar/Ocultar Sidebar (⌃⌘X)") {
                store.isSidebarVisible.toggle()
            }
        }
    }
}
