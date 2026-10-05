import Foundation

/// Identificador de requisição.
///
/// É tipado e opaco de propósito: o `cancelRequest` precisa mirar a
/// requisição certa, e misturar um id de notificação com um de requisição é
/// bug silencioso no LSP.
public struct RequestID: Hashable, Sendable, Codable {
    private let rawValue: Int

    public init(_ value: Int) {
        rawValue = value
    }

    public static func next(_ counter: inout Int) -> RequestID {
        counter += 1
        return RequestID(counter)
    }

    public var value: Int { rawValue }
}

/// Posição no documento. `line` e `character` são 0-based e `character` é
/// um índice **UTF-16** — a mesma convenção do `TextBuffer`, então a
/// conversão é direta e sem passar por `String.Index`.
public struct LSPPosition: Hashable, Sendable, Codable {
    public var line: Int
    public var character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

public struct LSPRange: Hashable, Sendable, Codable {
    public var start: LSPPosition
    public var end: LSPPosition

    public init(start: LSPPosition, end: LSPPosition) {
        self.start = start
        self.end = end
    }

    public init(line: Int, startCharacter: Int, endCharacter: Int) {
        self.init(
            start: LSPPosition(line: line, character: startCharacter),
            end: LSPPosition(line: line, character: endCharacter)
        )
    }
}

/// Severidade do LSP: 1 = erro, 2 = warning, 3 = info, 4 = hint.
public enum DiagnosticSeverity: Int, Hashable, Sendable, Codable {
    case error = 1
    case warning = 2
    case information = 3
    case hint = 4
}

public struct Diagnostic: Hashable, Sendable, Codable {
    public var range: LSPRange
    public var severity: DiagnosticSeverity?
    public var message: String
    public var source: String?

    public init(range: LSPRange, severity: DiagnosticSeverity?, message: String, source: String? = nil) {
        self.range = range
        self.severity = severity
        self.message = message
        self.source = source
    }
}

/// Documento que o servidor "conhece". Só entra depois de um `didOpen` bem
/// succeeding: mandar `didChange` para um URI desconhecido é erro de
/// protocolo e o servidor desconecta.
public struct OpenedDocument: Sendable, Equatable {
    public var uri: URL
    /// `textDocument/sync`, sempre 2: só com sync incremental o servidor
    /// reaproveita a parse em vez de reparsear o arquivo a cada tecla.
    public var version: Int
    public var languageID: String
    public var text: String

    public init(uri: URL, version: Int = 1, languageID: String = "swift", text: String = "") {
        self.uri = uri
        self.version = version
        self.languageID = languageID
        self.text = text
    }
}

/// URL de arquivo no formato que o LSP espera.
public enum FileURI {
    public static func encode(_ url: URL) -> String {
        url.absoluteString
    }

    public static func decode(_ uri: String) -> URL? {
        URL(string: uri)
    }
}
