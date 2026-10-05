import Foundation

/// Framing do LSP sobre stdio: cabeçalho `Content-Length` + corpo JSON.
///
/// O framing fica isolado de propósito: é a única parte do cliente que dá
/// para testar sem subir um servidor, e é onde vivem os bugs chatos de
/// buffer parcial e `\r\n` no meio do stream.
public enum MessageCodec {
    public enum CodecError: Error, Equatable {
        case missingContentLength
        case malformedContentLength(String)
        case truncatedBody(expected: Int, got: Int)
    }

    /// Serializa uma mensagem pronta para escrever no pipe.
    public static func encode(_ body: Data) -> Data {
        var out = Data()
        out.append(contentsOf: Array("Content-Length: \(body.count)\r\n\r\n".utf8))
        out.append(body)
        return out
    }

    /// Varre um buffer incremental e devolve as mensagens completas.
    ///
    /// Devolve o resto em `leftover` porque um `read` do pipe pode terminar
    /// no meio de um cabeçalho — tratar o pedaço como mensagem corromperia o
    /// stream inteiro.
    public static func decode(_ buffer: Data) throws -> (messages: [Data], leftover: Data) {
        var messages: [Data] = []
        var cursor = buffer.startIndex

        while true {
            guard let headerEnd = range(of: Data("\r\n\r\n".utf8), in: buffer, from: cursor) else {
                break
            }
            let headerData = buffer[cursor..<headerEnd.lowerBound]
            let length = try contentLength(from: headerData)
            let bodyStart = headerEnd.upperBound
            let bodyEnd = bodyStart + length
            guard bodyEnd <= buffer.endIndex else {
                break
            }
            messages.append(Data(buffer[bodyStart..<bodyEnd]))
            cursor = bodyEnd
        }

        return (messages, Data(buffer[cursor...]))
    }

    /// Procura o cabeçalho `Content-Length`. Os headers do LSP são
    /// case-insensitive e podem vir em qualquer ordem.
    static func contentLength(from headerData: Data) throws -> Int {
        guard let text = String(data: headerData, encoding: .utf8) else {
            throw CodecError.missingContentLength
        }
        for line in text.split(separator: "\r\n") {
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let name = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
            guard name == "content-length" else { continue }
            let value = pair[1].trimmingCharacters(in: .whitespaces)
            guard let length = Int(value) else {
                throw CodecError.malformedContentLength(String(value))
            }
            return length
        }
        throw CodecError.missingContentLength
    }

    private static func range(of pattern: Data, in buffer: Data, from start: Data.Index) -> Range<Data.Index>? {
        // Guarda antes de qualquer aritmética de índice: mover `endIndex`
        // para trás num buffer menor que o padrão estoura e mata o processo
        // com signal 5.
        guard !pattern.isEmpty, buffer.count >= pattern.count else { return nil }
        let limit = buffer.index(buffer.endIndex, offsetBy: -pattern.count)
        guard start <= limit else { return nil }
        return buffer.range(of: pattern, options: [], in: start..<buffer.index(limit, offsetBy: pattern.count))
    }
}
