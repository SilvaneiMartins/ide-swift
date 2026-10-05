import DesignSystem
import ProjectModel
import SwiftUI

/// Componente 1 de 4 — Sidebar. Árvore do pacote SwiftPM, arquivos
/// recentes e (a partir da Fase 2) estrutura de símbolos e busca.
///
/// A árvore vive dentro de uma `List(.sidebar)`: é a tree nativa do macOS,
/// com triângulo de expandir, seleção e material translúcido. Uma
/// `OutlineGroup` solta no `VStack` desenha o triângulo mas não responde ao
/// clique — e um `Button` marcado como `disabled` nas pastas mata o gesto de
/// expandir por completo.
struct SidebarView: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            if store.tree == nil {
                emptyState
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if !store.recentURLs.isEmpty {
                Divider()
                recents
            }
        }
        .background(Palette.sidebar)
    }

    /// Empty state: logo Swift + botão de importar, centralizado na vertical
    /// e na horizontal. Aparece quando nenhum projeto está aberto.
    private var emptyState: some View {
        VStack(spacing: Metrics.unit * 5) {
            Spacer()

            Image(systemName: "swift")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.swiftOrange)

            VStack(spacing: Metrics.unit * 2) {
                Text("Nenhum projeto aberto")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Importe uma pasta SwiftPM para começar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button {
                store.importProject()
            } label: {
                HStack(spacing: Metrics.unit * 2) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12))
                    Text("Importar Projeto")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, Metrics.unit * 5)
                .padding(.vertical, Metrics.unit * 2.5)
                .background(Palette.selection.opacity(0.15))
                .foregroundStyle(Palette.swiftOrange)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.controlCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.controlCornerRadius)
                        .strokeBorder(Palette.swiftOrange.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Só a árvore por enquanto. `Structure` e `Search` dependem do LSP
    /// (Fase 2/3) e tabs com placeholder só adicionariam chrome.
    private var content: some View {
        projectTree
    }

    private var projectTree: some View {
        List(selection: treeSelection) {
            if let tree = store.tree {
                OutlineGroup([tree], children: \.optionalChildren) { node in
                    if node.isDirectory {
                        // Sem tag: se a pasta entrasse na seleção, o realce
                        // pularia para ela e a linha do arquivo aberto perderia
                        // o destaque.
                        FileRow(node: node) {}
                    } else {
                        FileRow(node: node) { store.open(node.id) }
                            .tag(node.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 20)
    }

    private var treeSelection: Binding<Set<URL>> {
        Binding(
            get: { store.selectedDocumentID.map { [$0] } ?? [] },
            set: { newValue in
                if let url = newValue.first { store.open(url) }
            }
        )
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recentes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Limpar") { store.clearRecents() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Metrics.unit * 3)
            .padding(.vertical, Metrics.unit)

            ForEach(store.recentURLs, id: \.self) { url in
                Button {
                    store.open(url)
                } label: {
                    HStack(spacing: Metrics.unit * 2) {
                        Image(systemName: "clock")
                            .foregroundStyle(.tertiary)
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.unit * 3)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, Metrics.unit * 2)
    }
}

private struct FileRow: View {
    let node: FileNode
    let action: () -> Void

    var body: some View {
        if node.isDirectory {
            // Pasta: só o `OutlineGroup` cuida de expandir. Não pode virar
            // `Button` desabilitado, senão o triângulo deixa de responder.
            row(name: node.name, symbol: symbol, tint: Palette.swiftOrange)
        } else {
            Button(action: action) {
                row(name: node.name, symbol: symbol, tint: tint)
            }
            .buttonStyle(.plain)
        }
    }

    /// `Label` do SwiftUI usa a mesma fonte para ícone e texto, e o ícone
    /// sai do mesmo tamanho do texto. Como a fonte da row é pequena, o
    /// `Label` ficava com ícone grande demais em relação ao nome.
    private func row(name: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: Metrics.unit * 1.5) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var symbol: String {
        switch node.kind {
        case .directory: "folder"
        case .swiftFile: "swift"
        case .markdown: "doc.text"
        case .manifest: "shippingbox"
        case .other: "doc"
        }
    }

    private var tint: Color {
        switch node.kind {
        case .swiftFile, .manifest: Palette.swiftOrange
        case .directory, .markdown, .other: .secondary
        }
    }
}

private extension FileNode {
    /// `OutlineGroup` usa `nil` para "nó sem filhos", o que faz a tree colapsar.
    var optionalChildren: [FileNode]? {
        children.isEmpty ? nil : children
    }
}
