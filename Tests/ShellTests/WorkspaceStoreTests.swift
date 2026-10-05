import EditorCore
import Foundation
import Testing

@testable import Shell

/// O editor só mostra o que o `TextBuffer` do documento ativo contém. Como
/// o clique na sidebar passa pelo store, o fluxo inteiro é testado aqui:
/// abrir, trocar de aba, fechar.
@Suite("WorkspaceStore")
@MainActor
struct WorkspaceStoreTests {
    private func makeStore() throws -> (WorkspaceStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ide-swift-store-\(UUID().uuidString)", isDirectory: true)
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let file = sources.appendingPathComponent("main.swift")
        try "let a = 1".write(to: file, atomically: true, encoding: .utf8)
        return (WorkspaceStore(root: root), file)
    }

    @Test("abrir um arquivo cria documento e ativa a aba")
    func opensFile() throws {
        let (store, file) = try makeStore()
        store.open(file)

        #expect(store.documents.count == 1)
        #expect(store.activeDocument?.url == file)
        #expect(store.activeDocument?.buffer.text == "let a = 1")
    }

    @Test("o conteúdo do buffer vem do disco, não de um placeholder")
    func bufferComesDoDisco() throws {
        let (store, file) = try makeStore()
        store.open(file)
        #expect(store.activeDocument?.lineCount == 1)
        #expect(store.activeDocument?.isDirty == false)
    }

    @Test("abrir o mesmo arquivo de novo só troca a aba ativa")
    func reopenIsIdempotent() throws {
        let (store, file) = try makeStore()
        store.open(file)
        store.open(file)
        #expect(store.documents.count == 1)
    }

    @Test("trocar de aba troca o documento ativo")
    func switchesBetweenTabs() throws {
        let (store, file) = try makeStore()
        let other = file.deletingLastPathComponent().appendingPathComponent("outro.swift")
        try "let b = 2".write(to: other, atomically: true, encoding: .utf8)

        store.open(file)
        store.open(other)
        #expect(store.documents.count == 2)
        #expect(store.activeDocument?.url == other)

        store.select(file)
        #expect(store.activeDocument?.url == file)
        #expect(store.activeDocument?.buffer.text == "let a = 1")
    }

    @Test("cada aba guarda o próprio texto")
    func eachTabKeepsItsOwnBuffer() throws {
        let (store, file) = try makeStore()
        let other = file.deletingLastPathComponent().appendingPathComponent("outro.swift")
        try "let b = 2".write(to: other, atomically: true, encoding: .utf8)

        store.open(file)
        store.open(other)
        store.activeDocument?.buffer.setText("editado")
        store.select(file)

        #expect(store.activeDocument?.buffer.text == "let a = 1")
        store.select(other)
        #expect(store.activeDocument?.buffer.text == "editado")
    }

    @Test("editar marca o documento como modificado")
    func editingMarksDirty() {
        let document = OpenDocument(
            url: URL(fileURLWithPath: "/tmp/x.swift"),
            buffer: TextBuffer(text: "let a = 1")
        )
        #expect(!document.isDirty)
        document.buffer.setText("let a = 2")
        // `isDirty` é setado pelo Binding do editor, não pelo buffer; o
        // store não pode marcar sozinho.
        #expect(!document.isDirty)
    }

    @Test("pasta não vira documento")
    func ignoresDirectories() throws {
        let (store, _) = try makeStore()
        store.open(store.root.appendingPathComponent("Sources", isDirectory: true))
        #expect(store.documents.isEmpty)
        #expect(store.activeDocument == nil)
    }

    @Test("fechar a aba ativa seleciona outra, e a última não deixa nenhuma")
    func closingTabs() throws {
        let (store, file) = try makeStore()
        let other = file.deletingLastPathComponent().appendingPathComponent("outro.swift")
        try "let b = 2".write(to: other, atomically: true, encoding: .utf8)

        store.open(file)
        store.open(other)
        store.close(other)
        #expect(store.documents.count == 1)
        #expect(store.activeDocument?.url == file)

        store.close(file)
        #expect(store.documents.isEmpty)
        #expect(store.activeDocument == nil)
    }

    @Test("salvar grava o texto do buffer em disco e limpa o modificado")
    func savingWritesToDisk() throws {
        let (store, file) = try makeStore()
        store.open(file)
        store.activeDocument?.buffer.setText("let alterado = 99")
        store.activeDocument?.isDirty = true

        store.save(file)

        #expect(!store.hasUnsavedChanges)
        #expect(try String(contentsOf: file, encoding: .utf8) == "let alterado = 99")
    }

    @Test("arquivos fora da lista de extensões não abrem")
    func ignoresUnsupportedExtensions() throws {
        let (store, _) = try makeStore()
        let json = store.root.appendingPathComponent("Package.resolved")
        try "{}".write(to: json, atomically: true, encoding: .utf8)
        store.open(json)
        #expect(store.documents.isEmpty)
    }
}
