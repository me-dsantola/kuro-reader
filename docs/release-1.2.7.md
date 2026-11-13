# Release 1.2.7 (build 15)

### Mudanças e Melhorias
- **Identidade Visual e Novo Pacote Vetorial**:
  - Integração do pacote vetorial oficial completo da marca YOMI com 8 paletas de cores em alta fidelidade.
  - Novos ícones de aplicativo gerados para todas as densidades Android (`mipmap-mdpi`, `hdpi`, `xhdpi`, `xxhdpi`, `xxxhdpi`) e `assets/yomi_icon_1024.png`.
  - Símbolo oficial de páginas de mangá em perspectiva desenhado via `CustomPainter` vetorial de alta precisão (`YomiPagesMarkPainter`), integrado à logo Ensō tipográfica e adaptável dinamicamente via shader aos temas do usuário.
- **Header e Layout de Cápsulas Individuais**:
  - Correção de posicionamento dos botões de busca e perfil no Header, ancorando-os no canto superior direito em cápsulas de vidro translúcido flutuante.
- **Animações e Navegação Fluida**:
  - Transição horizontal suave de 380 ms entre abas com fade progressivo e desaceleração cúbica natural.
  - Carrossel de destaques com troca fluida e transição acelerada por hardware.
  - Refinamento sutil na barra de navegação inferior: altura ajustada para 64 dp, ícones para 23.5 dp e tipografia calibrada para 11 dp.
- **Temas, Cores e Mascote**:
  - Isolamento estrito das cores do carrossel da Home somente ao destaque: o restante da página permanece fiel ao tema do perfil do leitor.
  - Cartão de "Continue Lendo" sincronizado com a paleta específica da obra em leitura.
  - Mascote Blobatar integrado no topo da Biblioteca, adaptável ao tom do tema.
  - Expansão de opções de cores no perfil para 30 tonalidades (incluindo todas as marcas YOMI) e 25 matizes no Blobatar.
  - Remoção de telas redundantes de temas nas configurações e eliminação de auras com vazamento.
