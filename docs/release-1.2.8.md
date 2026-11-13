# Release 1.2.8 (build 16)

### Mudanças e Melhorias
- **Autenticação Obrigatória e Sincronização em Nuvem**:
  - Integração nativa com Google Sign-In e Firebase Firestore com chave SHA-1 e `serverClientId` configurados.
  - Tela de autenticação inicial limpa e minimalista com identidade visual YOMI oficial em vetor SVG.
  - Sincronização em nuvem completa: foto de perfil, banner, apelido, bio, favoritos, histórico e preferências de leitura.
  - Isolamento estrito entre usuários: troca de conta limpa sessões residuais e previne sobreposição de dados entre perfis diferentes.
- **Destaques e Billboard da Home**:
  - Altura do banner de destaque ampliada para 62% da altura útil da tela (540dp a 620dp), eliminando cortes de arte em telas 20:9 e 21:9.
  - Alinhamento da capa ajustado para `Alignment.topCenter` para preservar logotipos, títulos e ilustrações no topo do mangá.
  - Gradiente superior suavizado e translúcido, garantindo visualização cristalina das capas.
  - Rotação dinâmica e periódica: a cada janela de 45 minutos, 5 obras aleatórias são selecionadas a partir dos 25 mangás mais populares.
- **Otimização de Desempenho e Fluidez**:
  - Rolagem vertical otimizada via `ValueNotifier<double>`, eliminando chamadas repetitivas de `setState` durante o scroll.
  - Transição de destaques isolada em subárvore, evitando re-renderização da tela inteira a cada troca de obra.
  - Efeito de vidro fosco (`FrostedSurface`) otimizado com redução de sigma e simplificação de sombras de GPU, mantendo taxa de quadros estável em 60/120 FPS.
- **Distribuição e Atualização**:
  - Versão incrementada para `1.2.8+16`, habilitando atualização direta in-place sem desinstalação prévia.
