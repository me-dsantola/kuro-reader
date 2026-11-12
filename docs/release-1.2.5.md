# Release 1.2.5 (build 13)

### Mudanças e Melhorias
- **Correção no CI / Flutter Analyze**:
  - Remoção de injeção indevida da variável `q` em `AdultVaultAdapter` no arquivo `lib/services/mangadex_service.dart`.
  - Escopo da integração do catálogo do Telegram Vault isolado estritamente para `WesternComicsHqAdapter` (categoria de HQs / Quadrinhos Ocidentais).
- **Telegram Vault HQs**:
  - Suporte ao catálogo dinâmico de HQs salvas via bot no canal privado do Telegram.
  - Carregamento seguro assíncrono via `TelegramVaultService`.
