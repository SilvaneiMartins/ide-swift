import DesignSystem
import SwiftUI

/// Componente 2 de 4 — Header.
///
/// Liquid glass (macOS 26+): cada controle é uma cápsula de vidro com
/// `.glassEffect(.regular, in: .capsule)`, e os grupos ficam dentro de
/// `GlassEffectContainer`, que faz as cápsulas vizinhas fundirem as bordas
/// — o mesmo efeito do Finder e do Safari.
///
/// O `ConfigurationPicker` (NSPopUpButton) não recebe glass porque é
/// AppKit; substituído por um `Menu` SwiftUI com o mesmo efeito, mantendo
/// o comportamento nativo de menu.
///
/// Layout: Run/Stop/Build à esquerda, configuração + toggle da sidebar
/// à direita.
struct HeaderView: ToolbarContent {
    @Bindable var store: WorkspaceStore

    var body: some ToolbarContent {
        // MARK: - Ações de build/run
        ToolbarItem(placement: .navigation) {
            GlassEffectContainer(spacing: 2) {
                HStack(spacing: 0) {
                    capsuleButton(
                        symbol: "play.fill",
                        help: "Run (⌘R)",
                        enabled: store.activeDocument != nil
                    ) {
                        store.startRunning()
                    }

                    capsuleButton(
                        symbol: "stop.fill",
                        help: "Stop (⌘.)",
                        enabled: store.isRunning
                    ) {
                        store.stopRunning()
                    }

                    capsuleButton(
                        symbol: "hammer",
                        help: "Build (⌃⌘B)",
                        enabled: true
                    ) {
                        store.startBuild()
                    }
                }
            }
        }

        // MARK: - Configuração + sidebar (grupo direito)
        ToolbarItem(placement: .primaryAction) {
            GlassEffectContainer(spacing: 2) {
                HStack(spacing: 0) {
                    configurationMenu

                    capsuleButton(
                        symbol: store.isSidebarVisible ? "sidebar.left" : "sidebar.right",
                        help: "Mostrar/Ocultar Sidebar (⌃⌘X)",
                        enabled: true
                    ) {
                        store.isSidebarVisible.toggle()
                    }
                }
            }
        }
    }

    // MARK: - Controles

    private func capsuleButton(
        symbol: String,
        help: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 26)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .capsule)
        .disabled(!enabled)
        .help(help)
    }

    /// Menu Debug/Release em cápsula de vidro. `Menu` do SwiftUI mantém o
    /// comportamento nativo de popup (abrir, teclado, foco) sem precisar
    /// de `NSPopUpButton`.
    private var configurationMenu: some View {
        Menu {
            ForEach(WorkspaceStore.Configuration.allCases) { configuration in
                Button {
                    store.configuration = configuration
                } label: {
                    if store.configuration == configuration {
                        Label(configuration.rawValue, systemImage: "checkmark")
                    } else {
                        Text(configuration.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(store.configuration.rawValue)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
        .help("Configuração de build — apenas Debug e Release")
    }
}
