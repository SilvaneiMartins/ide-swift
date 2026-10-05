import Foundation

/// Tipo de nó da árvore do workspace. Tudo que a IDE abre é um pacote SwiftPM;
/// nunca um `.xcodeproj` ou bundle de plataforma (ver PLAN.md §1).
public struct FileNode: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case directory
        case swiftFile
        case markdown
        case manifest
        case other
    }

    public let id: URL
    public let name: String
    public let kind: Kind
    public let children: [FileNode]

    public init(url: URL, kind: Kind, children: [FileNode] = []) {
        self.id = url
        self.name = url.lastPathComponent
        self.kind = kind
        self.children = children
    }

    public var isDirectory: Bool {
        if case .directory = kind { return true }
        return false
    }
}

/// Leitura da árvore de um pacote SwiftPM. Mostra tudo — inclusive
/// pastas ocultas como `.build`, `.swiftpm` e `.vscode` — como o VS Code.
/// A única exceção é `.git`: o VS Code também esconde o conteúdo dela por
/// padrão (`files.exclude`), e escanear `.git/objects` eager pode ser
/// milhares de nós numa repo ativa.
public enum WorkspaceScanner {
    public static let ignoredDirectories: Set<String> = [
        ".git",
    ]

    public static func scan(root: URL) -> FileNode {
        FileNode(url: root, kind: .directory, children: children(of: root))
    }

    private static func children(of directory: URL) -> [FileNode] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []

        return urls
            .filter { !ignoredDirectories.contains($0.lastPathComponent) }
            .sorted { lhs, rhs in
                let lhsIsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let rhsIsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if lhsIsDir != rhsIsDir { return lhsIsDir }
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .map { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    return FileNode(url: url, kind: .directory, children: children(of: url))
                }
                return FileNode(url: url, kind: kind(of: url))
            }
    }

    private static func kind(of url: URL) -> FileNode.Kind {
        if url.lastPathComponent == "Package.swift" { return .manifest }
        switch url.pathExtension {
        case "swift": return .swiftFile
        case "md": return .markdown
        default: return .other
        }
    }
}
