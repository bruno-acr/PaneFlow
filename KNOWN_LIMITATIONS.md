# Limitações conhecidas

## Impostas pelo macOS (APIs públicas)
- **Sem transação atômica entre processos**: mover duas janelas são duas operações AX independentes.
  PaneFlow verifica e compensa; não promete atomicidade.
- **Sem ponte pública AXUIElement ↔ CGWindowID**: a correlação é heurística (PID + frame + título).
  Janelas do mesmo app com mesmo frame e sem título distinguível ficam *ambíguas* e não recebem
  miniatura (placeholder).
- **Sem títulos de janelas no window server sem Screen Recording** (`kCGWindowName` = nil). Os títulos
  via Accessibility continuam disponíveis.
- **Tamanho mínimo/máximo não é exposto pela AX** na maioria dos apps; é descoberto por read-back
  (`adjustedByApplication`).
- **Spaces**: sem API pública para enumerar ou mover janelas entre Spaces. PaneFlow trabalha só com o
  Space atual. Janelas em tela cheia nativa (outro Space) não são elegíveis.
- **Stage Manager**: comportamento ainda não validado (Fase 7).
- **Tiling nativo (macOS 15+)**: compete com o snap por arraste. PaneFlow apenas detecta e orienta; não
  altera a preferência. A detecção usa chaves não documentadas de `com.apple.WindowManager`
  (somente leitura, tratada como heurística).
- Apps com timeout: chamadas AX limitadas a 0,75 s; um app travado faz a operação falhar (sem travar
  o PaneFlow).

- **Divisa entre monitores**: o cursor atravessa a borda compartilhada, então a zona de encaixe ali
  é uma faixa de 16 pt dentro do monitor onde o cursor está e exige parar ~0,3 s.
- **Redimensionamento conjunto**: não existe divisor nativo entre janelas de apps diferentes; o
  PaneFlow observa qual janela muda de tamanho e move as vizinhas (vizinhas = bordas encostadas, até
  20 pt de distância, mesmo monitor). Pode haver um leve atraso visual em apps lentos. O tamanho
  mínimo do vizinho só é conhecido ao soltar o mouse; aí a janela arrastada é recuada.

- **Outros gerenciadores de janelas** (Rectangle, Magnet…) reagem ao mesmo gesto; o PaneFlow avisa
  no menu, mas não os desativa.

## Do estado atual do projeto
- Sem binário assinado/notarizado; sem abertura automática ao iniciar sessão; sem janela de Ajustes
  (preferências ficam no menu da barra).
- Snap Groups ainda não são persistidos nem restaurados entre sessões.
- Assinatura ad-hoc: a permissão de Acessibilidade se perde a cada rebuild (ver DEVELOPMENT.md).
- Menu e atalhos agem sobre a janela em foco do app ativo. Atalhos ainda não são configuráveis (Fase 8).
- "Restaurar janela" só conhece frames alterados nesta sessão do PaneFlow (memória, não persistido).
- Interface só em português (strings fixas; sem catálogo de localização ainda).
- Arrastar uma janela encaixada para fora ainda não restaura o tamanho original (use ⌃⌥↓).
