import DesignSystem
import EditorCore
import SwiftUI

/// Componente 3 de 4 — Body. Abas de documentos, breadcrumb e o editor.
struct BodyView: View {
    @Bindable var store: WorkspaceStore
    let editor: EditorController

    var body: some View {
        VStack(spacing: 0) {
            if store.documents.isEmpty {
                emptyState
            } else {
                DocumentTabBar(store: store)
                Divider()
                if let document = store.activeDocument {
                    BreadcrumbBar(document: document)
                    Divider()
                    editor(for: document)
                } else {
                    emptyState
                }
            }
        }
        .background(Palette.background)
    }

    private func editor(for document: OpenDocument) -> some View {
        CodeEditorView(
            text: Binding(
                get: { document.buffer.text },
                set: { newValue in
                    guard newValue != document.buffer.text else { return }
                    document.buffer.setText(newValue)
                    document.isDirty = true
                }
            ),
            onSelectionChange: { position in
                document.selection = position
            },
            onContainerReady: { container in
                editor.attach(container)
            }
        )
    }

    private var emptyState: some View {
        VStack(spacing: Metrics.unit * 3) {
            Image(systemName: "swift")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nenhum arquivo aberto")
                .font(.headline)
            Text("Selecione um arquivo .swift na sidebar")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BreadcrumbBar: View {
    let document: OpenDocument

    var body: some View {
        HStack(spacing: Metrics.unit) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(document.displayPath)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            Text("\(document.buffer.lineCount) linhas")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, Metrics.unit * 3)
        .frame(height: Metrics.statusBarHeight)
        .background(Palette.background)
    }
}

private struct DocumentTabBar: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(store.documents, id: \.id) { document in
                    tab(for: document)
                }
            }
        }
        .frame(height: Metrics.statusBarHeight + 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func tab(for document: OpenDocument) -> some View {
        let isSelected = store.selectedDocumentID == document.id
        return HStack(spacing: Metrics.unit * 2) {
            Button {
                store.select(document.id)
            } label: {
                HStack(spacing: Metrics.unit) {
                    Text(document.displayName)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    if document.isDirty {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, Metrics.unit * 2)
                .frame(height: Metrics.statusBarHeight)
            }
            .buttonStyle(.plain)

            Button {
                store.close(document.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
            }
            .buttonStyle(.plain)
            .padding(.trailing, Metrics.unit * 2)
        }
        .frame(minWidth: 90)
        .background(isSelected ? Palette.selection : .clear)
    }
}
