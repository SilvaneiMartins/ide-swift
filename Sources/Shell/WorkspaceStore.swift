import DesignSystem
import EditorCore
import Foundation
import ProjectModel
import Observation

/// Estado da sessão: workspace aberto, documentos abertos, seleção e estado
/// de build. `@MainActor` porque tudo que ele alimenta é SwiftUI.
@MainActor
@Observable
public final class WorkspaceStore {
    public enum BuildState: Equatable, Sendable {
        case idle
        case building
        case succeeded(duration: TimeInterval)
        case failed(errorCount: Int, duration: TimeInterval)

        public var label: String {
            switch self {
            case .idle: "Ready"
            case .building: "Building…"
            case .succeeded: "Build Succeeded"
            case .failed(let count, _): "\(count) Error\(count == 1 ? "" : "s")"
            }
        }
    }

    public enum Configuration: String, CaseIterable, Identifiable, Sendable {
        case debug = "Debug"
        case release = "Release"

        public var id: String { rawValue }
    }

    // Workspace
    public private(set) var root: URL
    public private(set) var tree: FileNode
    public var isSidebarVisible = true

    // Documentos
    public private(set) var documents: [OpenDocument] = []
    public private(set) var recentURLs: [URL] = []
    public var selectedDocumentID: URL?

    // Execução
    public var configuration: Configuration = .debug
    public private(set) var buildState: BuildState = .idle
    public private(set) var isRunning = false
    public private(set) var servicePort: Int?

    public init(root: URL? = nil) {
        let resolved = root ?? Self.defaultRoot()
        self.root = resolved
        self.tree = WorkspaceScanner.scan(root: resolved)
        self.recentURLs = RecentFilesStore.load()
    }

    /// Quando roda dentro de um `.app` via `open`, o diretório atual é `/` —
    /// varrer a raiz do filesystem seria travativo. Sem argumento explícito
    /// a IDE abre em `~/Projects`.
    private static func defaultRoot() -> URL {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--workspace"), index + 1 < arguments.count {
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        return FileManager.default.fileExists(atPath: projects.path) ? projects : home
    }

    public var activeDocument: OpenDocument? {
        guard let selectedDocumentID else { return nil }
        return documents.first { $0.id == selectedDocumentID }
    }

    // MARK: - Workspace

    public func reload() {
        tree = WorkspaceScanner.scan(root: root)
    }

    // MARK: - Documentos

    public func open(_ url: URL) {
        guard url.pathExtension == "swift" || url.pathExtension == "md" else { return }

        // Reabrir um arquivo já aberto só troca a aba ativa.
        if documents.contains(where: { $0.id == url }) {
            selectedDocumentID = url
            return
        }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let document = OpenDocument(url: url, buffer: TextBuffer(text: text))
        documents.append(document)
        selectedDocumentID = url
        recordRecent(url)
    }

    public func close(_ url: URL) {
        documents.removeAll { $0.id == url }
        if selectedDocumentID == url {
            selectedDocumentID = documents.last?.id
        }
    }

    public func closeAll() {
        documents.removeAll()
        selectedDocumentID = nil
    }

    public func select(_ url: URL) {
        selectedDocumentID = url
    }

    public func save(_ url: URL) {
        guard let document = documents.first(where: { $0.id == url }) else { return }
        do {
            try document.buffer.text.write(to: url, atomically: true, encoding: .utf8)
            document.isDirty = false
        } catch {
            document.saveError = error.localizedDescription
        }
    }

    public func saveActive() {
        guard let url = selectedDocumentID else { return }
        save(url)
    }

    public var hasUnsavedChanges: Bool {
        documents.contains { $0.isDirty }
    }

    private func recordRecent(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        recentURLs.insert(url, at: 0)
        if recentURLs.count > 10 { recentURLs.removeLast(recentURLs.count - 10) }
        RecentFilesStore.save(recentURLs)
    }

    public func clearRecents() {
        recentURLs = []
        RecentFilesStore.save(recentURLs)
    }

    // MARK: - Execução

    public func startBuild() { buildState = .building }
    public func finishBuild(errorCount: Int, duration: TimeInterval) {
        buildState = errorCount == 0
            ? .succeeded(duration: duration)
            : .failed(errorCount: errorCount, duration: duration)
    }
    public func startRunning() { isRunning = true }
    public func toggleRunning() { isRunning ? stopRunning() : startRunning() }
    public func stopRunning() { isRunning = false; servicePort = nil }
    public func noteServicePort(_ port: Int?) { servicePort = port }
}

/// Documento aberto. O `TextBuffer` é o source of truth do texto; a
/// `NSTextView` apenas reflete.
@MainActor
@Observable
public final class OpenDocument {
    public let url: URL
    public var buffer: TextBuffer
    public var isDirty = false
    public var saveError: String?
    public var selection = TextPosition(line: 1, column: 1)

    public init(url: URL, buffer: TextBuffer) {
        self.url = url
        self.buffer = buffer
    }

    public var id: URL { url }
    public var displayName: String { url.lastPathComponent }
    public var displayPath: String { url.deletingLastPathComponent().path }
    public var lineCount: Int { buffer.lineCount }
}

/// Arquivos recentes em JSON local. Nada de rede, nada de CoreData.
enum RecentFilesStore {
    private static var directory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ide-swift", isDirectory: true)
    }

    private static var fileURL: URL { directory.appendingPathComponent("recents.json") }

    static func load() -> [URL] {
        guard let data = try? Data(contentsOf: fileURL),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func save(_ urls: [URL]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(urls.map(\.path)) else { return }
        try? data.write(to: fileURL)
    }
}
