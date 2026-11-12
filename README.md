# YOMI — Kuro Reader

Leitor pessoal de mangás, manhwas e quadrinhos feito em Flutter.
A versão do checkout está definida no `pubspec.yaml`.
A versão efetivamente publicada aparece em [Releases](../../releases).

## Experiência

- Início com destaque rotativo, paleta por obra, capas populares e leitura recente;
- Logo centralizada em Explorar, com busca, filtros e ordenação no mesmo bloco;
- Ordenação por recentes, populares ou título, preservando a busca;
- Filtros por categoria, com inclusão/exclusão e aplicação explícita;
- Biblioteca, central local de atualizações, perfil e estatísticas;
- Leitor webtoon e paginado com recuperação de páginas e cache temporário limitado;
- Downloads verificados para leitura offline, com retomada e confirmação de exclusão;
- Feedback de bateria, ausência de internet e respostas lentas no Android;
- Aparência AMOLED clássica ou vidro suave, com recolhimento de menus configurável.
- Modo offline automático com aviso persistente, acesso à Biblioteca e Perfil;
- Downloads em **Biblioteca → Baixados**, com verificação das páginas locais;
- Reconexão com atualização do catálogo e restauração dos demais menus;
- Transições rápidas de fade/deslizamento e menu do leitor com cores da obra;
- Mais cores de perfil/Blobatar, ajuste contínuo de matiz e reação ao toque;
- Avisos e erros em pop-ups com contraste e botão para fechar.
- Biblioteca com busca, chips de leitura, continuação e progresso por obra;
- Banners de perfil: Horizonte distante, Lua vermelha e Portal da noite.

Em **Perfil → Configurações → Aparência e movimento**, personalize o vidro
suave e o recolhimento de menus. Ao descer, os controles liberam espaço; ao
subir, voltam. No leitor paginado, toque para mostrar ou ocultar a barra.
O alto contraste e a economia de bateria removem o desfoque. A preferência
de redução de movimento do aparelho desativa as transições animadas.

MangaDex é a fonte efetiva de páginas. AniList, Jikan/MAL e Kitsu fornecem
metadados e descoberta. O adaptador legado chamado ComicK usa Kitsu/MangaDex;
não há integração direta com ComicK. A categoria HQ combina consultas do
MangaDex com o catálogo local Telegram Vault. O catálogo acompanha o APK;
uploads posteriores exigem atualizar o catálogo distribuído. A listagem de
documentos do Vault está disponível, mas a leitura/download de PDF/CBR/ZIP
ainda não está integrada. A categoria 18+ consulta o MangaDex.
A disponibilidade depende das fontes e dos idiomas oferecidos por elas.

## Instalar a versão estável

Baixe o APK da [Release publicada](../../releases), de acordo com o aparelho:

| Arquivo | Uso |
| --- | --- |
| `YOMI-1.2.0-arm64-v8a.apk` | Android ARM64, comum em celulares atuais |
| `YOMI-1.2.0-armeabi-v7a.apk` | Android ARM de 32 bits compatível |
| `YOMI-1.2.0-x86_64.apk` | Emuladores e aparelhos Android x86 de 64 bits |

O pacote estável é `com.kuroreader.kuro_reader`. A Beta usa
`com.kuroreader.kuro_reader.beta`, com armazenamento separado. Exporte o
backup na Beta e importe na estável para migrar perfil, biblioteca e histórico.
As imagens offline precisam ser baixadas novamente.

Se uma instalação estável antiga usava certificado de depuração, o Android
não permitirá atualizá-la com a nova chave de produção. Nesse caso, exporte
e guarde o backup **antes de desinstalar** a instalação antiga. Preserve a
mesma chave de produção em todas as atualizações futuras.

## Desenvolvimento e validação

Flutter **3.47.9**, Java 17 e Android SDK para compilar Android:

```bash
flutter pub get
flutter analyze
flutter test
python3 -m unittest discover -s scripts/tests -v
flutter run
```

Os testes cobrem home/favoritos/rolagem, navegação/ordenação/filtros, leitura e geometria, troca de
modo, recuperação de páginas, caches, downloads, backup, privacidade e
estados de bateria/rede. A revisão detalhada está em
[docs/stable_review.md](docs/stable_review.md).
O confronto das promessas das releases 1.2.0–1.2.5 com o código atual está em
[docs/auditoria-2026-11-12.md](docs/auditoria-2026-11-12.md), incluindo pendências.
O comportamento do modo offline e das novas preferências está em
[docs/offline-e-personalizacao.md](docs/offline-e-personalizacao.md).
Os detalhes da Biblioteca reformulada, dos banners e da busca estão em
[docs/biblioteca-banners-e-busca.md](docs/biblioteca-banners-e-busca.md).

A fluidez, os provedores externos e os sensores reais precisam ser conferidos
em aparelho físico; testes com fontes simuladas não substituem essa verificação.
Para medir desempenho use `flutter run --profile`.

## Publicação

O workflow `stable_release.yaml` analisa e testa o projeto, compila três APKs
assinados e verifica identidade, versão, arquitetura e certificado antes de
gerar checksums e `release.json`. Na branch de validação ele guarda artefatos;
na `main`, publica uma Release versionada sem marcação de pré-lançamento.
O workflow `build_apk.yaml` atende exclusivamente à branch Beta.

A assinatura estável exige quatro secrets do repositório:
`YOMI_KEYSTORE_BASE64`, `YOMI_STORE_PASSWORD`, `YOMI_KEY_ALIAS` e
`YOMI_KEY_PASSWORD`. O proprietário pode configurar sua chave local pelo
[assistente PowerShell](scripts/setup-stable-signing.ps1), após revisar o script.
Java e GitHub CLI autenticado são necessários. O assistente não substitui uma
chave existente. Guarde uma cópia privada do keystore e da senha.

Nunca inclua chaves ou senhas em commits. Builds locais usam
`YOMI_KEYSTORE_PATH`, `YOMI_STORE_PASSWORD`, `YOMI_KEY_ALIAS` e
`YOMI_KEY_PASSWORD`. Certificados Android Debug são rejeitados pela validação
estável. Os códigos Android dos APKs separados por ABI usam o prefixo padrão
do Flutter: 1008, 2008 e 4008 para o build de origem 8.

## Backups e limites

O backup manual contém perfil, favoritos, preferências e histórico, sem as
imagens baixadas. É JSON codificado em Base64, **sem criptografia**. A
importação valida todas as seções antes de gravar e mantém um diário de
recuperação para reverter gravações interrompidas. Não compartilhe seu backup.

O backup automático Android está habilitado com agente próprio e cópia local;
a recuperação após reinstalação depende do sistema e do acesso ao arquivo.
Exporte uma cópia manual antes de desinstalar. No desktop há cópia no perfil
do usuário; a versão web não oferece esse mesmo backup de arquivos.
O tráfego HTTP sem criptografia está desabilitado.
Conteúdo sem classificação confirmada fica oculto no modo
seguro. Não há sincronização em nuvem, notificações automáticas de capítulos
ou fila avançada de downloads com política de Wi-Fi.

O cache temporário de leitura é limitado por sessão e pode ser descartado pelo
sistema. Use downloads para garantir acesso offline. Imagens ou capítulos
substituídos pela fonte podem alterar a correspondência da posição salva.
