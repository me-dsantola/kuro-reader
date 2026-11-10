# Beta 1.1.3+5 — estabilidade da leitura

Referência visual: vídeo reduzido enviado pelo responsável, com 50 segundos.
Foram observados espaços pretos durante a rolagem contínua e páginas que, ao
voltar no modo paginado, terminavam em um ícone de imagem quebrada sem recuperação.
A análise também reproduziu perda de posição ao redimensionar a janela.

## Correções

- Os modos contínuo e paginado usam a mesma sessão e os mesmos provedores de
  imagem. Páginas já obtidas permanecem em cache comprimido durante a leitura,
  mesmo que o Flutter descarte seus bitmaps decodificados. Voltar ou trocar de
  modo não depende de uma nova consulta para essas páginas enquanto estiverem
  no cache.
- O cache comprimido tem limite de 24 MiB e descarte por uso recente. O cache
  separado de bitmaps continua limitado a 64 MiB. A sessão é liberada ao sair.
- Requisições repetidas da mesma página são compartilhadas, com no máximo três
  requisições simultâneas. Respostas HTML não são aceitas como imagem.
- As duas modalidades usam os mesmos fallbacks já existentes. A nova tentativa
  no modo paginado invalida a página e pode renovar os endereços do capítulo.
- Imagens que terminam de carregar recebem a altura correta durante a rolagem,
  sem aguardar o fim do gesto e sem permanecer reduzidas em um espaço estimado.
- Correções de posição acontecem no layout, antes da pintura. A implementação
  anterior mudava a altura em um quadro e só corrigia a posição no seguinte.
- Redimensionar preserva página e fração visível. A posição também é salva por
  página/fração para reabertura e troca de modos; índices e offsets antigos
  continuam preservados para compatibilidade. O novo campo Hive é aditivo e
  também é validado na importação de backups.
- O modo paginado oferece nova tentativa e reconhece o toque para ocultar ou
  mostrar a barra. A conclusão do capítulo é gravada antes de avançar ao próximo.
- O botão Ordenar e sua ordenação parcial dos resultados foram removidos.
  Busca por título e filtros permanecem disponíveis.

## Evidência e limites

Os testes de posição visual por quadro e de redimensionamento falharam contra
a versão anterior do visualizador e passaram com a correção. Os demais cenários
incluem carregamento durante um gesto, retomada com largura diferente, retorno
após descarte de bitmaps, fonte que fica indisponível após a primeira leitura,
fila de requisições, falha e nova tentativa no modo paginado, toque na barra,
leitura local sem rede e compatibilidade de backup.

Validação: `flutter pub get`, `flutter analyze --no-fatal-infos`, `flutter test`
e o workflow Beta Release ARM64. A validação do vídeo foi por inspeção; os testes
automatizados usam imagens e fontes simuladas, não uma sessão do MEmu do responsável.
Arquivos danificados e indisponibilidade externa ainda podem exigir nova tentativa.

## Validação manual

1. Abrir o mesmo capítulo do vídeo, avançar ao fim e voltar repetidamente em
   ambos os modos. Conferir especialmente as páginas que falharam no vídeo.
2. Alternar modos sem fechar o capítulo e confirmar posição e imagens já lidas.
3. Ler enquanto chegam imagens em rede lenta: não deve haver um espaço preto
   reservado além da proporção real de uma imagem já carregada.
4. Falhar uma página e usar sua nova tentativa; conferir toque para esconder a barra.
5. Redimensionar, fechar e reabrir no meio de uma página; conferir a retomada.
6. Repetir com capítulo baixado e rede desligada.
7. Conferir a ausência de Ordenar e o funcionamento da busca e dos filtros.

Trabalho restrito à branch `refactor/kuro-reader-v2`. A `main` não foi alterada.
