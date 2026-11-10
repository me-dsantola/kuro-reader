# YOMI — Kuro Reader

Leitor pessoal de mangás, manhwas e quadrinhos feito em Flutter. A versão
**1.1.3 (build 5)** é a candidata Beta para validação antes do merge na `main`.

## Experiência

- Início com leituras recentes e retomada do capítulo/página;
- Pesquisa de obras em provedores de catálogo e leitura;
- Biblioteca de favoritos com central local de atualizações;
- Leitor webtoon e paginado, com posição persistida;
- Download de capítulos para acesso offline;
- Perfil, estatísticas e backup manual local.

**Fontes:** MangaDex é a principal fonte efetiva de páginas. AniList, Jikan/MAL
e Kitsu são usados para metadados e descoberta. O adaptador chamado ComicK
ainda usa Kitsu/MangaDex e **não representa uma integração direta com o ComicK**.
As seções HQ e 18+ usam filtros/consultas do MangaDex; não são bibliotecas
independentes. A disponibilidade de títulos/capítulos depende das APIs,
idiomas e permissões dos provedores.

## Testar a Beta

1. Abra [GitHub Actions](../../actions/workflows/build_apk.yaml) na branch
   `refactor/kuro-reader-v2`.
2. Abra a execução mais recente concluída com sucesso.
3. Baixe o artefato `KuroReader-Beta-Release-Android-APK`, extraia o ZIP e
   instale o APK ARM64 no Android.
4. O aplicativo usa o identificador `com.kuroreader.kuro_reader.beta`,
   separado da versão estável. **O APK Beta Release é assinado com uma chave
   de depuração exclusivamente para testes internos**.
5. Confira busca PT-BR, filtros, favoritos, downloads, modo avião,
   retomada webtoon/paginada, central de atualizações e backup/restauração.

Antes de instalar novas builds, faça backup manual dos dados importantes.
As versões estável e Beta têm armazenamento Android separado.

## Desenvolvimento e validação

Requer Flutter com Dart compatível com `pubspec.yaml` e Android SDK.

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter run
```

Para medir a fluidez de verdade use um aparelho físico em **Profile**,
não Debug:

```bash
flutter run --profile
```

O workflow `.github/workflows/build_apk.yaml` exige análise e testes antes
de gerar um APK. A branch `main` só deve receber a versão após testes
manuais de regressão.

## Backups e privacidade

O backup manual inclui perfil, favoritos, preferências e histórico, mas **não
inclui os arquivos de imagem baixados**. O conteúdo é JSON codificado em
Base64; **não há criptografia**. Não compartilhe o código publicamente,
principalmente se sua biblioteca inclui títulos sensíveis.

O backup automático do Android e tráfego HTTP sem criptografia estão
desabilitados. Utilize o backup manual antes de desinstalar ou limpar dados.
A importação verifica a estrutura antes de gravar e mescla chaves existentes,
mas não é uma transação atômica caso falte espaço ou ocorra erro de disco.

## Assinatura da versão estável

**Nunca distribua publicamente um APK assinado com chave de debug.** A
compilação estável utiliza uma chave de produção própria, configurada fora
do repositório. Os quatro secrets abaixo são necessários para o GitHub
Actions publicar a variante estável após o merge:

- `YOMI_KEYSTORE_BASE64`: arquivo JKS codificado em Base64;
- `YOMI_STORE_PASSWORD`: senha do keystore;
- `YOMI_KEY_ALIAS`: identificador da chave;
- `YOMI_KEY_PASSWORD`: senha da chave.

Nenhum segredo nem arquivo JKS deve ser commitado. Para builds locais de
Release estável, as variáveis de ambiente correspondentes são:
`YOMI_KEYSTORE_PATH`, `YOMI_STORE_PASSWORD`, `YOMI_KEY_ALIAS` e
`YOMI_KEY_PASSWORD`.

## Limitações conhecidas

- A posição webtoon é restaurada por deslocamento vertical em pixels: pode
  variar se as imagens forem substituídas ou mudarem de dimensões.
- Alguns provedores são apenas de metadados, não de capítulos legíveis.
- Não há notificações Android automáticas nem sincronização em segundo plano.
- Download retoma arquivos parciais, mas a fila avançada e política de Wi-Fi
  precisam de uma implementação posterior.
- Este projeto ainda requer validação de licenças, atribuição e limites de
  cada provedor antes de qualquer distribuição pública.
