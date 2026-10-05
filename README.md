# ide-swift

IDE nativa em Swift para escrever, compilar e executar **aplicações macOS e APIs/serviços em Swift**. Escrita em Swift 6.4, rodando apenas em macOS 26+.

## Estado do projeto

**Fases 0 e 1 concluídas. Fase 2 (LSP) em andamento.**

### Já funciona

- Abas de documento com indicador de modificado e salvar
- Arquivos recentes persistidos em JSON
- Gutter com números de linha desenhado à mão
- Realce sintático via `swift-syntax` (parse fora da main thread, repinta só as linhas alteradas)
- Undo coalescido por rajada de digitação
- Go to Line (⌃L), Find nativa (⌘F), Comentar/Descomentar (⌘/)
- Tree do workspace com pastas expansíveis
- Sidebar translúcida com material `.ultraThinMaterial`
- Header minimalista com botões de ícone sem moldura
- StatusBar com linha/coluna, linguagem, configuração e estado do build

### Em desenvolvimento (Fase 2 — LSP)

- `LSPClient/MessageCodec.swift` — framing `Content-Length` do LSP sobre stdio
- `LSPClient/LSPTypes.swift` — tipos compartilhados (posições UTF-16, diagnósticos, documentos abertos)
- Próximo: `SourceKitLSPServer` — actor que faz spawn de `sourcekit-lsp`, gerencia JSON-RPC e cancelamento de requisições

### Ainda não funciona

- LSP: sem completion, sem diagnósticos, sem ir-para-definição
- `swift build` / `swift run` reais — os botões do Header só mudam estado
- Terminal embutido (PTY)
- Integração Git
- Command Palette

## Requisitos

- macOS 26+
- Xcode 27.0+ (Swift 6.4)
- `sourcekit-lsp` e `swift-format` resolvidos via `xcrun --find` (não precisam estar no PATH)

## Comandos

```bash
swift build                          # compila sem warning
swift test                           # roda todos os testes (Swift Testing)
swift test --filter MessageCodecTests # filtra por suíte
scripts/make-app.sh [debug|release]  # gera dist/ide-swift.app
scripts/run.sh [workspace]           # build + open do .app
```

## Arquitetura

```
Sources/
├── ide-swiftApp/          # @main: App, Scene, WindowGroup, Commands
├── DesignSystem/          # tokens (cores, tipografia, espaçamento), wrappers SwiftUI
├── Shell/                 # Sidebar, Header, Body, StatusBar + WorkspaceStore
├── EditorCore/            # NSTextView host, TextBuffer, gutter, SyntaxTheme
├── SyntaxHighlight/       # parser swift-syntax → tokens coloridos
├── LSPClient/             # framing JSON-RPC, tipos LSP, SourceKitLSPServer (em breve)
└── ProjectModel/          # workspace, árvore de arquivos, Package.swift parsing
```

### Decisões técnicas

| Item | Decisão |
|---|---|
| Build da IDE | SwiftPM + script de empacotamento `.app` |
| UI | SwiftUI para chrome, AppKit (`NSTextView`) para o editor |
| Engine de linguagem | SourceKit-LSP via `xcrun --find sourcekit-lsp` |
| Concorrência | Swift 6 strict concurrency; UI em `@MainActor`, LSP em `actor` |
| Source of truth do texto | `TextBuffer` (UTF-16), não o `NSTextView` |
| IntelliSense | SourceKit-LSP — sem parser/indexador próprios |

### Princípios de design

- **Nativo antes de customizado** — cores semânticas, SF Symbols, materiais `.ultraThinMaterial`
- **Minimalista, não um clone do Xcode** — controles só com ícone, barras finas, muito espaço para o código
- **4 componentes fixos** — Sidebar, Header, Body, StatusBar
- **Latência é requisito funcional** — loop de digitação com orçamento de 16 ms

## Escopo

- **Dentro:** apps macOS (SwiftUI/AppKit), APIs/serviços em Swift (Vapor, Hummingbird), bibliotecas SwiftPM
- **Fora:** iOS/mobile, jogos, distribuição App Store, rede em runtime, Docker/K8s

## Arquivos relevantes

### Documentação
- [PLAN.md](PLAN.md) — plano completo por fases, decisões técnicas, roadmap
- [AGENTS.md](AGENTS.md) — regras para o agente, gotchas de macOS/AppKit, critérios de pronto

### Código-fonte
- [Sources/ide-swiftApp/IdeSwiftApp.swift](Sources/ide-swiftApp/IdeSwiftApp.swift) — entry point da app
- [Sources/Shell/ShellView.swift](Sources/ShellView.swift) — layout dos 4 componentes
- [Sources/Shell/WorkspaceStore.swift](Sources/Shell/WorkspaceStore.swift) — estado central da sessão
- [Sources/EditorCore/CodeEditorView.swift](Sources/EditorCore/CodeEditorView.swift) — NSTextView + gutter
- [Sources/EditorCore/TextBuffer.swift](Sources/EditorCore/TextBuffer.swift) — source of truth do texto
- [Sources/LSPClient/MessageCodec.swift](Sources/LSPClient/MessageCodec.swift) — framing JSON-RPC
- [Sources/LSPClient/LSPTypes.swift](Sources/LSPClient/LSPTypes.swift) — tipos compartilhados LSP

### Testes
- [Tests/LSPClientTests/MessageCodecTests.swift](Tests/LSPClientTests/MessageCodecTests.swift) — 11 testes do framing
- [Tests/EditorCoreTests/](Tests/EditorCoreTests/) — testes do editor e TextBuffer
- [Tests/ShellTests/](Tests/ShellTests/) — testes do WorkspaceStore

### Scripts
- [scripts/make-app.sh](scripts/make-app.sh) — gera o `.app` em `dist/`
- [scripts/run.sh](scripts/run.sh) — build + open do `.app`
