# PaneFlow — Arquitetura

Documento vivo. Fase 0 (pesquisa e viabilidade) concluída em 2026-10-22.
Ambiente de referência: macOS 27.0.1 (26A434), Xcode 27.0, Swift 6.4, Apple Silicon (arm64),
MacBook (1470×956 pt @2x) + monitor externo LG 1920×1080 @1x posicionado à esquerda/acima
(origem AppKit `(-1920, 227)`, origem global/AX `(-1920, -351)`).

---

## 1. Decisões principais

| Decisão | Escolha | Justificativa |
|---|---|---|
| Versão mínima | **macOS 14.0 (Sonoma)** | `SCScreenshotManager.captureImage(contentFilter:configuration:)` exige 14.0 (verificado no header do SDK). `SMAppService` exige 13.0. Nada do núcleo exige 15+. Recursos de 15+ (tiling nativo) são tratados por coexistência, não por dependência. |
| Linguagem | Swift 6 (modo de linguagem 6, concorrência estrita) | Detecção de data races em tempo de compilação; essencial num app residente com IPC bloqueante. |
| UI | AppKit (status item, painéis, `NSPanel` não ativável) + SwiftUI hospedado (onboarding, Settings, conteúdo do Snap Assist) | `NSPanel` dá controle fino de nível/foco/ativação que o SwiftUI puro não dá. |
| Build | Swift Package Manager + script de empacotamento (`scripts/build-app.sh`) | Sem dependências externas (xcodegen/tuist não instalados e desnecessários). `swift build`/`swift test` são reproduzíveis em CI. Um `.xcodeproj` pode ser gerado depois via `xed Package.swift`. |
| Sandbox | **Não** usa App Sandbox | Controlar janelas de outros processos via Accessibility é incompatível com o sandbox. Distribuição direta (Developer ID + notarização), não Mac App Store. |
| Dependências externas | Nenhuma | — |
| APIs privadas | Nenhuma | Ver §6 (o que **não** usamos e por quê). |

## 2. Módulos

```
PaneFlowCore     (Foundation + CoreGraphics; sem AppKit; 100% testável por unidade)
  Geometry/      CoordinateConverter, extensões de CGRect, GeometryVerifier
  Displays/      DisplayDescriptor, DisplayTopology (busca de monitor por ponto/retângulo)
  Layout/        LayoutDefinition, LayoutCatalog, LayoutEngine, SplitSolver (base do SnapConstraintSolver)
  Window/        WindowSnapshot, WindowEligibility, WindowIdentityResolver (correlação multi-sinal)
  Diagnostics/   LatencyStatistics (p50/p95)

PaneFlowSystem   (AppKit, ApplicationServices, CoreGraphics; integra com o SO)
  Accessibility/ AXElement (wrapper tipado), AccessibilityExecutor (fila serial + timeouts)
  Window/        WindowRepository (descoberta), WindowGeometryController (operação verificada),
                 WindowRestoreManager
  Displays/      DisplayManager (NSScreen → DisplayTopology, observa mudanças)
  Permissions/   PermissionManager (Accessibility, Screen Recording)
  Diagnostics/   Log (OSLog por categoria), PerformanceMonitor, DiagnosticsReport

PaneFlow         (executável; app residente LSUIElement)
  Application/   main, AppDelegate, ApplicationCoordinator
  Interface/     MenuBarController, PermissionsWindowController + PermissionsView (SwiftUI)
  SelfTest/      Phase1SelfTest (validação real de mover/redimensionar com read-back)
```

Fases seguintes adicionam (nomes da especificação mantidos):
`SnapEngine`, `SnapZoneDetector`, `SnapStateMachine`, `SnapTransactionCoordinator`, `WindowDragMonitor`,
`SnapPreviewPanel` (Fase 2); `SnapAssistPanel`/`SnapAssistViewModel` (Fase 3); `ScreenCaptureService`,
`WindowThumbnailService`, `ThumbnailCache` (Fase 4); `SnapGroupManager`, `SnapGroupResizer`,
`SnapGroupDivider`, `SnapConstraintSolver` (Fase 5) …

Regra de dependência: `PaneFlow → PaneFlowSystem → PaneFlowCore`. O Core nunca importa AppKit;
lógica de decisão (zonas, layouts, máquina de estados, solver, correlação) mora no Core
para ser testada sem permissões nem monitores reais.

## 3. Sistemas de coordenadas

| Espaço | Origem | Eixo Y | Usado por |
|---|---|---|---|
| **Global (CG/AX)** | canto sup. esq. do monitor principal | para baixo | `AXPosition`, `CGWindowListCopyWindowInfo`, `CGDisplayBounds`, `SCWindow.frame`, `CGEvent.location` |
| AppKit | canto inf. esq. do monitor principal | para cima | `NSScreen.frame/visibleFrame`, `NSWindow.frame`, `NSEvent.mouseLocation` |
| Local do monitor | origem do monitor | — | layouts (frações 0…1 da área útil) |
| Pixels | — | — | apenas captura (`points × backingScaleFactor`) |

**Representação canônica interna: Global (CG/AX), em pontos.** Toda conversão passa por
`CoordinateConverter`, parametrizado pela altura do monitor principal:
`global.y = primaryHeight − (appKit.y + appKit.height)` (a função é a própria inversa).
Nenhum código assume origem zero: monitores à esquerda/acima produzem coordenadas negativas
(caso real do ambiente de teste — coberto por testes com esse fixture).

## 4. Concorrência e resiliência a processos externos

- Chamadas AX são IPC síncrono para o processo alvo. Um app travado bloqueia a chamada até o timeout.
- `AXUIElementSetMessagingTimeout(systemWide, 0.75)` define um teto global (padrão do sistema ≈ 6 s).
- Todas as chamadas AX rodam no `AccessibilityExecutor` (fila serial dedicada, fora da main thread),
  expostas como `async`. A main thread nunca fala com outro processo.
- `AXUIElement` não é `Sendable`; é encapsulado em `AXElement: @unchecked Sendable`, justificado
  pelo fato de que só é desreferenciado dentro do executor.
- Sem laços de tentativa ilimitados: o aplicador de frame faz no máximo **uma** correção (ver §5).
- Erros AX são mapeados para `AXFailure` (`invalidElement`, `cannotComplete`, `notTrusted`, …).
  `kAXErrorInvalidUIElement` ⇒ janela deixou de existir; `kAXErrorCannotComplete` ⇒ app sem resposta.

## 5. Operação de geometria verificada (Fase 1)

`WindowGeometryController.apply(frame:to:)`:
1. Processo ainda ativo (`NSRunningApplication(processIdentifier:)`, `isTerminated`).
2. Janela ainda válida (leitura de `AXRole` bem-sucedida).
3. Elegibilidade (`WindowEligibility`: papel `AXWindow`, subpapel padrão, não minimizada, tamanho mínimo).
4. Atributos modificáveis (`AXUIElementIsAttributeSettable` para posição e tamanho).
5. Frame alvo calculado pelo chamador (LayoutEngine) e arredondado para pontos inteiros.
6. Aplicação: **posição → tamanho → posição** (ao encolher perto da borda, alguns apps limitam o
   tamanho pela posição antiga; a segunda posição corrige — mesma técnica de gerenciadores maduros).
7. Leitura real da geometria.
8. `GeometryVerifier` classifica: `exact` (≤ 1 pt), `adjustedByApplication` (o app impôs
   mínimo/máximo/incremento — ex.: Terminal arredonda para células), `failed`.
9. Se `failed` e for seguro, restaura o frame anterior (apenas se a geometria atual ainda for a que
   nós deixamos — não sobrescreve um movimento do usuário). Uma tentativa, sem loop.

AX **não** oferece transação atômica entre processos. Grupos (Fase 3/5) usarão compensação:
registrar frames anteriores, aplicar, verificar, e desfazer as partes aplicadas se outra falhar.

## 6. Pesquisa de viabilidade (Fase 0) — resultados

### 6.1 Permissões (medido neste Mac)
- `AXIsProcessTrusted()` = `false` e `CGPreflightScreenCaptureAccess()` = `false` para o processo de
  desenvolvimento. Logo, nenhuma operação real sobre janelas pôde ser executada nesta sessão sem
  que o usuário conceda Acessibilidade ao `PaneFlow.app`.
- `CGWindowListCopyWindowInfo` funciona **sem** permissão, mas `kCGWindowName` vem `nil` (verificado:
  todas as janelas listadas sem nome). Com Screen Recording o título fica disponível.
- **Input Monitoring não é necessário**: o plano de detecção usa `NSEvent.addGlobalMonitorForEvents`
  apenas para eventos de mouse (`leftMouseDown/Dragged/Up`), que funcionam com Acessibilidade.
  Atalhos globais (Fase 8) usarão `RegisterEventHotKey` (Carbon, público, sem permissão extra).
- A concessão de Acessibilidade (TCC) é vinculada à assinatura de código. Com assinatura ad-hoc,
  **cada rebuild invalida a permissão**. Nenhuma identidade de assinatura existe neste Mac
  (`security find-identity` = 0). Ver DEVELOPMENT.md (usar um certificado "Apple Development" ou um
  certificado local estável via `PANEFLOW_SIGN_IDENTITY`).

### 6.2 Detecção de arraste (risco alto) — estratégia escolhida
O macOS não publica "a janela X está sendo arrastada". Estratégia híbrida (Fase 2):
1. `leftMouseDown` global → hit-test AX (`AXUIElementCopyElementAtPosition` no system-wide) →
   subir até o ancestral `AXWindow`; guardar frame inicial. Não decide nada ainda.
2. `leftMouseDragged` (amostrado, ≤ 60 Hz) → reler a **posição** da janela candidata. Só entra em
   `trackingDrag` quando a posição mudou acima de um limiar **e o tamanho não mudou**.
   - Arraste de arquivo no Finder, seleção de texto, arraste de abas/elementos: a janela não se move ⇒
     nunca vira snap.
   - Redimensionamento manual: o tamanho muda ⇒ descartado.
3. Zona de snap avaliada pela posição do cursor (não da janela) com histerese e atraso configurável.
4. `leftMouseUp` → commit somente se o estado for `previewing`.
`AXObserver` (`kAXWindowMovedNotification`) é complementar (confirma movimento), não primário: chega
com atraso variável e alguns apps só o emitem ao final do arraste.
**Resultado do experimento E6 (2026-10-22, macOS 27):** em movimentos pela barra de título, os
monitores globais recebem `leftMouseDown`, mas **não** `leftMouseDragged`/`leftMouseUp` (o window
server conduz o arraste); em redimensionamentos recebem. Por isso, enquanto o botão está pressionado
sobre uma janela, o PaneFlow amostra cursor (`CGEvent(source:nil).location`), botão
(`NSEvent.pressedMouseButtons`) e Esc (`CGEventSource.keyState`) a 60 Hz.

### 6.3 Correlação AXUIElement ↔ CGWindowID / SCWindow (risco alto)
- A única ponte direta (`_AXUIElementGetWindow`) é **API privada — não usada**.
- Estratégia: correlação multi-sinal no `WindowIdentityResolver` (Core, testado):
  mesmo PID + frame igual com tolerância de 2 pt + título igual quando ambos disponíveis +
  restrição 1-para-1. Resultado: `unique(windowID)`, `ambiguous([ids])` ou `none`.
- Ambíguo (ex.: duas janelas do mesmo app empilhadas no mesmo frame com o mesmo título) ⇒ **sem
  miniatura** (placeholder + ícone + título), conforme especificação.
- A ordem de `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` é frente→trás e serve como
  heurística de relevância (foco recente) para o Snap Assist.
- Identidade dentro da sessão: o próprio `AXUIElement` (comparável via `CFEqual`) enquanto válido;
  `kAXUIElementDestroyedNotification` invalida. Entre sessões: nada é persistido como identidade
  durável (PID/título mudam).

### 6.4 Tiling nativo do macOS (15+) — conflito confirmado neste Mac
`defaults read com.apple.WindowManager` mostra `EnableTilingByEdgeDrag = 1`: o macOS também vai
encaixar ao arrastar para a borda. Ambos reagiriam ao mesmo gesto. Estratégia de coexistência:
detectar (leitura somente-leitura desse domínio, chave não documentada ⇒ tratada como heurística),
avisar no onboarding e orientar o usuário a desligar em *Ajustes > Mesa e Dock > "Arrastar janelas
para as bordas da tela para organizá-las"*. O PaneFlow **não** altera essa preferência.
Stage Manager: `GloballyEnabled = 0` neste Mac.

### 6.5 Spaces, Stage Manager, tela cheia
- Não há API pública para enumerar/mover entre Spaces. `CGWindowList(.optionOnScreenOnly)` só lista
  janelas do Space atual — usado para priorizar janelas visíveis.
- Janelas em tela cheia nativa vivem em outro Space; não aparecem como on-screen ⇒ inelegíveis.
- Stage Manager: janelas de outros "stages" ficam fora da tela/encolhidas; serão tratadas como
  inelegíveis no Snap Assist. Validação manual pendente (Fase 7).

### 6.6 ScreenCaptureKit
- `SCShareableContent` + `SCContentFilter(desktopIndependentWindow:)` +
  `SCScreenshotManager.captureImage` (14.0+) para capturas únicas — sem stream contínuo.
- `SCWindow.windowID` é o `CGWindowID` ⇒ a correlação AX↔CG (§6.3) serve também para SCK.
- Sem permissão: fallback para ícone + título (o app continua funcional).

## 7. Experimentos

| # | Experimento | Estado |
|---|---|---|
| E1 | Disponibilidade de APIs no SDK (AX, SCK 14.0, timeout de mensagens) | ✅ verificado nos headers |
| E2 | `CGWindowList` sem permissão (títulos ocultos, ordem frente→trás, coordenadas negativas) | ✅ executado |
| E3 | Topologia de monitores real e conversão AppKit↔Global | ✅ executado; virou fixture de teste |
| E4 | Detecção de conflito com tiling nativo | ✅ executado (conflito presente) |
| E5 | Mover/redimensionar Safari e Word com read-back | ⏳ implementado como **Self-Test** no app; requer permissão de Acessibilidade |
| E6 | Taxa de falso positivo do detector de arraste (Finder, texto, abas) | ⏳ Fase 2; requer permissão |
| E7 | Correlação AX↔SCWindow em apps com várias janelas iguais | ⏳ Fase 4; requer Screen Recording |

## 8. Riscos técnicos

| Risco | Impacto | Mitigação |
|---|---|---|
| Arraste não detectável com precisão em alguns apps (ex.: barras de título customizadas) | Alto | Critério "janela se moveu + tamanho constante"; fallback por atalho/menu |
| Conflito com tiling nativo | Alto | Detecção + orientação; não brigar pela geometria (uma única aplicação, sem reaplicar) |
| Apps que impõem tamanho mínimo/incremento | Médio | Read-back + `adjustedByApplication`; solver com mínimos aprendidos |
| Apps travados | Médio | Timeout de 0,75 s, fila fora da main thread, falha controlada |
| Permissão TCC perdida a cada rebuild (ad-hoc) | Médio (dev) | Identidade de assinatura estável |
| Correlação ambígua de miniaturas | Médio | Placeholder seguro, nunca captura "chutada" |
| Spaces/Stage Manager sem API pública | Médio | Operar só no Space atual; documentar limitações |
