# Desenvolvimento

## Estrutura
```
Package.swift                 SwiftPM, macOS 14+, Swift 6 (concorrência estrita)
Sources/PaneFlowCore          lógica pura (sem AppKit) — geometria, layouts, solver, identidade
Sources/PaneFlowSystem        integração com o SO — AX, monitores, permissões, logs
Sources/PaneFlow              app residente — coordenador, menu bar, onboarding, self-test
Tests/PaneFlowCoreTests       testes unitários
Tests/PaneFlowSystemTests     testes de integração (pulam o que exige permissão)
Resources/Info.plist          LSUIElement, LSMinimumSystemVersion 14.0
Resources/PaneFlow.entitlements  Hardened Runtime sem exceções, sem sandbox
scripts/                      build-app.sh, test.sh, self-test.sh
```

## Pasta de build fora do iCloud
Se o projeto estiver numa pasta sincronizada pelo iCloud Drive (ex.: `~/Documents`), o File Provider
adiciona atributos estendidos (`com.apple.FinderInfo`, `com.apple.fileprovider.fpfs#P`) e o
`codesign` rejeita os bundles (`resource fork, Finder information, or similar detritus not allowed`)
— inclusive os `.xctest` de `swift test`. Por isso **todos os scripts usam `--scratch-path
~/Library/Caches/PaneFlow/build`** e o app é montado em `~/Library/Caches/PaneFlow/app`
(`build/PaneFlow.app` é um link simbólico). Prefira os scripts a `swift build`/`swift test` diretos.

## Assinatura e permissão de Acessibilidade
A concessão TCC fica vinculada à assinatura. Com assinatura ad-hoc (`-`, padrão quando não há
identidade), **cada rebuild faz o macOS esquecer a permissão** (o app aparece na lista, mas não
funciona). Opções:
1. Recomendado: Xcode › Settings › Accounts › adicionar Apple ID → "Apple Development"; depois
   `export PANEFLOW_SIGN_IDENTITY="Apple Development: Seu Nome (XXXXXXXXXX)"`.
2. Sem conta: crie um certificado de assinatura de código local em Acesso às Chaves
   (Assistente de Certificado › Criar um Certificado › tipo "Assinatura de Código") e use seu nome em
   `PANEFLOW_SIGN_IDENTITY`.
3. Ad-hoc: após cada rebuild, remova o PaneFlow da lista de Acessibilidade ("–") e conceda de novo.

## Xcode
`xed Package.swift` abre o pacote no Xcode (esquema `PaneFlow`). Para depurar o app com permissões,
prefira o bundle gerado pelo script (o binário solto herda o TCC do processo pai).

## Convenções
- Coordenadas internas: **globais CG/AX** (origem no canto sup. esq. do monitor principal).
  Converter apenas via `CoordinateConverter`.
- Nada de chamadas AX na main thread: use `AccessibilityExecutor`.
- Títulos de janelas só em logs com `privacy: .private`; nunca em relatórios.
- Novas decisões de geometria vão para `PaneFlowCore` com testes.
