import AppKit
import Testing

@testable import Shell

@Suite("ConfigurationPopUp")
@MainActor
struct ConfigurationPopUpTests {
    @Test("lista exatamente Debug e Release — nunca dispositivo ou simulador")
    func listsOnlyDebugAndRelease() {
        let popUp = ConfigurationPopUp(frame: .zero)
        #expect(popUp.numberOfItems == 2)
        #expect(popUp.itemTitles == ["Debug", "Release"])
    }

    @Test("a seleção reflete o estado inicial")
    func reflectsInitialSelection() {
        let popUp = ConfigurationPopUp(frame: .zero)
        popUp.selection = .release
        #expect(popUp.indexOfSelectedItem == 1)
        #expect(popUp.selection == .release)
    }

    @Test("escolher um item dispara o callback com a configuração nova")
    func firesCallback() {
        let popUp = ConfigurationPopUp(frame: .zero)
        var received: WorkspaceStore.Configuration?
        popUp.onChange = { received = $0 }

        popUp.selectItem(at: 1)  // selectItem(at:) do AppKit
        popUp.valueChanged()

        #expect(received == .release)
    }

    @Test("atualizar a seleção pelo lado de fora não dispara callback")
    func externalUpdateDoesNotFire() {
        let popUp = ConfigurationPopUp(frame: .zero)
        var fired = false
        popUp.onChange = { _ in fired = true }

        popUp.selection = .release

        #expect(!fired)
        #expect(popUp.indexOfSelectedItem == 1)
    }

    @Test("o piso de largura é aplicado uma vez só")
    func appliesWidthOnce() {
        let popUp = ConfigurationPopUp(frame: .zero)
        popUp.minimumWidth = 140
        popUp.minimumWidth = 140

        let widths = popUp.constraints.filter { $0.firstAttribute == .width }
        #expect(widths.count == 1)
        #expect(widths.first?.constant == 140)
    }

    @Test("seleção inválida cai em Debug em vez de quebrar")
    func invalidIndexFallsBack() {
        let popUp = ConfigurationPopUp(frame: .zero)
        popUp.select(nil)
        #expect(popUp.selection == .debug)
    }
}
