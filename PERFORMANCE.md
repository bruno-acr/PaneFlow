# Desempenho

Metas da especificação são **objetivos a medir**, não garantias. Métricas são registradas por
`PerformanceMonitor` (p50/p95, reservatório limitado a 512 amostras por métrica) e exportadas em
Diagnostics › Export Diagnostics Report e no relatório do self-test.

## Métricas instrumentadas
| Métrica | Onde |
|---|---|
| `window.discovery` | `WindowRepository.discoverWindows` (enumeração AX + correlação) |
| `window.geometry.apply` | `WindowGeometryController.apply` (validação → escrita → read-back) |

## Medições reais (2026-10-22, MacBook Apple Silicon, macOS 27.0.1, build release ad-hoc)
| Item | Meta | Medido | Observação |
|---|---|---|---|
| CPU em repouso | ≈ 0 | **0,0 %** (`ps`, 26 s; 0,21 s de CPU acumulada incluindo a inicialização) | sem polling além do timer de permissão de 30 s |
| Memória em repouso | < 80 MB | **≈ 74 MB RSS** | com a janela SwiftUI de permissões aberta; sem ela ainda não medido |
| Inicialização fria | < 2 s | não medido com precisão | o self-test sem permissão (iniciar → relatório → sair) levou 1,9 s de relógio no total |
| Latência de snap / Snap Assist | 100 / 200 / 250 ms | não medido | depende das Fases 2–3 e da permissão de Acessibilidade |
| `window.discovery` | — | **107 ms** (1 amostra, 9 janelas) | primeira execução, inclui enumeração de todos os apps |
| `window.geometry.apply` | < 250 ms | **p50 59 ms / p95 234 ms** (8 amostras) | p95 = primeira escrita no Word; reaplicações sem mudança: < 3 ms |

## Medição em uso — 0.3.5 (2026-10-22, app residente, permissões concedidas)
| Item | Medido | Ferramenta |
|---|---|---|
| Memória real (phys_footprint) | **30 MB** (pico 33 MB) | `footprint` |
| RSS | 110 MB | `ps` — inclui frameworks do sistema compartilhados; não é memória exclusiva do app |
| CPU em repouso | **0,0 %** em 10 de 12 amostras de 5 s; picos de 1–2 % durante interação | `top -stats cpu,power` |
| Impacto de energia (POWER) | **0,0** em repouso | `top` |
| Wakeups ociosos | ~0,5/s (678 → 708 em 60 s) | `top -stats idlew` |
| CPU acumulada | 4,4 s em 3 min de uso | `ps` |

Trabalho só acontece durante gestos: amostragem a 60 Hz enquanto o botão está pressionado sobre
uma janela; leituras do window server (< 1 ms cada) e escrita AX ao encaixar. Miniaturas: apenas
com o Snap Assist aberto, no máximo 4 capturas simultâneas, descartadas ao fechar.

## Decisões que afetam o desempenho
- Atributos de snapshot lidos com `AXUIElementCopyMultipleAttributeValues` (1 IPC por janela, em vez de 8).
- Mudanças de monitor por notificação (`didChangeScreenParametersNotification`), sem polling.
- Menu reconstruído apenas ao abrir ou quando permissões/monitores mudam.
- Permissões: timer de 30 s (tolerância 10 s) chamando duas funções locais baratas; 1 s só com o
  onboarding visível.
