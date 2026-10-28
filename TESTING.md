# Testes

## Como rodar
```bash
./scripts/test.sh                     # tudo
./scripts/test.sh --filter LayoutEngineTests
./scripts/self-test.sh                # aceite da Fase 1 com janelas reais (exige Acessibilidade)
./scripts/self-test.sh --keep         # idem, sem restaurar as janelas no final
```

## Teste de arraste ponta a ponta (`./scripts/drag-test.sh`)
Posta eventos de mouse sintéticos (não mexa no mouse por ~20 s). Usa uma janela do Finder numa pasta
temporária vazia para os testes de mover e a divisa Safari/Word para o redimensionamento conjunto.
Recusa pontos sobre botões/campos. Restaura tudo no final.

| Execução | Resultado |
|---|---|
| 0.3.0 (17:12 UTC) | 6/12 — redimensionamento conjunto e inversão OK; encaixe ao arrastar nunca comprometido |
| 0.3.1 (17:17 UTC) | idem; log mostrou arrastes de janela classificados como "conteúdo" (posição AX atrasada) |
| **0.3.2 (17:21 UTC)** | **8/9** — bordas direita/superior, divisa parando antes e ultrapassando, travessia rápida, Esc, arraste de conteúdo e Snap Assist (4 candidatas, fecha com Esc) aprovados. Redimensionamento conjunto não rodou: a janela do Safari estava em outro Espaço (AX lista 0 janelas). |

| **0.3.3 (17:29 UTC)** | **13/13 APROVADO** — todos os casos acima + escolha com ↩ no Snap Assist preenchendo exatamente o espaço vazio (sem vão nem sobreposição), inversão Safari/Word e redimensionamento conjunto (ao vivo a meio do arraste e no final). |
| 0.3.4 (17:36 UTC) | 13/15 — resistência na divisa aprovada (empurrar encaixa; continuar empurrando atravessa). Snap Assist abria e fechava sozinho (perda de foco). |
| **0.3.5 (17:40 UTC)** | **11/12** — tudo aprovado, inclusive Snap Assist (abre, Esc fecha, ↩ preenche o espaço exato) e Esc sem encaixe fantasma após remover o Rectangle. Redimensionamento conjunto não rodou: a janela do Safari estava numa mesa não visível do monitor externo (aprovado em 0.3.0 e 0.3.3; código inalterado desde então). |

Observação 0.3.2: o encaixe nativo do macOS continuou agindo apesar de `EnableTilingByEdgeDrag = 0`
(no caso do Esc a janela foi encaixada sem nenhuma escrita do PaneFlow). **Causa encontrada em 0.3.4:
o Rectangle estava aberto**; após removê-lo (0.3.5) o Esc deixa a janela onde estava.

## 0.2.1 — 93 testes automatizados (92 aprovados, 1 pulado)

## Execução — 0.2.0 (2026-10-22)
89 testes: 88 aprovados, 1 pulado (Acessibilidade), 0 falhas. Novas suítes: `SnapZoneDetectorTests` (8),
`SnapStateMachineTests` (9), `SnapCyclingTests` (7), `LinkedResizeTests` (10).

## Execução anterior — 0.1.0 (2026-10-22, macOS 27.0.1, Xcode 27.0)
| Suíte | Testes | Resultado |
|---|---|---|
| CoordinateConverterTests | 7 | ✅ |
| DisplayTopologyTests | 6 | ✅ |
| LayoutEngineTests | 10 | ✅ |
| SplitSolverTests | 9 | ✅ (inclui varredura pseudo-aleatória de 500 casos) |
| WindowEligibilityTests | 2 | ✅ |
| WindowIdentityResolverTests | 8 | ✅ |
| GeometryVerifierTests | 3 | ✅ |
| LatencyStatisticsTests | 2 | ✅ |
| SystemIntegrationTests | 8 | ✅ 7 aprovados, **1 pulado** (`testDiscoveryRequiresAccessibility`: o executor de testes não tem Acessibilidade) |
| **Total** | **55** | **54 aprovados, 1 pulado, 0 falhas** |

Destaque: `testDisplayManagerMatchesCoreGraphics` valida, **nos monitores reais**, que o frame global
calculado a partir do `NSScreen` (AppKit) é idêntico a `CGDisplayBounds` — inclusive para o monitor
externo em `(-1920, -351)`.

## Self-test da Fase 1 (`--self-test`)
Executado dentro do `PaneFlow.app` (via `open`, para que o TCC use a permissão do app):
1. Descobre janelas; escolhe Safari + Word (fallback: duas janelas elegíveis mais à frente).
2. Safari → metade esquerda, Word → metade direita; verifica cada uma por read-back independente.
3. Verifica não sobreposição, idempotência (reaplicar não causa deriva) e a troca de lados.
4. Se houver segundo monitor, move para a metade esquerda dele (coordenadas negativas).
5. Restaura os frames originais (exceto com `--keep`).
Relatório JSON: `$TMPDIR/paneflow-selftest.json` (ou Diagnostics › Run Geometry Self-Test, salvo em
`~/Library/Application Support/PaneFlow/Diagnostics/`). Sem títulos de janelas.

**Estado (2026-10-22 16:56 UTC): APROVADO 11/11 com Safari + Word reais**, ambos no monitor externo
(origem negativa `(-1920, -321)`), todos os vereditos `exact`, frames originais restaurados.

## Ainda não cobertos (planejado)
- Integração AX com geometria real (depende da permissão) — Fase 1.
- Máquina de estados de snap, zonas, detector de arraste — Fase 2.
- Testes de UI, desempenho com 5/15/30/50 janelas, sessões prolongadas — Fases 3–9.
