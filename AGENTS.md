# AGENTS.md

ide-swift = IDE para escrever/compilar/executar apps macOS **e APIs** em Swift, escrita **em Swift**, rodando **só em macOS**.

## Estado atual
**Fases 0 e 1 concluídas. Fase 2 (LSPClient) ainda não começou.** Módulos: `DesignSystem`, `EditorCore`, `SyntaxHighlight`, `ProjectModel`, `Shell` e o executável `ide-swiftApp`. Testes com **Swift Testing** (`import Testing`, `@Suite`, `@Test`) — não XCTest.

Já funciona: abas de documento, dirty + salvar, recentes em JSON, gutter com números de linha, realce sintático via swift-syntax (parse fora da main thread, repinta só as linhas que mudaram), undo coalescido por rajada, ⌃L Go to Line, ⌘F find bar nativa, ⌘/ comentar/descomentar.

**Não** funciona ainda: LSP (sem completion, sem diagnóstico, sem ir-para-definição), `swift build`/run de verdade — os botões do Header só mudam estado. Não os descreva como funcionais.

## Ambiente (verificado em 26-09-2026)
- macOS 27.0, Xcode 27.0, Swift 6.4, `xcode-select -p` → `/Applications/Xcode.app/Contents/Developer`
- Swift 6 com strict concurrency: código que toca UI é `@MainActor`; o cliente LSP é um `actor`, não uma classe com `DispatchQueue`.
- `sourcekit-lsp` e `swift-format` **não** estão no PATH. Resolver sempre via `xcrun --find sourcekit-lsp`. Nunca chame direto pelo nome — quebra quando o Xcode default muda.

## Escopo fechado (decidido com o usuário — não reabrir)
- **Só macOS.** Nenhum target iOS/iPadOS/watchOS/tvOS/visionOS, nenhum simulador, nenhum device support. Se aparecer `UIKit`, `UIDevice`, `SpriteKit`, `Metal` ou `xcodebuild` no código, é bug.
- **Sem jogos, sem mobile.** Nada de engine, cena, profiler gráfico.
- **Só SwiftPM.** Sem `.xcodeproj`, sem `xcodebuild`, sem schemes de simulador. Build do usuário = `swift build` / `swift run` / `swift test`.
- **Distribuição apenas local.** Sem App Store, sem Developer ID, sem notarização, sem entitlements de sandbox.
- **Foco do produto:** escrever apps macOS (SwiftUI/AppKit) **e** APIs/serviços em Swift (Vapor, Hummingbird, `swift-service-lifecycle`), além de bibliotecas SwiftPM.
- **Sem rede em runtime**, sem contas, sem telemetria, sem Docker/K8s.

O destino no Header é sempre **target executável + Debug/Release**, nunca um dispositivo ou simulador.

## Regras que o agente não deve violar
- **Nenhuma dependência de rede em runtime.** O binário da IDE não baixa nada; tudo vem do toolchain local.
- **IntelliSense = SourceKit-LSP.** Não escreva parser, índice de símbolos ou tokenizer próprios. Se faltar algo, verifique se é uma capability do LSP antes de implementar. O único parser próprio aceito é o de *coloração* (`SyntaxHighlight`), que roda offline e separado do LSP.
- **UI minimalista, não uma réplica do Xcode.** Controles de toolbar só com ícone e sem moldura (`NativeToolbarButton` com `style: .plain`), barras finíssimas, muito espaço para o código. Não copie o chrome do Xcode; as referências de design estão em `IMG_5969.pdf` e `IMG_5970.pdf` na raiz do repo.
- **Cores apenas semânticas** (`.labelColor`, `.selectedContentBackgroundColor`, `NSColor.controlBackgroundColor`), ícones apenas SF Symbols, materiais `.ultraThinMaterial`. Proibido `Color(hex:)`, CSS, HTML ou WebView no editor. Única exceção: `Palette.swiftOrange`, nos ícones de pasta e de arquivo `.swift`.
- **Os 4 componentes são fixos:** Sidebar, Header, Body, StatusBar. Mudança de layout entra no `PLAN.md` primeiro.
- **Tree do workspace dentro de `List(.sidebar)`.** `OutlineGroup` solto num `VStack` desenha o triângulo mas não responde ao clique, e `Button(...).disabled(true)` em pasta mata o expandir. Pasta é `Label` puro; só arquivo vira `Button` e recebe `.tag`.
- **`NSTextView` só dentro de `NSViewRepresentable`.** SwiftUI não tem editor de texto nativo; não tente substituir.
- **Source of truth do texto é `TextBuffer`**, não o `NSTextView`. Features leem/escrevem no buffer e o texto reflete. Offsets externos são sempre **UTF-16** — é o que o LSP usa; `TextBuffer` faz a conversão para `String.Index`.
- **Requests de LSP são canceláveis.** Antes de emitir uma requisição nova do mesmo arquivo, mande `cancelRequest` da anterior; completion nunca pode bloquear a digitação.

## Onde mexer por feature
- Realce / cores: `SyntaxHighlight/` (parse) e `SyntaxTheme` em `EditorCore` (cor → NSColor)
- Editor, gutter, comandos de edição: `EditorCore/CodeEditorView.swift` e `LineNumberGutterView.swift`
- Abas, recentes, sessão: `Shell/WorkspaceStore.swift`
- Layout dos 4 componentes: `Shell/{SidebarView,HeaderView,BodyView,StatusBarView}.swift`

## Comandos
`swift build` · `swift test` · `swift test --filter TextBuffer` · `swift test --filter EditorDrawingTests` · `scripts/make-app.sh [debug|release]` (gera `dist/ide-swift.app`) · `scripts/run.sh [workspace]` (build + `open -n`).

Nenhum CI, formatter ou linter de repo está configurado — não sugira `swiftlint`/`swiftformat` como se fossem do projeto. `Package.swift` compila em `swiftLanguageModes: [.v6]` (strict concurrency), então passar `-swift-version 5` ou adicionar `@unchecked Sendable` para calar o compilador é bug.

## Gotchas de macOS/AppKit
- Um executável SwiftPM não vira app por si só: o `.app` precisa de `Contents/Info.plist` com `CFBundleIdentifier`, `LSMinimumSystemVersion` e `NSPrincipalClass` (`NSApplication`). Sem isso roda sem ícone, sem menu e sem janelas em foreground.
- Botões de toolbar macOS precisam de `bezelStyle = .texturedRounded` (ou `.automatic`) para o visual nativo; SwiftUI `Button` puro não é o mesmo componente.
- Comece a janela com `.windowStyle(.titleBar)` e configure `toolbar` no `Scene`; `NavigationSplitView` fora de `Scene` perde a sidebar translúcida.
- `NSTextView` usa coordenadas *flipped* — cálculo de gutter, minimap e scroll sync quebra silenciosamente se você assumir o contrário.
- `deleteBackward(_:)` é action do `NSResponder`, não hook sobrescrevível. O ponto certo para coalescer undo é o delegate `textView(_:shouldChangeTextIn:replacementString:)`, que cobre digitação, colagem e delete. Deve ficar em `extension` do Coordinator, senão o compilador complains de "nearly matches".
- Grupo de undo aberto + `Cmd-Z` = primeiro undo só fecha o grupo. Feche por `Timer`, não na próxima edição.
- Editar `NSTextStorage` programaticamente **colapsa a seleção**; um transformador de texto precisa resselecionar o bloco, senão apertar ⌘/ duas vezes desfaz só a última linha.
- `NSTextView` pinta o próprio fundo **por cima** das subviews: uma view de highlight atrás do texto nunca aparece. O lugar certo é `drawBackground(in:)`, que roda antes de o texto ser desenhado.
- `addBackgroundColorAttribute` / `removeBackgroundColorAttribute` saíram do SDK 27. Não use para highlight de linha.
- Em Swift `"\r\n"` é **um** `Character`; para detectar terminadores de linha itere por `unicodeScalars`, nunca compare `String.last` com `"\n"`.
- Rodar via `open` deixa o cwd em `/`. A workspace só vem de `--workspace`; sem ele a IDE abre em `~/Projects`.
- Recursos com SwiftUI + `@State`/`@Observable`: o modelo fica em `@Observable` (Observation), não `ObservableObject`, e muta no `@MainActor`.
- Erros do `swift build` só são parseáveis de forma confiável com `-Xswiftc -diagnostic-style=json`; regex do swift-driver é fallback.

## Critério de "pronto"
Antes de dizer que uma fase está pronta: `swift build` sem warning, `swift test` verde, e o comportamento verificado em **Light e Dark mode** (a IDE é usada nos dois). Fases e checklist funcional estão em `PLAN.md` §7.
