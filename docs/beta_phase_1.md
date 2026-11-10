# YOMI — primeiro lote de qualidade e privacidade

Beta: `1.1.1+3`. Base: `74a9118`, branch `refactor/kuro-reader-v2`.

## Entrega

- Abrir um capítulo pela aba Offline deixa de marcá-lo como concluído.
- Novas buscas reiniciam os estados de paginação, sem aceitar a resposta antiga.
- Backup manual é descrito corretamente nas configurações; a validação cobre
  campos internos de favoritos, capítulos, histórico, perfil e preferências.
- A restauração serializa pedidos e salva um registro de recuperação antes das
  alterações. Uma falha tenta desfazer as chaves alteradas; uma interrupção deixa
  o registro para recuperação antes da abertura normal do aplicativo.
- Uma falha na inicialização do armazenamento mostra uma tela de recuperação,
  com nova tentativa, em vez de acessar caixas indisponíveis.
- Jikan/Kitsu preservam a classificação de conteúdo; dados sem classificação
  confirmada ficam ocultos no modo seguro. A paginação Kitsu não termina só
  porque os resultados de uma página foram ocultados.
- Perfil e central de novidades reagem à mudança do modo de conteúdo.
- O escudo de privacidade passa a ficar acima das rotas de navegação, incluindo
  detalhes e leitor, e exclui o conteúdo coberto da árvore de acessibilidade.
- “Segure para ver” volta a borrar a capa ao soltar.
- Correções de layout para placeholders pequenos de capa e de Material nos
  grupos de configurações preservam o visual e o feedback de toque.
- Flutter fixado em 3.47.9 no CI; nenhuma nova dependência de execução.

Os nomes das caixas Hive e IDs existentes são preservados. O campo opcional
`contentRatingKnown` é aditivo. Favoritos antigos Jikan/Kitsu sem classificação
confiável continuam armazenados e podem ser vistos ao habilitar conteúdo
sensível; não foram excluídos. Atualização automática da classificação desses
registros fica para um lote posterior.

## Validação automatizada

- `flutter pub get`
- `flutter analyze --no-fatal-infos`
- `flutter test` — 43 testes, incluindo regressões de importação, recuperação de
  restauração interrompida, requisições antigas, adaptação dos provedores,
  navegação offline, escudo sobre rotas e inicialização com falha.
- O GitHub Actions executa novamente análise, testes e compilação Beta ARM64.

O registro de recuperação melhora a reversibilidade entre caixas Hive; não
representa uma transação atômica do sistema de arquivos. Se faltar espaço até
para desfazer uma escrita, o registro é mantido para a próxima inicialização.
Os backups continuam sem criptografia e não incluem imagens offline.

## Validação em aparelho

1. Exportar e guardar um backup da instalação atual.
2. Instalar a nova Beta sobre a existente e confirmar favoritos, histórico,
   preferências e capítulos offline. Não desinstalar antes de guardar o backup
   se o Android acusar incompatibilidade de assinatura.
3. Abrir e fechar um capítulo Offline: a contagem de concluídos não deve mudar.
   Marcar como concluído deve contar uma única vez.
4. Iniciar paginação em Explorar e trocar rapidamente texto/filtros; a nova
   busca deve continuar paginando normalmente.
5. Exportar/restaurar dados válidos e tentar um backup inválido; o inválido deve
   ser recusado sem modificar favoritos nem progresso.
6. Alternar conteúdo sensível e conferir Início, Perfil, Biblioteca, Offline e
   novidades. Segurar uma capa borrada e soltar deve restaurar o borrão.
7. Com detalhes ou leitor abertos, alternar de aplicativo e conferir a tela de
   recentes. Validar também retorno ao aplicativo e TalkBack.
8. Conferir Configurações com fonte ampliada e em tela pequena.

## Próximos lotes aprovados

- Continuidade: abertura unificada, sequência por idioma, início da obra,
  estados de disponibilidade e separação de metadados/provedores de leitura.
- Organização: biblioteca com estados/coleções, gerenciamento offline, filtros
  com edição temporária e separação gradual de componentes/telas.
- Acabamento: microanimações de favorito/conclusão/download, movimento reduzido,
  acessibilidade, identidade e desempenho medido em aparelho.
- Infraestrutura: assinatura Beta persistente e validação de atualização entre
  APKs consecutivos, sem usar a chave de produção na Beta.

O carregador de páginas e a `main` permanecem fora deste lote. Nenhuma promoção
para estável deve ocorrer sem a validação física do responsável.
