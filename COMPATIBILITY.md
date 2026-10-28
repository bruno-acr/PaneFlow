# Matriz de compatibilidade

Legenda — Implementação: ✅ feito · 🟡 parcial · ⏳ planejado. Validação: ✅ validado em uso real ·
🧪 só testes automatizados · ❌ não validado.

| Funcionalidade | macOS | Permissão | Apps testados | Limitação conhecida | Implementação | Validação |
|---|---|---|---|---|---|---|
| Conversão de coordenadas / multi-monitor | 14+ | — | — (monitores reais: built-in @2x + externo @1x à esquerda/acima) | — | ✅ | ✅ (vs `CGDisplayBounds`) |
| Detecção de mudança de monitores | 14+ | — | — | reconexão/restauração de layouts na Fase 7 | 🟡 | ❌ |
| Descoberta de janelas (AX) | 14+ | Acessibilidade | Safari, Word (9 janelas, 7 elegíveis) | só Space atual na correlação | ✅ | ✅ |
| Correlação AX ↔ CGWindowID | 14+ | (Screen Recording melhora) | — | heurística; ambíguos sem miniatura | ✅ | 🧪 |
| Mover/redimensionar verificado | 14+ | Acessibilidade | Safari, Word | mín./máx. descobertos por read-back | ✅ | ✅ (autoteste 11/11, inclusive coordenadas negativas) |
| Metades / maximizar / centralizar / restaurar (menu) | 14+ | Acessibilidade | nenhum ainda | só janela em foco | ✅ | ❌ |
| Mover para próximo monitor | 14+ | Acessibilidade | nenhum ainda | proporcional à área útil | ✅ | ❌ |
| Catálogo de layouts (13) | 14+ | — | — | sem UI de escolha ainda | ✅ (motor) | 🧪 |
| Solver 1D com mín./máx. | — | — | — | integração com grupos na Fase 5 | ✅ | 🧪 |
| Onboarding de permissões | 14+ | — | — | — | ✅ | ❌ (UI não inspecionada visualmente) |
| Detecção do tiling nativo | 15+ | — | — | chave não documentada (heurística) | ✅ | ✅ (detectou `EnableTilingByEdgeDrag = 1`) |
| Diagnóstico sanitizado | 14+ | — | — | — | ✅ | ❌ |
| Snap por arraste + preview (bordas, cantos, topo) | 14+ | Acessibilidade | Finder (eventos sintéticos) | conflita com tiling nativo ligado | ✅ | ✅ (teste ponta a ponta 0.3.2) |
| Zona na divisa entre monitores (com espera) | 14+ | Acessibilidade | Finder (eventos sintéticos) | exige parar o cursor ~0,2 s | ✅ | ✅ (parando antes e ultrapassando) |
| Redimensionar janelas vizinhas juntas | 14+ | Acessibilidade | Safari + Word (eventos sintéticos, 0.3.0) | atraso visual em apps lentos | ✅ | ✅ |
| Atalhos ⌃⌥ (troca de monitor ao repetir) | 14+ | Acessibilidade | nenhum ainda | conflitos só detectados se outro app registrou | ✅ | 🧪 (lógica de ciclo) |
| Interface em português | 14+ | — | — | — | ✅ | ❌ (não inspecionada visualmente) |
| Snap Assist (seletor após encaixe) | 14+ | Acessibilidade | Finder + Word/Safari (0.3.3): abre, Esc fecha, ↩ escolhe e preenche o espaço exato | sem miniatura para janelas ambíguas | ✅ | ✅ (clique do mouse e miniaturas reais ainda não testados) |
| Inverter janelas (⌃⌥S) | 14+ | Acessibilidade | Safari + Word (0.3.0) | só janelas encostadas na ativa | ✅ | ✅ |
| Miniaturas (ScreenCaptureKit) | 14+ | Gravação de Tela | — | sem permissão: ícone + título | ✅ | ❌ |
| Snap Groups (registro, restauração, troca) | 14+ | Acessibilidade | — | — | ⏳ Fase 5 | ❌ |
