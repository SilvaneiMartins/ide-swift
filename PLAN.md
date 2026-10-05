# ide-swift — Plano de Construção

**Nome:** ide-swift
**Alvo:** macOS desktop (macOS 26+ / Apple Silicon-first), apenas macOS.
**Língua de implementação:** Swift 6.4 (SwiftUI + AppKit).
**Objetivo:** IDE para escrever, compilar e executar **aplicações macOS e APIs/serviços em Swift**, com auto-complete e IntelliSense, usando o design system nativo da Apple e o Xcode como referência de UX.

---

## 1. Escopo (decidido — não reabrir)

**Dentro:**
- Aplicativos macOS desktop (SwiftUI e AppKit), bundles `.app`
- APIs e serviços backend em Swift (Vapor, Hummingbird, `swift-service-lifecycle`, `AsyncHTTPClient`)
- Bibliotecas e pacotes Swift reaproveitáveis
- Testes com `swift test` (XCTest e Swift Testing)
- Execução local: o usuário abre a IDE e roda o próprio projeto

**Fora (permanentemente):**
- iOS, iPadOS, watchOS, tvOS, visionOS — sem simuladores, sem device support, sem assinatura de plataforma
- Android, cross-platform, qualquer target que não seja `macOS`
- Jogos, engine gráfica, editor de cenas, profiler de GPU
- Distribuição: sem App Store, sem Developer ID, sem notarização. **Só local.** O `.app` gerado por `scripts/make-app.sh` roda apenas na máquina de desenvolvimento
- Accounts, login, cloud, telemetria. Nenhuma dependência de rede em runtime
- Kubernetes/Docker/orquestração. O processo de build roda direto via `Process`/`forkpty`

**Consequências de escopo:**
- Workspace = um ou mais pacotes SwiftPM com targets `.executable` macOS, `.library` e `.test`. Nada de `.xcodeproj`
- Alvo de plataforma é sempre `.macOS(...)`; se aparecer `UIDevice`, `UIKit`, `SpriteKit`, `Metal` ou target iOS no código da IDE, é bug
- Perfis de build: apenas Debug e Release. Sem simuladores, sem dispositivos, sem watchOS destinations
- O "destination" do Header = **arquivo executável do pacote + configuração**, não um scheme de simulador
- Build de apps SwiftUI precisa de `swift build` + empacotamento manual; o preview em canvas é nice-to-have, não infraestrutura crítica

## 2. Princípios de produto

1. **Nativo antes de customizado.** Toda UI usa controles e cores semânticas do macOS. Nada de tema próprio. Fonte de verdade visual: AppKit + SwiftUI.
2. **Minimalista, não um clone do Xcode.** O Xcode é referência de * ergonomia*, não de aparência. Controles só com ícone, barras finas, pouca moldura, muito espaço para o código. As referências visuais do projeto estão em `IMG_5969.pdf` e `IMG_5970.pdf` na raiz: barra de ferramentas fina com ícones à esquerda, breadcrumb, área de código grande com gutter estreito, barra de status mínima e um painel inferior expansível.
3. **SwiftPM é o único build system suportado.** Sem `xcodebuild`, sem `.xcodeproj`, sem schemes de simulador.
4. **IntelliSense via SourceKit-LSP.** Não reimplementar parser/indexador. SourceKit-LSP já entende o compilador Swift, módulos, macros e SDK.
5. **Latência é requisito funcional.** O loop de digitação tem orçamento de 16 ms. Trabalho de indexação nunca no main thread.
6. **Estrutura de 4 componentes, fixa:** Sidebar, Header, Body, StatusBar.

## 3. Decisões técnicas (verificadas no ambiente atual)

| Item | Decisão | Detalhe |
|---|---|---|
| Build da própria IDE | SwiftPM (executable target) + script de empacotamento `.app` | evita projetar Xcode gerenciado à mão; distribuição só local |
| UI | SwiftUI para chrome (sidebar/header/statusbar), AppKit para o editor | `NSTextView` não tem equivalente em SwiftUI |
| Engine de linguagem | **SourceKit-LSP** | `xcrun --find sourcekit-lsp` → `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp` |
| Formatação | **swift-format** | `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-format` |
| AST / refactor | **swift-syntax** | dependência SPM, usada em formatação, rename seguro e code actions |
| Compilação | `swift build` (SwiftPM) com terminal embutido lendo stdout/stderr | `-Xswiftc -diagnostic-style=json` para erros clicáveis |
| Execução | `swift run <target>` / binário debug; terminal via `Process` + pipes, nunca `NSTask` shell | para APIs: processo em background + log view + abrir `http://localhost:PORT` no navegador padrão |
| Concorrência | Swift 6 **strict concurrency**; UI isolada em `@MainActor` | Xcode 27 / Swift 6.4 |
| Índice de arquivos | FileSystem + `DispatchSource` / `FSEvents` | |
| Persistência de estado | `SceneStorage` + JSON em `~/Library/Application Support/ide-swift` | sem CoreData no v1 |

Restrições do ambiente (26-09-2026): macOS 27.0, Xcode 27.0 (27A266a), Swift 6.4, `xcode-select -p` = `/Applications/Xcode.app/Contents/Developer`.

## 4. Arquitetura de módulos

```
ide-swift/
├── Package.swift                 # product: ide-swift (executable macOS 26+)
├── AGENTS.md
├── PLAN.md
├── scripts/
│   ├── make-app.sh               # swift build -> empacota .app com Info.plist
│   └── run.sh                    # build + open do .app
├── Sources/
│   ├── ide-swift/                # @main: App, Scene, WindowGroup, Commands
│   ├── DesignSystem/             # tokens (cores, tipografia, espaçamento), wrappers SwiftUI
│   ├── Shell/                    # Sidebar, Header, Body, StatusBar + Layout e resizing
│   ├── EditorCore/               # NSTextView host, buffers, undo, goto-line, seleção múltipla
│   ├── SyntaxHighlight/          #rules -> NSAttributedString, cache por linha
│   ├── LSPClient/                # processo, JSON-RPC, framing, TypedIDs
│   ├── Features/                 # completion, diagnostics, signature, rename, hover
│   ├── ProjectModel/             # workspace, arvore de arquivos, Package.swift parsing
│   ├── BuildRunner/              # swift build/run/test, parse de output, terminal
│   └── Terminal/                 # PTY wrapper (forkpty) para terminal embutido
└── Tests/
    ├── LSPClientTests/           # fixtures de *.swift, mock server
    ├── EditorCoreTests/
    └── ProjectModelTests/
```

Fluxo: `NSTextView` → `didChangeText` → `TextBuffer` (fonte única de verdade) → debounce → `LSPClient.didChange` → respostas → `FeatureStore` → SwiftUI re-render.

## 5. Layout da janela (4 componentes)

```
┌──────────────────────────────────────────────────────────────┐
│  Toolbar/Header: Run ▸ Stop | ▾ target | ▾ config (Debug/Release) │  ← material fino
├──────────┬───────────────────────────────────────────────────┤
│ Sidebar  │ Body                                              │
│ (não     │  ┌ breadcrumbs ───────────────────────────┐       │
│  showing │  │ gutter │ NSTextView (Swift)            │       │
│  files / │  │  1..  │                                │       │
│  issues  │  │       │                                │       │
│          │  └────────────────────────────────────────┘       │
├──────────┴───────────────────────────────────────────────────┤
│ StatusBar: ● Ln 12, Col 8 · Swift · Debug · build ✓ · LSP: ok │  ← base
└──────────────────────────────────────────────────────────────┘
```

**Sidebar** — `NavigationSplitView` com sidebar translúcida (`.ultraThinMaterial`, comportamento nativo do Finder/Xcode):
- Segmented control: Project / Structure / Search
- Project: árvore de arquivos, indicador de arquivo modificado na tree (não no arquivo)
- Structure: símbolos via `textDocument/documentSymbol`
- Search: pesquisa textual com replace-all dentro do workspace
- Rodapé: "Open Recent", "Add Package…", config Debug/Release, botão de build

**Header** — toolbar unificada no estilo Xcode: Run/Stop, seletor de **target executável** (nunca simulador), seletor de configuração (Debug/Release), arquivo aberto, `⌘⇧O` Command Palette, toggle do painel de saída.

**Body** — editor:
- `NSTextView` com `NSTextStorage` + `NSLayoutManager` (delegação de `textStorage:edited:range:changeInLength:` para marcação incremental)
- Gutter com números de linha, marca da linha atual, marcadores de erro/warning do LSP
- Linha atual e ocorrência selecionada com cor semântica `.selectedContentBackgroundColor`
- Find & Replace sheet, Go to Line, comment/uncomment block
- Split horizontal/vertical, abas por arquivo
- Aba de preview do SwiftUI com live reload (fase tardia)
- **Aba de saída (API):** log do processo agrupado por nível (debug/info/warn/error), streaming, "Open in Browser", "Copy cURL" quando o log de boot declarar a porta

**StatusBar** — linha/coluna, tipo de seleção, linguagem, configuração (Debug/Release), branch git, estado do build (spinner + última duração + contagem de erros), estado do LSP, porta do serviço em execução, zoom de fonte.

## 6. Auto-complete e IntelliSense (escopo do plano)

Capacidades via SourceKit-LSP, cada uma com chave de toggle e teste manual:

| # | Capacidade | LSP | UI |
|---|---|---|---|
| 1 | Complete code | `textDocument/completion` | lista com ícone + assinatura + doc; filtro por `.`/letra; aceita com Tab/Enter |
| 2 | Doc do item | `textDocument/hover` | popover com Quick Help |
| 3 | Assinatura de função | `textDocument/signatureHelp` | popover comhighlight do argumento ativo |
| 4 | Erros e avisos em tempo real | `textDocument/diagnostic` | squiggle + marcador no gutter + lista de problemas |
| 5 | Ir para definição | `textDefinition` | reveal + selection na tree |
| 6 | Encontrar referências | `textDocument/references` | painel Search com preview |
| 7 | Renomear símbolo | `textDocument/rename` | preview de todas as ocorrências antes de aplicar |
| 8 | Highlights semânticos | `textDocument/semanticTokens/full` | keywords, tipos, strings coloridos sem regex |
| 9 | Código deacción / quick fix | `textDocument/codeAction` | menu no lightbulb + ⌘. |
| 10 | Formatação | `swift-format` | ⌘⇧I no arquivo, ⌃⌥⇧I no workspace |
| 11 | Organize Imports | `textDocument/codeAction` | ⌃O |
| 12 | Indexação workspace | index correspondente | indicador de progresso na StatusBar |

Regras de UX (o que diferencia uma boa IDE de um popup feio):
- Debounce de 150 ms após digitação; hoje o LSP faz parse assíncrono e responde.
- Cancelamento de requisição obsoleta: sempre enviar `cancelRequest` para a anterior do mesmo arquivo antes de emitir a nova.
- Prioridade: completion nunca bloqueia a digitação; se o LSP não responder em 250 ms, não mostra nada.
- Filtro de completions: filtrar por `fuzzy`, mostrar no máximo 50 itens, agrupar por `kind`.
- Ignorar completions auto-inseridos fora do cursor; nada de travar o cursor.
- Assinatura só aparece quando a chamada está de fato em progresso (heurística de unbalanced `(`, não de delay fixo).

## 7. Roadmap por fases

**Fase 0 — Fundação (semanas 1-2)**
- `Package.swift` com todos os módulos e `platform: [.macOS(.v26)]`
- `scripts/make-app.sh` gerando `.app` com `Info.plist` (bundle id, ícone, `LSMinimumSystemVersion`, documento de projeto)
- Janela com os 4 componentes em estado estático, já com `NavigationSplitView` + material
- Wizard "New Project" que gera um pacote SwiftPM (template: app macOS / API HTTP / biblioteca)
- `AGENTS.md` e este plano versionados

**Fase 1 — Editor (semanas 3-5) — CONCLUÍDA**
- `TextBuffer` como source of truth, com índices de linha em UTF-16 cacheados
- Undo coalescido por rajada de digitação (grupo aberto + fechamento por `Timer`)
- Gutter desenhado à mão com números de linha; faixa de linha atual em `drawBackground(in:)`
- Abas de documento, indicador de modificado, salvar, arquivos recentes em JSON
- Realce sintático com swift-syntax: parse fora da main thread, repinta só da primeira linha alterada até o fim
- Go to Line (⌃L), Find nativa (⌘F), Comentar/Descomentar (⌘/) com indentação preservada
- **Falta para fechar a fase:** split view (⌘\) e abas de preview SwiftUI são da Fase 6/optional; sem isso a fase está completa

**Fase 2 — LSP (semanas 6-8)**

*Decisões fechadas com o usuário: (a) diagnósticos primeiro, (b)
sourcekit-lsp com build system SwiftPM completo, (c) painel inferior
expansível com o log do LSP.*

Sequência de trabalho — cada passo é verificável sem UI:

1. **`LSPClient/JSONRPC.swift`** — tipos de mensagem e framing `Content-Length`.
   Fraco de dependência: é testável sem servidor, com `Data` e `String` puros.
2. **`LSPClient/SourceKitLSPServer.swift`** — `actor` que faz o spawn de
   `sourcekit-lsp`, envia/recebe em background, cancela requisições
   obsoletas. Executável resolvido por `xcrun --find sourcekit-lsp`.
   Argumentos desta versão (verificado em 26-09-2026): `--bypass-workspace-trust`
   e `--configuration debug|release`. **Não existe mais** a flag
   `--experimental-feature sourcekit-lsp-experimental-*`; o build description
   é pedido por LSP depois, no passo 3.
3. **Lifecycle** — `initialize` (com `workspaceFolders`) → `initialized` →
   `workspace/buildTarget` com `{"swiftPM": {"configuration": "debug",
   "swiftSDK": "macosx"}}`. É isso que faz o servidor indexar o pacote de
   verdade, e é o que diferencia "completo com swiftpm" de "inferência".
4. **Sync de documentos** — `didOpen`/`didChange` incremental/`didSave`/
   `didClose`. O texto do `didChange` vem do `TextBuffer` (UTF-16), nunca do
   `NSTextView`.
5. **Diagnósticos** — `textDocument/publishDiagnostics` → marcadores no gutter,
   squiggle no editor e contagem na StatusBar. **Primeira capability visível.**
6. **Painel inferior** com o log do LSP (stdout + stderr + protocolo), fino e
   expansível, no estilo das referências de design.
7. **Hover, completion e signature help** — com debounce de 150 ms,
   `cancelRequest` antes de reemitir e nunca bloqueando a digitação.
8. **Semantic tokens** — highlight semântico do compilador, no lugar da classificação por palavra-chave.

Riscos desta fase: `workspace/buildTarget` pode demorar dezenas de segundos
num workspace novo (o servidor roda `swift build` internamente) — a UI precisa
mostrar progresso em vez de parecer travada.

**Fase 3 — Refactor (semanas 9-10)**
- Definição, referências, rename com preview
- Code actions / quick fix, organize imports
- swift-format integração
- Navegação de testes: Discover Tests (`test_discovery`) e "Run Test at Cursor"

**Fase 4 — Build & Run (semanas 11-13)**
- `swift build` com streaming de output na StatusBar e num terminal embutido (forkpty)
- Erros de compilação clicáveis via `-diagnostic-style=json` (regex do swift-driver só como fallback)
- Executar app target `.executable`, parar processo, monitorar stdout/stderr do app
- `swift test` integrado ao gutter (teste passando/falhando por arquivo)
- **Modo API:** roda o serviço em background, painel de log, "Open in Browser" para `http://localhost:PORT`, output agrupado por nível

**Fase 5 — Workspace & Git (semanas 14-15)**
- Workspace multi-pacote/multi-target SwiftPM, detecção de dependências externas
- Integração Git: status na sidebar, branch na StatusBar, diff
- Persistência de layout e sessão

**Fase 6 — Polimento (semanas 16-18)**
- Command Palette (⌘⇧P), keybindings, Light/Dark
- Acessibilidade: VoiceOver, navegação por teclado completo, foco visível
- Benchmarks de latência e testes de fumaça por fluxo
- Documentação local de ajuda (gerada do próprio LSP, sem rede)

## 8. Layout / Design System Apple (regras de implementação)

- **Cores:** somente `.background`, `.labelColor`, `.secondaryLabelColor`, `.selectedContentBackgroundColor`, `NSColor.controlBackgroundColor`, etc. Zero `Color(hex:)` próprio. A **única** exceção é `Palette.swiftOrange` (cor da marca Swift), usada só nos ícones de pasta e de arquivo `.swift` — pedida explicitamente e legível em Light e Dark.
- **Ícones da tree menores que o texto:** `Label` do SwiftUI usa a mesma fonte para ícone e título, e o ícone sai grande demais numa row de fonte pequena. `FileRow` monta `HStack` com `font(.system(size: 10))` no ícone e `12` no nome.
- **Tipografia:** SF Mono com fallback; tamanho é preferência do usuário, ajustável (⌘+ / ⌘-).
- **Ícones:** apenas SF Symbols (`"play.fill"`, `"stop.fill"`, `"chevron.right"`).
- **Materiais:** sidebar e statusbar com `.ultraThinMaterial` + vibrancy; toolbar com material fino.
- **Espaçamento:** escala 2/4/8/12/16/20/24; raio de canto 6 (controles), 10 (painéis).
- **Comportamento:** menus reais (`CommandGroup` com atalhos padrão do macOS), não atalhos customizados quando o padrão do sistema já existe; `⌘N` novo arquivo, `⌘O` abrir, `⌘W` fechar, `⌘S` salvar, `⌘⌥⌘F` find no arquivo, `⌘⇧O` palette, `⌃⌘→` build, `⌘R` run, `⌘.` cancelar.
- **Janela:** toolbar unified, inspetor opcional, `⌘⌃X` alterna sidebar, full screen nativo, `restoreFrameAutosaveName` para persistir geometria.
- **Dark mode** obrigatório; verificar contraste em ambos.
- **Foco/seleção de cor semântica** — nunca azul genérico.

### Visual VS Code-like (aprovado em 04-10-2026, referência IMG_6156)

- **Árvore mostra tudo:** `WorkspaceScanner` não filtra pastas ocultas (`.build`, `.swiftpm`, `.vscode` aparecem). Única exceção: `.git` (o VS Code também esconde seu conteúdo via `files.exclude`; escanear `.git/objects` eager é pesado).
- **Header da sidebar:** linha no topo com nome do projeto + 5 ícones de ação (novo arquivo, importar, reload, colapsar, mais). Três deles estão `disabled` com tooltip "em breve" — não se descreve como funcional o que não existe.
- **Indicador de modificado na árvore:** ponto cinza à direita de arquivos com `isDirty`, mesmo padrão das abas.
- **Empty state (Body):** watermark do logo Swift 80pt com opacity 0.15 + 3 linhas de atalho com keycaps: Importar Projeto (⌘O, ativo), Todos os Comandos (⇧⌘P, **disabled** até a Fase 6), Buscar Arquivo (⌘F, ativo só com documento aberto).
- **Status bar:** esquerda = nome do projeto (bold) + Ln/Col (só com documento); direita = contagem de erros + LSP + estado do build. Removidos "Swift", "Debug" e "Modificado" — Debug já está no header.

## 9. Riscos e decisões abertas

| Risco | Mitigação |
|---|---|
| SourceKit-LSP é lento na primeira indexação de workspace grande | Indexação assíncrona, indicador de progresso,Limitar ao workspace aberto |
| `NSTextView` + SwiftUI: scroll sync e resize só funcionam dentro de `NSViewRepresentable` | Camada fina de bridging; não replicar layout em SwiftUI |
| PTY é C API (`forkpty`) | Encapsular em módulo `Terminal` com `Darwin`; alternativa inicial: pipes + `Process` |
| Regex para erros do swift-driver é frágil | Preferir `--diagnostic-style=json` do swift-driver; regex só como fallback |
| App Store / Sandbox | Fora de escopo: sem assinatura, sem notarização, sem sandbox. Roda local, sem entitlements |
| Concorrência estrita do Swift 6 | Tudo que toca UI é `@MainActor`; clientes de rede (LSP) `actor`; testes de concorrência com `swift test --sanitize=thread` |

Decisões **já fechadas** (ver §1): distribuição apenas local, somente SwiftPM, sem mobile, sem jogos, foco em app macOS + API.

Ainda em aberto antes da Fase 1:
1. Preview do SwiftUI com hot reload: entra no v1 ou fica para v2? (não bloqueia o início)
2. Plugins/extensões: desenhar a API do LSP client com essa porta fechada ou aberta desde o início? (recomendação: interface fechada, sem plugin API no v1)
3. Biblioteca local de trechos de código (snippets) e Live Snippets: prioridade?

## 10. Como verificar o progresso

- `swift build` sem warning (warnings tratados como erro)
- `swift test` para LSPClient, EditorCore e ProjectModel
- Checklist manual por fase em `CHECKLIST.md` (a criar na Fase 1)
- Latência: digitação contínua por 30 s sem frame perdido; completion aparece em < 200 ms pós-tecla
- Escopo: nenhuma dependência adicionada ao `Package.swift` sem necessidade para macOS + SwiftPM
