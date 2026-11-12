# Release 1.2.6 (build 14)

### Mudanças e Melhorias
- **Home & Biblioteca**:
  - Transição de paleta dinâmica com efeito "wave wipe" e sincronização com header e barra de navegação.
  - Carrossel com pré-carregamento e cache LRU limitado, garantindo trocas fluidas sem travamentos.
  - Header recolhível responsivo à rolagem vertical sem conflito com o carrossel horizontal.
  - Novo card "Continuar Lendo" da Biblioteca e da Home com capa flutuante inclinada, coração sincronizado e barra de progresso.
  - Exibição consistente em cinza para obras com contagem confirmada de zero capítulos.
- **Tela de Leitura**:
  - Controles e superfícies adaptados à paleta da obra.
  - Blobatar do perfil integrado de forma discreta na barra superior (pausando animações ao ocultar controles).
  - Ações claras e limpas ao fim do capítulo.
- **Downloads e Modo Offline**:
  - Agrupamento de downloads por obra com capa persistida offline em armazenamento local.
  - Tolerância a falhas na capa sem invalidar capítulos salvos.
  - Migração compatível de downloads legados.
- **Perfil & Customização**:
  - Remoção do botão redundante de banner no perfil (o toque direto na área do banner abre o editor).
  - Correção de conformidade de widgets Material/ListTile para compilações estáveis.
