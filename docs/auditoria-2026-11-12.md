# Auditoria de código e releases — 12/11/2026

Escopo: código deste checkout, notas locais de 1.2.0 a 1.2.5, dependências,
testes Dart/Flutter e ferramentas de publicação. Esta revisão não certifica
APKs já publicados nem substitui testes em aparelho físico.

## Correções desta revisão

- Home com destaque de uma obra real do catálogo popular: capa, degradê,
  título, gêneros, sinopse de duas linhas, leitura e favoritos persistentes.
- “Ler Agora” retoma o capítulo salvo ou abre o primeiro capítulo disponível.
  Ausência de capítulos e falhas de rede têm feedback e permitem nova tentativa.
- Fileira “Mangás Populares” com três capas completas e início da quarta em
  celulares; favoritos não são misturados ao ranking da fonte.
- Respostas antigas não substituem uma consulta popular mais nova. Obras
  sensíveis são filtradas imediatamente quando a preferência muda.
- Removidos banner ilustrativo antigo, seu painter e progresso fictício de 12%.
- Tela de recuperação existente conectada à inicialização; eliminada a segunda
  implementação que só sugeria fechar e reabrir o aplicativo.
- Removido `cached_network_image`, sem importação no app,
  e 14 dependências transitivas. `photo_view` permanece: fornece zoom paginado.
  `cupertino_icons` foi preservado: a compilação web detectou referências
  implícitas do Flutter à fonte de ícones dos controles adaptativos.
  O registro de plugins macOS foi regenerado sem `sqflite_darwin`.
- Catálogo HQ incluído como asset. Um arquivo local ausente ou com JSON
  inválido não bloqueia a cópia incluída. Falha ao gravar cache não interrompe
  a listagem. Arquivos com identificador ausente são ignorados.
- A descoberta de capítulos de HQs do Telegram usa o catálogo pelo ID; não
  tenta encontrar essas obras por título no MangaDex. Falha do MangaDex não
  elimina os resultados locais de HQs.
- Corrigida a expansão dos feeds: páginas extras em inglês são buscadas mesmo
  quando existe tradução parcial em português. As listas continuam separadas
  até a desduplicação, garantindo prioridade PT-BR.
- Removido o token embutido do bot do Flutter e do uploader. O uploader usa
  `TELEGRAM_BOT_TOKEN` e `TELEGRAM_CHANNEL_ID` do ambiente e valida sua presença.
  A credencial antiga continua no histórico Git e deve ser revogada pelo dono.

## Promessas de cada release

“Presente” significa que há implementação e evidência automatizada relacionada;
não garante disponibilidade de provedores, compatibilidade com todos os aparelhos
ou execução de cada fluxo no Android real.

| Release / promessa | Resultado da revisão | Implementação / evidência |
| --- | --- | --- |
| 1.2.0: logo, busca, ordenação, filtros e menus ao rolar | Presente | `home_tabs.dart`, `catalog_sort.dart`, `scroll_chrome_controller.dart`; testes `catalog_order`, `catalog_content_filter`, `catalog_request_state`, `scroll_chrome`, `reading_ui` |
| 1.2.0: vidro opcional, contraste e redução de movimento | Presente | `appearance_controller.dart`, `frosted_surface.dart`, `adaptive_app_shell.dart`; testes `appearance_controller`, `reading_ui` |
| 1.2.0: cache, renovação de páginas e tentativa manual | Presente | `reader_image_session.dart`, `reader_page_provider.dart`, `reader_screen.dart`; testes `reader_image_session`, `webtoon_view` |
| 1.2.0: downloads verificados, requisições compartilhadas e exclusão | Presente | `download_manager.dart`, tela Offline; testes `download_manager`, `reading_privacy_regression` |
| 1.2.0: histórico e métricas protegidos | Presente | filas de escrita e validação em `storage_service.dart`; testes `storage_service`, `backup_codec` |
| 1.2.0: feedback Android de bateria/rede | Presente, aparelho pendente | canal `yomi/device_state` em `MainActivity.kt`, `device_state_service.dart`; testes `device_state` simulam o canal |
| 1.2.0: APKs assinados e verificados | Ferramentas presentes; artefatos publicados não certificados aqui | `stable_release.yaml`, scripts de assinatura/verificação; testes Python de identidade, ABI, versão e certificado |
| 1.2.1: tema por obra e perfil/Blobatar | Presente | `profile_palette_service.dart`, detalhes, perfil e `yomi_blobatar_studio.dart`; testes `reading_ui` |
| 1.2.1: download completo e biblioteca offline | Presente para capítulos de imagens | `manga_detail_screen.dart`, `DownloadManager.downloadManga`, `StorageService.ensureInLibrary`; testes `download_manager`, `reading_privacy_regression` |
| 1.2.1: privacidade redesenhada | Presente | `privacy_shield.dart`; teste de proteção de rotas e retomada em `reading_privacy_regression` |
| 1.2.1: backup automático entre reinstalações | Parcial / condicionado à plataforma | canal Android, MediaStore, `YomiBackupAgent`, cópia desktop e restauração existem; comportamento do SO, permissões e reinstalação precisam de aparelho. Não é garantia universal nem sincronização própria em nuvem |
| 1.2.1: notificações ativas | Sininho local presente | `favorite_updates_service.dart`, tela de novidades e perfil. Não há notificações push nem verificação periódica em segundo plano |
| 1.2.1: URLs expiradas e CDNs alternativas | Presente, disponibilidade externa variável | sessão de imagens e URLs candidatas em `manga_models.dart`; testes `reader_image_session`, `manga_metadata_regression` |
| 1.2.2: prioridade PT-BR e preenchimento EN sem duplicatas | Presente, com falha corrigida nesta revisão | `discoverAllSourcesForManga`; novo teste usa feeds simulados de 1001 entradas, PT-BR parcial e páginas EN adicionais |
| 1.2.2: todas as obras completas / sem lacunas | Não pode ser garantido | Só há capítulos disponibilizados pela fonte nos idiomas consultados. Não se criam traduções ou capítulos ausentes. A busca inicial é limitada a 1500 entradas por idioma, com paginação adicional |
| 1.2.3: substituição de `ScrollCacheExtent.pixels` | Presente | usa APIs de lista compatíveis com o SDK instalado. “Todas as versões do Flutter” não é uma garantia verificável; o projeto tem uma versão de SDK de referência no CI |
| 1.2.3: Chrome e Android sem erros | Exige compilação por plataforma | análise Dart e testes não equivalem a compilar ou executar nos dois alvos; ver seção de validação |
| 1.2.4: HQs do Telegram na aba HQs e capítulos | Listagem implementada e corrigida | asset, serviço e adaptador HQ; testes `telegram_vault` cobrem APK sem arquivo no diretório, detalhe de obra salva e queda do MangaDex |
| 1.2.4: leitura e download de PDF/CBR/ZIP | **Não implementado** | o leitor e o gerenciador de downloads trabalham com sequências de imagens; faltam download de documentos, extração/rasterização e integração ao leitor |
| 1.2.5: correção da variável `q` no adaptador adulto | Presente | integração fica no adaptador HQ; análise estática verifica nomes indefinidos |
| 1.2.5: catálogo dinâmico e carregamento assíncrono | Parcial | carrega asset ou arquivo local. Não existe mecanismo de buscar automaticamente o JSON atualizado do computador/canal para o celular |

## Uso de código e dependências

A análise estática identifica imports e membros privados sem uso. Também foi
conferido o grafo de imports de `lib`: a tela de recuperação estava desconectada
e foi integrada. `scroll_chrome_bar.dart` era exercitado apenas por testes e
foi movido para `test/support`; a navegação atual implementa a animação
diretamente em `main.dart`. Isso não é evidência de que cada ramo público do
projeto é executado.

`TelegramVaultService.resolveDirectDownloadUrl` é uma função preparatória sem
chamador no fluxo atual de leitura. Não é evidência de leitura de documentos.
O notifier sem consumidores e o ID de canal sem uso no Flutter foram removidos.
Os nomes legados de fontes e a biblioteca Blobatar foram preservados para não
quebrar dados salvos e personalização existente.

## Configuração do uploader

No PowerShell, configure `TELEGRAM_BOT_TOKEN` e `TELEGRAM_CHANNEL_ID` no ambiente
da sessão antes de executar `python scripts/upload_hqs_telegram.py CAMINHO`.
Não grave os valores em arquivos versionados. O ledger e o catálogo em produção
não foram regravados por esta auditoria; já tinham alterações do usuário.

O Flutter não precisa do token para listar obras. O método preparatório de
resolução aceita `--dart-define=TELEGRAM_BOT_TOKEN=...`, mas isso **não protege**
segredos dentro de um APK. Uma futura distribuição de leitura do Vault deve
resolver downloads por um serviço intermediário sem expor o token do bot.

## Validação

- Baseline anterior às mudanças: 105 testes Flutter e 19 testes Python passaram.
- Fonte real: consulta pública MangaDex retornou cinco obras e as cinco capas
  foram baixadas para inspeção visual. Isso não certifica todos os idiomas,
  provedores, rotas CDN ou capítulos.
- Testes novos verificam favoritos, rota de “Ler Agora”, início da quarta capa,
  rolagem horizontal, tela de 320 px com texto 2×, catálogo inválido, ausência
  de arquivo no APK, falha do MangaDex e preenchimento de feeds EN/PT-BR.
- `flutter analyze --no-pub`: sem problemas.
- `flutter test --no-pub`: **112 testes passaram** na revisão final.
- `python -m unittest discover -s scripts/tests -v`: **19 testes passaram**.
- `python -m py_compile scripts/upload_hqs_telegram.py`: compilação válida.
- `git diff --check`: sem erros de whitespace.
- Android: `flutter build apk --debug --no-pub` passou. APK em
  `build/app/outputs/flutter-apk/app-debug.apk`, com assinatura de depuração.
  Não houve instalação em aparelho nem certificação de uma build de produção.
- O Java padrão deste computador era 25.0.4 e falhou no Gradle. A compilação
  passou com o Java 17 já instalado, selecionado somente no processo:

  ```powershell
  $env:JAVA_HOME = 'C:\Program Files\Eclipse Adoptium\jdk-17.0.21.9-hotspot'
  $env:GRADLE_OPTS = '-Dorg.gradle.java.home="C:/Program Files/Eclipse Adoptium/jdk-17.0.21.9-hotspot"'
  flutter build apk --debug --no-pub
  ```

- Web: `flutter build web --no-pub` passou, incluindo o dry run de Wasm;
  saída em `build/web`, sem aviso de fonte de ícones ausente.
- Prévia renderizada por teste com fontes Flutter e capas reais em
  `build/home-preview/home-billboard.png`, inspecionada visualmente.
- Grafo de imports: nenhum arquivo Dart em `lib`, além de `main.dart`, ficou
  sem referência de importação/exportação por outro arquivo de produção.
  Isso não equivale a cobertura de execução de todos os membros públicos.
- Nenhum token de bot embutido foi encontrado nos fontes Dart e scripts Python.
- Não houve publicação nem alteração de releases remotas.

## Pendências reais

1. Integrar um leitor de documentos e downloads de PDF/CBR/CBZ/ZIP ao Vault.
2. Definir distribuição remota do catálogo para o app receber novos uploads sem
   recompilar. Atualizar o JSON no computador não atualiza APKs já instalados.
3. Revogar a credencial antiga e provisionar a substituta fora do código.
4. Validar instalação, reinstalação/backup, bateria, rede, fluidez e leitor em
   aparelho Android físico. Validar assinatura antes de publicar uma release.
