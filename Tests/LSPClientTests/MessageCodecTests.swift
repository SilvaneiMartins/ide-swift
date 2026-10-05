import Foundation
import Testing

@testable import LSPClient

@Suite("MessageCodec")
struct MessageCodecTests {
    private func framed(_ json: String) -> Data {
        MessageCodec.encode(Data(json.utf8))
    }

    @Test("encode escreve Content-Length em bytes, não em caracteres")
    func encodesByteLength() {
        // "ó" tem 2 unidades UTF-8: contar caracteres daria 1 a menos.
        let body = Data("{\"t\":\"ó\"}".utf8)
        let encoded = MessageCodec.encode(body)
        let header = String(data: encoded.prefix(while: { $0 != 0x0D }), encoding: .utf8) ?? ""
        #expect(header == "Content-Length: \(body.count)")
    }

    @Test("decode recupera exatamente o que foi encodes")
    func roundTrip() {
        let original = framed("{\"jsonrpc\":\"2.0\",\"id\":1}")
        let (messages, leftover) = try! MessageCodec.decode(original)
        #expect(messages.count == 1)
        #expect(messages[0] == Data("{\"jsonrpc\":\"2.0\",\"id\":1}".utf8))
        #expect(leftover.isEmpty)
    }

    @Test("várias mensagens no mesmo buffer saem todas")
    func decodesBatchedMessages() {
        var buffer = Data()
        buffer.append(framed("{\"id\":1}"))
        buffer.append(framed("{\"id\":2}"))
        buffer.append(framed("{\"id\":3}"))

        let (messages, leftover) = try! MessageCodec.decode(buffer)
        #expect(messages.count == 3)
        #expect(leftover.isEmpty)
    }

    @Test("buffer parcial não vira mensagem: devolve como leftover")
    func keepsPartialBufferAsLeftover() {
        var buffer = framed("{\"id\":1}")
        buffer.append(contentsOf: Array("Content-Len".utf8))

        let (messages, leftover) = try! MessageCodec.decode(buffer)
        #expect(messages.count == 1)
        #expect(String(data: leftover, encoding: .utf8) == "Content-Len")
    }

    @Test("cabeçalho completo mas corpo incompleto espera mais bytes")
    func waitsForCompleteBody() {
        let body = Data("{\"id\":42}".utf8)
        var buffer = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        buffer.append(contentsOf: body.prefix(4))

        let (messages, leftover) = try! MessageCodec.decode(buffer)
        #expect(messages.isEmpty)
        #expect(leftover == buffer)
    }

    @Test("byte a byte chega na mensagem completa")
    func reassemblesByteByByte() {
        let wire = framed("{\"jsonrpc\":\"2.0\",\"method\":\"initialized\"}")
        var collected: [Data] = []
        var buffer = Data()

        for byte in wire {
            buffer.append(byte)
            let (messages, leftover) = try! MessageCodec.decode(buffer)
            collected.append(contentsOf: messages)
            buffer = leftover
        }

        #expect(collected.count == 1)
        #expect(String(data: collected[0], encoding: .utf8) == "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\"}")
    }

    @Test("Content-Length é case-insensitive")
    func headerNameIsCaseInsensitive() {
        let body = Data("{}".utf8)
        let buffer = Data("CONTENT-LENGTH: \(body.count)\r\n\r\n".utf8) + body
        let (messages, _) = try! MessageCodec.decode(buffer)
        #expect(messages.count == 1)
    }

    @Test("outros headers não atrapalham")
    func ignoresOtherHeaders() {
        let body = Data("{\"id\":1}".utf8)
        let buffer = Data("Content-Type: application/vscode-jsonrpc; charset=utf-8\r\nContent-Length: \(body.count)\r\n\r\n".utf8) + body
        let (messages, _) = try! MessageCodec.decode(buffer)
        #expect(messages.count == 1)
    }

    @Test("cabeçalho sem Content-Length é erro explícito")
    func missingContentLengthThrows() {
        #expect(throws: MessageCodec.CodecError.missingContentLength) {
            try MessageCodec.contentLength(from: Data("Content-Type: x\r\n".utf8))
        }
    }

    @Test("Content-Length não numérico é erro explícito")
    func malformedContentLengthThrows() {
        #expect(throws: MessageCodec.CodecError.malformedContentLength("banana")) {
            try MessageCodec.contentLength(from: Data("Content-Length: banana\r\n".utf8))
        }
    }

    @Test("corpo com JSON malformado ainda sai como Data — quem valida é o parser")
    func doesNotValidateJSON() {
        let body = Data("{não é json".utf8)
        let (messages, _) = try! MessageCodec.decode(framed("{não é json"))
        #expect(messages == [body])
    }
}
