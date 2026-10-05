import DesignSystem
import SwiftUI

/// Componente 4 de 4 — StatusBar. Nome do projeto e posição do cursor à
/// esquerda; erros, LSP e estado do build à direita.
struct StatusBarView: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        HStack(spacing: Metrics.unit * 3) {
            // MARK: - Esquerda
            Text(store.root?.lastPathComponent ?? "ide-swift")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)

            if store.activeDocument != nil {
                Divider().frame(height: 12)
                cursorIndicator
            }

            Spacer()

            // MARK: - Direita
            errorIndicator
            Divider().frame(height: 12)
            lspIndicator
            Divider().frame(height: 12)
            buildIndicator
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Metrics.unit * 3)
        .frame(height: Metrics.statusBarHeight)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var cursorIndicator: some View {
        let selection = store.activeDocument?.selection
        return Text(selection.map { "Ln \($0.line), Col \($0.column)" } ?? "Ln 1, Col 1")
            .monospacedDigit()
    }

    /// Contagem de erros do último build. Sem LSP ainda (Fase 2), a fonte
    /// é o `buildState` — quando os diagnósticos chegarem, passa a ler do
    /// store também.
    private var errorIndicator: some View {
        HStack(spacing: Metrics.unit) {
            if case .failed(let count, _) = store.buildState, count > 0 {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("\(count)")
            } else {
                Image(systemName: "xmark.circle")
                Text("0")
            }
        }
        .monospacedDigit()
    }

    private var lspIndicator: some View {
        Label("LSP", systemImage: "bolt.horizontal.circle")
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private var buildIndicator: some View {
        switch store.buildState {
        case .idle:
            Label("Ready", systemImage: "circle.dashed")
        case .building:
            ProgressView().controlSize(.small)
            Text(store.buildState.label)
        case .succeeded(let duration):
            Label(
                "\(store.buildState.label) · \(duration.formatted(.number.precision(.fractionLength(1))))s",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        case .failed(let count, _):
            Label("\(count) erro\(count == 1 ? "" : "s")", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }
}
