# Release e distribuição

Distribuição direta (fora da Mac App Store: o App Sandbox é incompatível com controle de janelas via AX).

## Estado
| Item | Estado |
|---|---|
| Hardened Runtime | ✅ habilitado em `build-app.sh` (`--options runtime`), sem exceções de entitlements |
| Code signing | ⚠️ ad-hoc por padrão; nenhuma identidade Developer ID neste Mac |
| Notarização | ⏳ requer Developer ID Application + `notarytool` |
| DMG | ⏳ Fase 9 |
| Launch at Login (`SMAppService.mainApp`) | ⏳ Fase 8 |
| Atualização segura | ⏳ não implementada (se for, com assinatura EdDSA e HTTPS) |
| Arquitetura | arm64 (máquina de build). Universal: `swift build --arch arm64 --arch x86_64` — não testado |

## Procedimento planejado (Fase 9)
```bash
export PANEFLOW_SIGN_IDENTITY="Developer ID Application: <Nome> (<TEAMID>)"
CONFIG=release ./scripts/build-app.sh
# codesign com --timestamp (remover --timestamp=none do script para release)
ditto -c -k --keepParent build/PaneFlow.app PaneFlow.zip
xcrun notarytool submit PaneFlow.zip --keychain-profile <perfil> --wait
xcrun stapler staple build/PaneFlow.app
```
Credenciais de notarização ficam no Keychain (`notarytool store-credentials`), nunca no repositório.
