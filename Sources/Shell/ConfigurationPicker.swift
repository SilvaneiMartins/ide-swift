import AppKit
import DesignSystem
import SwiftUI

/// Seletor de configuração Debug/Release.
///
/// `NSPopUpButton` em vez de `Picker` do SwiftUI: só o AppKit dá o
/// `controlSize` pequeno e o bezel nativo que a barra unificada espera — um
/// `Picker` estilizado à mão não vira o mesmo componente.
struct ConfigurationPicker: NSViewRepresentable {
    @Binding var selection: WorkspaceStore.Configuration
    /// Largura mínima: "Release" sozinho já ocupa quase toda a largura
    /// natural, então sem um piso o pop-up fica com cara de botão estreito.
    var minimumWidth: CGFloat = ConfigurationPopUp.defaultMinimumWidth

    func makeNSView(context: Context) -> ConfigurationPopUp {
        let popUp = ConfigurationPopUp(frame: .zero)
        popUp.minimumWidth = minimumWidth
        popUp.onChange = { context.coordinator.selection = $0 }
        popUp.selection = selection
        return popUp
    }

    func updateNSView(_ popUp: ConfigurationPopUp, context: Context) {
        popUp.onChange = { context.coordinator.selection = $0 }
        popUp.selection = selection
        popUp.minimumWidth = minimumWidth
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    @MainActor
    final class Coordinator {
        @Binding var selection: WorkspaceStore.Configuration

        init(selection: Binding<WorkspaceStore.Configuration>) {
            self._selection = selection
        }
    }
}

/// O pop-up em si, sem SwiftUI. Separado do representable para poder ser
/// testado sem construir um `NSViewRepresentableContext`.
@MainActor
final class ConfigurationPopUp: NSPopUpButton {
    static let defaultMinimumWidth: CGFloat = 110

    var onChange: ((WorkspaceStore.Configuration) -> Void)?

    /// Só Debug e Release: nunca um dispositivo ou simulador (PLAN.md §1).
    static let configurations = WorkspaceStore.Configuration.allCases

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect, pullsDown: false)
        controlSize = .small
        font = EditorFont.mono(size: EditorFont.defaultSize)
        toolTip = "Configuração de build — apenas Debug e Release"
        removeAllItems()
        for configuration in Self.configurations {
            addItem(withTitle: configuration.rawValue)
        }
        target = self
        action = #selector(valueChanged)
        minimumWidth = Self.defaultMinimumWidth
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) não é suportado")
    }

    var selection: WorkspaceStore.Configuration {
        get { Self.configurations.indices.contains(indexOfSelectedItem) ? Self.configurations[indexOfSelectedItem] : .debug }
        set {
            let index = Self.configurations.firstIndex(of: newValue) ?? 0
            if indexOfSelectedItem != index { selectItem(at: index) }
        }
    }

    var minimumWidth: CGFloat = ConfigurationPopUp.defaultMinimumWidth {
        didSet { applyWidth(minimumWidth) }
    }

    @objc func valueChanged() {
        onChange?(selection)
    }

    private func applyWidth(_ width: CGFloat) {
        for constraint in constraints where constraint.firstAttribute == .width {
            constraint.constant = width
            return
        }
        widthAnchor.constraint(equalToConstant: width).isActive = true
    }
}
