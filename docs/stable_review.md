# Revisão da linha estável 1.2.0

## Princípios de UI

A interface anterior atendia parcialmente aos cinco princípios. Havia uma
identidade visual consistente, mas controles competiam no cabeçalho, filtros
densos dificultavam a leitura e os menus ocupavam espaço durante a rolagem.

| Princípio | Ajuste aplicado | Evidência verificável |
| --- | --- | --- |
| Hierarquia | Logo central; busca/filtros antes da ordenação; leitura e retomada em destaque | Teste do catálogo e capturas em 320/360 px |
| Contraste | Texto claro nas tags, badges escuros opacos sobre capas, busca mais legível, vidro opaco em alto contraste/economia | Teste em alto contraste e texto ampliado; revisão visual |
| Consistência | Mesmas superfícies, cores e ações de recuperação nos dois modos de leitura | Testes da barra, troca de modo e nova tentativa |
| Divulgação progressiva | Fontes e categorias recolhíveis; gêneros abertos inicialmente; mudanças só entram ao aplicar | Teste de cancelamento do rascunho sem nova consulta |
| Alinhamento/equilíbrio | Cabeçalho agrupado, alvos de tags de pelo menos 48 px e larguras flexíveis | Catálogo/filtros em 320 px e barra com texto ampliado |

A navegação inferior reage ao gesto vertical, ignora carrosséis e saltos
programáticos e retorna ao inverter o gesto ou voltar de outra tela.
O cabeçalho de Explorar flutua/recolhe junto da rolagem. A barra do webtoon
acompanha o gesto; o modo paginado mantém controle por toque. A opção de
recolhimento pode ser desligada. As transições respeitam redução de movimento.

## Referências sugeridas

Foram revisados os dois vídeos enviados e o projeto
[Glisse](https://github.com/0kzh/glisse). O vidro em controles delimitados e a
resposta da interface à direção da rolagem se adaptam à proposta do YOMI.
A implementação usa Flutter, sem incorporar a biblioteca React/WebGL ou copiar
seu código. Não há parallax ou alteração do gesto natural de leitura.

## Confiabilidade

- Memória de páginas limitada a 24 MiB e cache temporário de disco a 96 MiB por
  sessão; ambos compartilhados pelos modos. O disco é opcional e falhas nele
  não transformam uma página obtida com sucesso em erro de leitura.
- Cache de disco removido ao encerrar o capítulo; sessões abandonadas são
  limpas na primeira leitura após reiniciar o processo.
- URLs expiradas podem ser atualizadas com uma consulta compartilhada. Limite
  HTTP 429 interrompe tentativas alternativas automáticas.
- Falhas de decodificação invalidam bytes; nova tentativa não reutiliza o
  conteúdo corrompido. A geometria da página permanece independente do widget.
- Downloads só são indexados após validar as imagens. Chamadas simultâneas
  compartilham o mesmo resultado e a limpeza não concorre com gravações.
- Exclusão individual e total pedem confirmação e preservam progresso/favoritos.
- Histórico e conclusão são serializados. Entradas inválidas não bloqueiam a
  biblioteca nem são apagadas silenciosamente. Eventos duplicados e tamanhos
  desconhecidos não inventam páginas lidas.
- Títulos japoneses/coreanos preservam sua identidade. Contagens de capítulos
  desconhecidas não recebem números fictícios. O modo seguro não confia em
  classificação ausente.
- Backup inclui as duas preferências visuais e valida o diário de recuperação
  integralmente antes de reverter qualquer seção.

## Validação e limites

A suíte inclui regressões de geometria webtoon, revisita após descarte de
bitmaps, cache de disco sem rede, recuperação automática/manual, limite de
requisições, downloads corrompidos, concorrência, restauração e privacidade.
Há verificações de rolagem, busca/ordenação, cancelamento de filtros, largura
estreita, alto contraste e texto ampliado. O workflow também rejeita APK Beta,
debuggável, de versão/arquitetura errada ou certificado divergente.

Isso não demonstra ausência absoluta de defeitos nem substitui uma reprodução
no aparelho do vídeo original. Não foi medida a taxa de quadros em hardware
Android nesta revisão. Os sensores nativos e fontes reais exigem conferência
em Android; os testes de rede usam respostas controladas.

A publicação depende da chave permanente configurada pelo proprietário. Uma
assinatura de debug ou descartável não pode substituir esse requisito.
