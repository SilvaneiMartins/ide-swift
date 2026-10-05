import DesignSystem
import SwiftUI

/// Componente 4 de 4 — StatusBar. Posição do cursor, configuração, estado
/// do build, do LSP e a porta do serviço em execução.
struct StatusBarView: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        HStack(spacing: Metrics.unit * 3) {
            cursorIndicator
            Divider().frame(height: 12)
            Text("Swift")
            Text(store.configuration.rawValue)
            if store.hasUnsavedChanges {
                Label("Modificado", systemImage: "pencil")
            }
            Spacer()
            buildIndicator
            Divider().frame(height: 12)
            lspIndicator
            if let port = store.servicePort {
                Divider().frame(height: 12)
                Label("localhost:\(port)", systemImage: "network")
            }
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

    private var lspIndicator: some View {
        Label("LSP: Fase 2", systemImage: "bolt.horizontal.circle")
            .foregroundStyle(.tertiary)
    }
}
