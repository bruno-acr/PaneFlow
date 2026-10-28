# Changelog

## [Não lançado] — 0.3.5
### Corrigido
- Snap Assist fechava sozinho logo após abrir quando a Gravação de Tela estava concedida: o painel
  era cancelado ao perder o foco de teclado (um alerta do sistema basta para isso). Agora fecha só
  com clique fora, troca para outro app, Esc ou escolha.
### Adicionado
- Aviso no menu quando outro gerenciador de janelas que encaixa por arraste está aberto
  (Rectangle, Magnet, BetterSnapTool, Moom, Divvy, Amethyst, yabai…). No Mac do usuário o Rectangle
  era a causa do "encaixe nativo fantasma" (alturas 848/696, encaixe mesmo após Esc); foi movido
  para a Lixeira a pedido do usuário.

## [Não lançado] — 0.3.4
### Corrigido
- Relato do usuário com mouse real: na divisa entre monitores a janela "escapava" para o outro
  monitor (o cursor não para numa borda que não existe; o teste sintético parava exatamente).
  Nova **resistência na divisa** (`EdgeResistance`, como "Ease cursor movement between displays" do
  Windows): ao arrastar uma janela, o cursor é segurado na borda compartilhada até acumular 140 pt de
  empurrão; movimentos rápidos atravessam quase sem notar. Preferência "Segurar o cursor na divisa
  entre monitores" (ligada por padrão; desligada se ⌥ estiver pressionado).
- Teste de arraste: empurrões relativos de 6 pt contra a divisa (encaixa) e atravessando (vai ao vizinho).

## [Não lançado] — 0.3.3
### Alterado
- Snap Assist: a janela escolhida preenche **exatamente** o espaço vazio, medido pelos frames reais
  das janelas já posicionadas (sem vão nem sobreposição quando a primeira não ficou em 50 %, por
  exemplo por tamanho mínimo do app ou divisão 40/60). O painel também ocupa esse espaço exato.
- Se o app escolhido exige tamanho mínimo maior que o espaço, ele fica encostado na borda da tela e
  as janelas vizinhas são reduzidas para não sobrepor (aviso se alguma recusar).
- Teste de arraste: escolha com ↩ no Snap Assist e verificação de preenchimento exato.

## [Não lançado] — 0.3.2
### Corrigido
- Arrastes de janela eram classificados como "arraste de conteúdo" (log de depuração do teste
  ponta a ponta): a posição via Accessibility atrasa em relação ao cursor durante arrastes conduzidos
  pelo window server. A classificação agora usa os limites do próprio window server
  (`CGWindowListCreateDescriptionFromArray`, sem IPC ao app) a cada amostra enquanto o botão está
  pressionado, e nunca desiste definitivamente antes de soltar.
- Teste de arraste de conteúdo usa o frame efetivamente adotado (Finder tem largura mínima de 714 pt).

## [Não lançado] — 0.3.1
### Corrigido
- **Encaixe ao arrastar não acontecia** (achado pelo teste ponta a ponta): no macOS 27, ao mover
  uma janela pela barra de título, o window server conduz o arraste e os monitores globais não
  recebem `leftMouseDragged`/`leftMouseUp`. O rastreador agora amostra cursor, botão e Esc a 60 Hz
  apenas enquanto o botão está pressionado sobre uma janela. Explica também a falha relatada na
  divisa entre monitores.

## [Não lançado] — 0.3.0
### Adicionado
- **Snap Assist**: após encaixar (arraste, menu ou atalho), a área vazia mostra as outras janelas
  abertas (janelas individuais, não apps), ordenadas por uso recente. Mouse, setas, ↩, esc e busca
  por app/título; janelas do mesmo app identificadas ("2 de 3"). Quartos oferecem as três áreas
  restantes em sequência. A janela escolhida é encaixada e recebe o foco.
- Miniaturas reais via ScreenCaptureKit (`WindowThumbnailService`): sob demanda, no máximo 4
  capturas simultâneas, reduzidas a 480 px, só em memória, canceladas ao fechar; só para janelas
  identificadas sem ambiguidade. Sem Gravação de Tela: ícone + título e link "Mostrar miniaturas…".
- **Inverter janelas** (menu da barra e ⌃⌥S): espelha as janelas encaixadas junto da janela ativa
  (esquerda ↔ direita; em cima ↔ embaixo quando só empilhadas), preservando proporções; desfaz se
  alguma janela recusar.
- Teste de arraste ampliado: Snap Assist abre/fecha com Esc; inversão Safari/Word.

## [Não lançado] — 0.2.1
### Corrigido
- Encaixe na divisa com o monitor vizinho (relato do usuário: não conseguia encaixar na metade
  esquerda do MacBook com monitor à esquerda). A zona agora pertence ao monitor de onde a janela
  veio; faixa de 40 pt dentro + 80 pt de ultrapassagem no vizinho; espera reduzida para 0,2 s.
- Reconhecimento do arraste falhava se a janela já tivesse se movido quando o PaneFlow a identificava
  (tolerância de 2 pt); agora aceita correspondência única próxima.
- Redimensionamento conjunto usa o frame do instante do clique como referência (evita sobreposição de 2–3 pt).
### Adicionado
- `scripts/drag-test.sh`: teste ponta a ponta com eventos de mouse sintéticos (bordas, divisa entre
  monitores, ultrapassagem, travessia rápida, Escape, arraste de conteúdo, redimensionamento conjunto).

## [Não lançado] — 0.2.0
### Adicionado
- Interface em português (pt-BR).
- Encaixe ao arrastar para as bordas (Fase 2, adiantada): metades, quartos nos cantos, maximizar
  na borda superior, prévia translúcida, Escape cancela, ⌥ suprime. Detecção por geometria
  (`PointerGestureTracker`), máquina de estados pura (`SnapStateMachine`).
- Bordas compartilhadas entre monitores: faixa de 16 pt de cada lado, ativada ao parar o cursor
  por 0,3 s (cruzar rápido de um monitor para o outro nunca encaixa).
- Redimensionamento conjunto de janelas vizinhas (base do Snap Group Resizer, Fase 5 adiantada):
  arrastar a divisa entre janelas lado a lado ajusta as vizinhas ao vivo; grades 2×2 incluídas;
  respeita tamanho mínimo do app vizinho ao soltar.
- Atalhos globais: ⌃⌥←/→ (repetir troca de monitor), ⌃⌥↑ maximizar, ⌃⌥↓ restaurar,
  ⌃⌥C centralizar, ⌃⌥↩ próximo monitor. Conflitos detectados e mostrados no menu.
- Menu "Mover para monitor" com metades/maximizar por monitor; quartos no menu de encaixe.
- Ícone do app (`scripts/make-icon.swift` → `Resources/AppIcon.icns`) e `scripts/install.sh`.

## [Não lançado] — 0.1.0 (Fase 0 + Fase 1)
### Adicionado
- Pesquisa de viabilidade e arquitetura (ARCHITECTURE.md).
- `PaneFlowCore`: `CoordinateConverter`, `DisplayTopology`, `LayoutDefinition`/`LayoutCatalog`
  (13 layouts: metades, 40/60, 60/40, 30/70, 70/30, superior/inferior, terços, metade+quartos,
  centro largo, ⅔+⅓, grade 2×2, quatro colunas, maximizar), `LayoutEngine` (gaps/margens sem
  sobreposição), `SplitSolver` (mín./máx.), `WindowEligibilityPolicy`, `WindowIdentityResolver`,
  `GeometryVerifier`, `LatencyStatistics`.
- `PaneFlowSystem`: `AXElement`, `AccessibilityExecutor` (timeout 0,75 s, fora da main thread),
  `WindowRepository`, `WindowGeometryController` (operação verificada), `WindowRestoreManager`,
  `DisplayManager`, `PermissionManager`, `NativeWindowManagerSettings`, `PerformanceMonitor`,
  `DiagnosticsReport`, categorias OSLog.
- App: barra de menus, onboarding de permissões, comandos de janela, self-test de geometria,
  exportação de diagnóstico.
- 55 testes (54 aprovados, 1 pulado por falta de permissão).
