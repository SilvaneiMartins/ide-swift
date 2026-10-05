import Foundation
import Testing

@testable import ProjectModel

@Suite("WorkspaceScanner")
struct WorkspaceScannerTests {
    @Test("mostra pastas ocultas como .build, mas ignora .git")
    func showsHiddenButIgnoresGit() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        try root.write("Sources/App/main.swift", contents: "print(1)")
        try root.write("Package.swift", contents: "// manifest")
        try root.write(".build/debug/binary.swift", contents: "noise")
        try root.write(".git/hook.swift", contents: "noise")

        let tree = WorkspaceScanner.scan(root: root.url)
        let topLevel = tree.children.map(\.name)

        #expect(topLevel.contains("Sources"))
        #expect(topLevel.contains("Package.swift"))
        #expect(topLevel.contains(".build"))
        #expect(!topLevel.contains(".git"))
    }

    @Test("classifica arquivos por extensão")
    func classifiesFiles() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        try root.write("Package.swift", contents: "")
        try root.write("README.md", contents: "")
        try root.write("data.json", contents: "")

        let tree = WorkspaceScanner.scan(root: root.url)
        let byName = Dictionary(uniqueKeysWithValues: tree.children.map { ($0.name, $0.kind) })

        #expect(byName["Package.swift"] == .manifest)
        #expect(byName["README.md"] == .markdown)
        #expect(byName["data.json"] == .other)
    }

    @Test("diretórios vêm antes de arquivos, ambos em ordem alfabética")
    func ordering() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        try root.write("z.swift", contents: "")
        try root.write("a.swift", contents: "")
        try root.makeDirectory("Zeta")
        try root.makeDirectory("Alpha")

        let tree = WorkspaceScanner.scan(root: root.url)
        #expect(tree.children.map(\.name) == ["Alpha", "Zeta", "a.swift", "z.swift"])
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ide-swift-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ relativePath: String, contents: String) throws {
        let destination = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: destination, atomically: true, encoding: .utf8)
    }

    func makeDirectory(_ relativePath: String) throws {
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent(relativePath),
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
