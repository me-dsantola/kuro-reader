# Beta 1.1.4+6 — catálogo e feedback do dispositivo

Branch: `refactor/kuro-reader-v2`. Base: `f91546e`.

## Catálogo e contraste

A marca permanece à esquerda do cabeçalho, com ajuste de escala em telas
estreitas; o seletor de ordem fica à direita. A busca e os filtros continuam
na linha seguinte. Recentes, Populares e Título A–Z disparam novas consultas
com a ordem nativa de cada provedor, reiniciando os cursores e invalidando
respostas da seleção anterior. Buscar por texto mantém a ordem escolhida.

Populares preserva a classificação de cada catálogo, intercalando fontes;
não usa número de capítulos como popularidade e não inventa uma pontuação
comparável entre serviços. Recentes usa atualizações do catálogo ou data de
publicação informada pelo provedor. Fontes de metadados não comprovam novas
páginas legíveis. Datas ausentes não são preenchidas com a data atual.
A–Z organiza os títulos carregados, incluindo as novas páginas; o menu
explica esse limite. Não representa uma classificação global de todo o acervo.

As tags de detalhes, os chips de fontes e seus marcadores de seleção usam
texto claro nas superfícies escuras. Inclusão/exclusão mantém Enso/Sakura.

## Estado do Android

Uma ponte nativa usa eventos do Android para bateria, carregamento, economia
de energia e conectividade validada. `ACCESS_NETWORK_STATE` é a única nova
permissão, normal e sem solicitação de acesso em tempo de execução. Não há
nova dependência Flutter ou serviço externo. Plataformas sem essa ponte
permanecem com conectividade desconhecida.

- Sem internet: faixa persistente em todas as rotas orienta à aba Offline.
- Requisição aguardando por 3 segundos: feedback de carregamento lento.
  Duas respostas lentas entre as três últimas mantêm esse estado; respostas
  rápidas o removem. A observação usa as requisições existentes, sem teste
  de velocidade, e não atribui necessariamente a lentidão ao celular: a
  fonte também pode estar lenta. Um erro de API não declara o aparelho offline.
- Bateria em até 20%, fora do carregador, ou economia do Android ativa:
  reduz animações que respeitam MediaQuery e usa barras opacas sem blur.
  Até 5%, o aviso ganha destaque. Ao recuperar, a aparência anterior retorna.

As faixas ficam acima da navegação, sem substituir o leitor ou apagar dados.
As preferências de acessibilidade continuam respeitadas. Downloads mantêm
seu limite de 30 segundos por requisição; não há mudança automática do modo
de qualidade de imagem salvo pelo usuário.

## Validação

Executar `flutter pub get`, `flutter analyze --no-fatal-infos`, `flutter test`
e o GitHub Actions Beta Release ARM64. Os testes novos cobrem a consulta
real formada para seis adaptadores e três ordens, bateria/carregador,
conectividade desconhecida, latência/recuperação e preservação de uma rota
aberta durante a transição de estado. Os dados de rede e bateria nos testes
são simulados; requer confirmação em Android físico.

## Conferência manual

1. Instalar o APK 1.1.4 (build 6) e conferir as três ordens com e sem busca.
2. Abrir filtros e detalhes: texto e marcas de seleção devem permanecer claros.
3. Abrir um capítulo baixado, ativar modo avião e conferir faixa e leitura local.
4. Voltar à rede: a faixa deve sumir sem fechar o capítulo ou perder navegação.
5. Usar rede lenta: conferir aviso de carregamento e recuperação posterior.
6. Ativar economia do Android e depois desativar; conferir barras e animações.
7. Conferir bateria em até 20%/5%, carregador, tela estreita e fonte ampliada.

A falha de imagens relatada na 1.1.3 continua pendente de reprodução real.
Este lote não deve ser interpretado como correção comprovada desse problema.


## Ajuste de posição — Beta 1.1.5+7

A logo YOMI passa ao centro da linha superior. Busca e filtros ficam juntos
na linha seguinte; a ordenação ocupa uma linha logo abaixo da busca, alinhada
à direita, com o rótulo “Ordenar por”. A altura reservada ao cabeçalho acompanha
essa composição para que o catálogo comece abaixo de todos os controles.
As três ordens e os indicadores de estado mantêm seu comportamento.
