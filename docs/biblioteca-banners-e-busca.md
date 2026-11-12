# Biblioteca, banners e destaque rotativo

## Banners do perfil

As três imagens fornecidas foram incluídas sem alteração em `assets/banners`:
**Horizonte distante**, **Lua vermelha** e **Portal da noite**. São as opções
padrão apresentadas no editor; o cadastro de presets anteriores foi preservado
para continuar reconhecendo perfis salvos. Perfis sem banner usam a primeira
imagem. Fotos e banners personalizados continuam disponíveis.

O desenho usa `Image.asset` com resolução de decodificação limitada à tela,
evitando manter as imagens originais inteiras na memória em cada miniatura.

## Home e navegação

- O destaque alterna entre até cinco obras populares a cada oito segundos.
  Os indicadores permitem escolher uma obra manualmente.
- A paleta acompanha a capa da obra selecionada, com fallback determinístico
  quando não é possível extrair a cor. As ações, seções e acentos da home
  recebem essa paleta; a preferência global do perfil não é sobrescrita.
- A alternância pausa em abas inativas, em outras rotas, durante a abertura da
  leitura, em segundo plano e quando o sistema pede redução de movimento.
- A barra inferior mantém vidro, cápsula ativa, ícones e rótulos existentes,
  com largura centralizada limitada a 328 px, altura de 58 px e menor distância
  entre ícone e texto. No offline, os dois itens ficam em uma cápsula de 240 px.

## Biblioteca

O layout segue a referência de Biblioteca encontrada em `exemplo biblioteca.jpg`:
título e subtítulo, busca arredondada, chips **Todas / Favoritos / Lendo /
Concluídas**, card **Continue Lendo**, capas com progresso e card
**Adicione novas obras**. As abas **Minha Biblioteca / Baixados** foram mantidas.

O fundo é liso: não há personagem, ilustração nem painter decorativo atrás do
conteúdo. Campos, chips, bordas, gradientes, barras e títulos de seção recebem
a paleta reativa do perfil. Alterar essa paleta atualiza a Biblioteca aberta.

O progresso considera capítulos concluídos e a posição salva no capítulo atual,
sem contar duas vezes traduções da mesma numeração. Um cache parcial não reduz
o total conhecido da obra. “Concluídas” usa o estado de leitura, não o status de
publicação informado pela fonte. A contagem depende dos capítulos e totais
conhecidos pelo app; não inventa a quantidade de capítulos ausentes.

Listas pessoais, renomeação/exclusão com confirmação, verificação de novidades
e download em lote continuam acessíveis pelo menu de organização. O CTA abre
Explorar quando conectado e explica a limitação quando offline.

## Busca

- A geração da busca é invalidada no momento da digitação, antes do debounce.
  Uma resposta antiga não pode repor títulos de uma consulta anterior.
- Trocar a consulta também reinicia o buffer e os offsets do agregador, mesmo
  quando o chamador não passa `reset: true`.
- A busca local da Biblioteca e das HQs aceita variações de acentos e espaços,
  mantendo a identidade exata usada nos favoritos e nos dados já salvos.
- Ausência de resultados, enriquecimento em outras fontes e indisponibilidade
  das fontes têm estados distintos. A ordenação escolhida continua preservada.

## Validação

- 131 testes Flutter na suíte completa, incluindo regressões de busca,
  alternância manual/automática, troca de cores, filtros, progresso, cache
  parcial, assets, tela estreita e texto ampliado.
- Análise estática sem problemas e verificação de whitespace.
- Compilações Android de depuração e web; o APK fica em
  `build/app/outputs/flutter-apk/app-debug.apk`.
- Consulta real à API MangaDex em 12/11/2026 para One Piece e Solo Leveling;
  as obras principais foram encontradas entre os primeiros resultados.
- Prévia renderizada com fontes e capas reais em
  `build/home-preview/library-redesign.png`. Os estados de progresso dessa
  prévia são dados de teste.

O catálogo e o ledger que recebem uploads não foram alterados por esta revisão.
Execução em aparelho físico e disponibilidade futura das fontes externas
continuam dependendo das condições reais do dispositivo e dos provedores.
