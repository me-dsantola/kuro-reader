# Modo offline, navegação e personalização

## Comportamento

- Sem conexão, a navegação oferece somente **Biblioteca** e **Perfil**. Se a
  pessoa estava em Início, Explorar ou Ajustes, é direcionada à Biblioteca.
- Um aviso persistente informa que o app está offline e com funcionalidades
  reduzidas. Os atalhos de catálogo/ajustes do perfil ficam desabilitados.
- A Biblioteca reúne as abas **Minha Biblioteca** e **Baixados**. Não há mais
  um item Offline separado na barra principal.
- A tela de downloads, as listas, o perfil e os capítulos salvos usam Hive e
  arquivos locais. Metadados em cache não são apresentados como downloads.
- A abertura verifica se todas as páginas indexadas existem e são imagens
  válidas. Arquivos incompletos não são anunciados como download completo.
- O leitor não tenta baixar páginas novas enquanto está offline. Páginas já
  carregadas na sessão continuam disponíveis. Um capítulo completamente
  baixado pode ser lido após fechar e reabrir o app.
- Na reconexão, o app habilita os quatro menus, reinicia o agregador do
  catálogo, recria a home para atualizar os populares e atualiza a Biblioteca.
  O menu em uso é preservado. O leitor tenta novamente carregar um capítulo
  que não tinha páginas disponíveis quando a conexão retorna.
- O Android publica eventos de rede validada, bateria e economia de energia.
  O estado também é consultado ao iniciar e retomar o app. Os canais de eventos
  e de consulta têm nomes distintos para não sobrescrever um ao outro.
- Nas demais plataformas, `connectivity_plus` detecta disponibilidade de rede.
  Uma interface Wi-Fi conectada não garante acesso à internet; erros e timeouts
  continuam tratados. Essa limitação é documentada pelo
  [plugin](https://pub.dev/packages/connectivity_plus/versions/6.1.5).
- Downloads persistentes de páginas são um recurso das versões nativas; o
  navegador continua com os limites de armazenamento da versão web.

## Interface

- Mudanças de menu aplicam fade e deslizamento vertical de 180 ms. O
  `IndexedStack` preserva os estados das abas. Redução de movimento e economia
  desativam o efeito; também há uma preferência para desativá-lo manualmente.
- O menu do leitor usa a paleta da capa para ícones, informações e bordas;
  quando a capa não está disponível, usa a paleta local do perfil.
- Em **Perfil → Configurações → Aparência, privacidade e movimento**, há
  controles funcionais de vidro/AMOLED, transições, cores do leitor pela obra,
  privacidade e recolhimento de menus. As novas preferências são validadas,
  exportadas e restauradas nos backups.
- O editor do perfil oferece 16 cores de destaque; o Blobatar tem 17 matizes
  prontas, ajuste contínuo de 0–360° e controle da reação ao toque. Formato,
  expressão, moldura, nome, seed e animação continuam disponíveis.
- Gravações automáticas do editor são ordenadas para uma escolha antiga não
  sobrescrever a mais recente. A opção de reação ao toque faz parte do perfil
  salvo; perfis antigos mantêm o comportamento anterior.
- Avisos e erros antes enviados ao `ScaffoldMessenger` agora usam um popup
  único, com fundo escuro, borda/ícone, semântica de anúncio e botão de fechar.
  Ações dos avisos são preservadas. O popup desaparece após seis segundos e
  libera seus temporizadores quando a interface é desmontada.

## Verificação

Os testes de `offline_mode_test.dart` cobrem perda/retorno de conexão, menus
permitidos, atualização da home, uso exclusivo de downloads na descoberta,
leitura local sem HTTP, páginas em cache, canais Android, cores do leitor,
persistência do Blobatar e pop-ups. `appearance_controller_test.dart` cobre
restauração das novas preferências no backup. Os resultados da suíte completa,
da análise estática e das compilações foram conferidos na revisão:

- **121 testes Flutter passaram** na suíte completa.
- **19 testes Python passaram** nas ferramentas de release.
- `flutter analyze --no-pub`: sem problemas.
- `flutter build apk --debug --no-pub`: compilação Android concluída, incluindo
  o código Kotlin dos eventos de rede. APK em
  `build/app/outputs/flutter-apk/app-debug.apk`, com assinatura de depuração.
- `flutter build web --no-pub`: compilação concluída, incluindo dry run Wasm.
- `git diff --check`: sem erros de whitespace.

O commit inclui a implementação da home e a limpeza da revisão anterior.
O catálogo e o ledger que estão sendo atualizados pelo uploader foram
preservados como alterações locais e não foram incluídos no commit.

A validação automática não substitui testar modo avião, alternância Wi-Fi/dados,
retomada após segundo plano e leitura de capítulos longos em aparelho físico.
O leitor de PDF/CBR/ZIP do Telegram continua sendo uma pendência separada.
