import DesignSystem
import SwiftUI

/// Componente 2 de 4 — Header.
///
/// Liquid glass (macOS 26+): os controles ficam dentro de um
/// `GlassEffectContainer`, que faz o material de vidro reagir aos vizinhos
/// — o efeito que o Finder e o Safari usam. Cada botão é SwiftUI com
/// `.buttonStyle(.glass)`, o estilo nativo do novo design system; não há
/// mais `NSButton` com `bezelStyle` aqui.
///
/// Layout: Run/Stop/Build agrupados à esquerda, configuração no centro,
/// toggle da sidebar à direita.
struct HeaderView: ToolbarContent {
    @Bindable var store: WorkspaceStore

    var body: some ToolbarContent {
        // MARK: - Ações de build/run (agrupadas em glass)
        ToolbarItem(placement: .navigation) {
            GlassEffectContainer(spacing: Metrics.unit) {
                HStack(spacing: 0) {
                    headerButton(
                        symbol: "play.fill",
                        help: "Run (⌘R)",
                        enabled: store.activeDocument != nil
                    ) {
                        store.startRunning()
                    }

                    headerButton(
                        symbol: "stop.fill",
                        help: "Stop (⌘.)",
                        enabled: store.isRunning
                    ) {
                        store.stopRunning()
                    }

                    headerButton(
                        symbol: "hammer",
                        help: "Build (⌃⌘B)",
                        enabled: true
                    ) {
                        store.startBuild()
                    }
                }
            }
        }

        // MARK: - Configuração Debug/Release
        ToolbarItem(placement: .automatic) {
            ConfigurationPicker(selection: $store.configuration)
        }

        // MARK: - Toggle da sidebar
        ToolbarItem(placement: .primaryAction) {
            GlassEffectContainer {
                headerButton(
                    symbol: store.isSidebarVisible ? "sidebar.left" : "sidebar.right",
                    help: "Mostrar/Ocultar Sidebar (⌃⌘X)",
                    enabled: true
                ) {
                    store.isSidebarVisible.toggle()
                }
            }
        }
    }

    private func headerButton(
        symbol: String,
        help: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.glass)
        .disabled(!enabled)
        .help(help)
    }
}
