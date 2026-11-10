# Beta 1.1.2+4 — leitura e harmonização visual

Solicitação: saltos na rolagem mostrados em `Bug.mp4`, harmonização do Início,
transparência das barras e substituição do relógio do catálogo.

## Correção do leitor

As imagens offline não reservavam altura antes da decodificação. Ao sair da
tela, seus widgets eram reciclados; a recriação podia voltar a ter altura zero.
O cache de proporções existente não era preenchido. Assim, o comprimento da
lista mudava durante a rolagem, inclusive sem acesso à internet.

- As dimensões codificadas das páginas locais são lidas antes de exibir a lista,
  sem decodificar o capítulo inteiro em bitmaps de uma só vez.
- A geometria pertence ao capítulo; a lista recebe a altura de cada página
  independentemente do estado do widget de imagem.
- Carregamento, falha, nova tentativa e reciclagem mantêm o espaço reservado.
- Páginas online informam suas dimensões por um único fluxo de imagem.
  Proporções novas são aplicadas ao terminar a rolagem, preservando a página e
  a posição relativa no topo da tela.
- Imagens locais também têm limite de resolução de decodificação para a tela.
- O arquivo local completo continua tendo prioridade mesmo com internet.
- A alternância de modo usa a página atual, e a troca de capítulo preserva o
  modo imersivo em vez de restaurar barras do sistema do leitor anterior.

Erros externos de rede/CDN e arquivos locais danificados ainda podem ocorrer;
a correção evita que esses estados alterem a altura da página e causem saltos.

## Interface

- Início: arte Torii/Sakura, cartão de leitura com capa e progresso, ação de
  continuar, atalhos e novidades nas superfícies AMOLED/Enso/Sakura.
- Barras do leitor e do catálogo: efeito translúcido com gradiente e blur
  restrito à área da barra. Alto contraste usa uma superfície opaca.
- A barra do leitor separa título e ações em duas linhas, usa os recuos do
  sistema e se esconde por sua altura real; movimento reduzido é respeitado.
- O relógio foi substituído por **Ordenar**, com **Padrão do catálogo** e
  **Título (A–Z)**. A ordenação atua nos resultados carregados, sem consultar
  novamente as fontes, reiniciar a paginação ou perder a posição de rolagem.
- O cabeçalho deixa de receber o tom de elevação padrão do Material ao rolar.
- A apresentação dos catálogos distingue metadados de leitura MangaDex.

## Verificação

Executar `flutter pub get`, `flutter analyze --no-fatal-infos`, `flutter test`
e o workflow Beta Release ARM64. A suíte local tem 56 testes aprovados.
Os testes novos verificam geometria,
dimensões locais, imagens atrasadas/indisponíveis, reciclagem de 24 páginas,
âncora de leitura, ordenação sem novas consultas, fonte ampliada e tela estreita.
Prévias de widgets foram renderizadas com conteúdo de teste para conferir o
visual; isso não equivale a uma medição em aparelho Android.

## Validação em aparelho

1. Abrir o mesmo capítulo baixado do vídeo com modo avião e rolar rapidamente
   até o fim, voltando ao início várias vezes. As páginas não devem colapsar.
2. Repetir com internet ligada; um capítulo completamente baixado deve continuar
   usando os arquivos locais.
3. Testar um capítulo não baixado, inclusive com rede lenta e falha de página.
   Conferir se a nova tentativa mantém a posição da leitura.
4. Ocultar/exibir a barra, trocar o modo de leitura e avançar/voltar capítulo.
5. No catálogo, rolar e alternar **Ordenar**. A lista não deve virar uma tela de
   carregamento e deve manter a posição. Busca/filtros novos devem começar no topo.
6. Conferir o Início com e sem histórico, capas ausentes e fonte ampliada.

Branch de trabalho: `refactor/kuro-reader-v2`. A `main` não faz parte da entrega.
