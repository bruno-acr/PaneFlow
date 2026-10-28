# Registro de progresso

Para retomar em outra sessão: leia este arquivo, depois ARCHITECTURE.md e KNOWN_LIMITATIONS.md.

## Fase 0 — Pesquisa e viabilidade ✅ (2026-10-22)
Resultados em ARCHITECTURE.md §6–§8. Pontos-chave: mínimo macOS 14; detecção de arraste híbrida
("janela se moveu e tamanho constante"); correlação AX↔CG por múltiplos sinais (sem
`_AXUIElementGetWindow`); Input Monitoring desnecessário; conflito real com o tiling nativo deste Mac.

## Fase 1 — Foundation ✅ aceite validado (2026-10-22, 16:56 UTC)
Autoteste com Safari + Word reais: **11/11 verificações aprovadas**, todas com veredito `exact`.
Ambas as janelas estavam no monitor LG (coordenadas negativas): metades esquerda/direita,
sem sobreposição, idempotência, troca de lados, ida ao MacBook e restauração dos frames originais.
Permissão resolvida com `tccutil reset Accessibility app.paneflow.PaneFlow` + nova concessão
(a entrada antiga apontava para uma assinatura ad-hoc anterior).

### Histórico da implementação
- Compila sem erros e **sem warnings** (Swift 6.4, modo Swift 6). Build release assinado ad-hoc com
  Hardened Runtime: `codesign --verify --strict` ok.
- Testes: 55 executados — 54 aprovados, 1 pulado (precisa de Acessibilidade), 0 falhas.
- App executado: inicia, cria o item na barra de menus, abre o onboarding; CPU 0,0 % e ~74 MB RSS em repouso.
- Self-test executado **sem** permissão → falha controlada (esperado).
- **Critério de aceite ("mover Safari e Word com precisão, com operações verificáveis") NÃO
  validado**: o PaneFlow ainda não tem permissão de Acessibilidade neste Mac, e conceder exige ação
  do usuário em Ajustes do Sistema.

### Para fechar a Fase 1
1. (Recomendado) Configurar `PANEFLOW_SIGN_IDENTITY` estável (DEVELOPMENT.md) e rebuildar.
2. `open build/PaneFlow.app` → Grant Access… → ativar PaneFlow em Privacidade e Segurança › Acessibilidade.
3. Abrir Safari e Word (uma janela cada) e rodar `./scripts/self-test.sh`.
4. Se aprovado, marcar Fase 1 ✅ aqui e em COMPATIBILITY.md e registrar p50/p95 em PERFORMANCE.md.
5. Recomendado ao usuário: desligar "Arrastar janelas para as bordas da tela para organizá-las"
   antes da Fase 2.

## Iteração 0.2.0 — pedidos do usuário (2026-10-22) 🟡 implementada, não validada em uso real
Pedidos: interface em português; encaixe ruim na divisa com o monitor estendido; ajustar
proporções arrastando o meio; ícone. Implementado (ver CHANGELOG 0.2.0). Partes das Fases 2, 5 e 8
foram adiantadas. Testes: 89 (88 aprovados, 1 pulado). **Arraste, redimensionamento conjunto e
atalhos não foram exercitados em janelas reais**: o PaneFlow não tem Acessibilidade e cada
reinstalação ad-hoc invalida a permissão.

## Iterações 0.2.1 → 0.3.3 (2026-10-22) ✅ validadas com teste ponta a ponta
Teste de arraste com eventos de mouse sintéticos: **13/13 aprovado** na 0.3.3 (ver TESTING.md).
Achado-chave (ARCHITECTURE.md §6.2): no macOS 27, arrastes pela barra de título não entregam
`leftMouseDragged`/`leftMouseUp` a monitores globais e a posição AX atrasa; o rastreador amostra
cursor/botão/Esc e lê limites do window server enquanto o botão está pressionado.

## Próximo passo
1. Uso real pelo usuário (mouse físico) e retorno.
2. ✅ "Encaixe fantasma" era o Rectangle (removido a pedido do usuário em 0.3.5; PaneFlow agora avisa).
3. Miniaturas reais: Gravação de Tela concedida em 0.3.5; captura não verificada visualmente.
4. Assinatura estável (cada reinstalação ad-hoc exige `tccutil reset` + nova concessão).
5. Fases restantes: Snap Groups persistentes/restauração, layouts personalizados, Settings, Launch at Login.
