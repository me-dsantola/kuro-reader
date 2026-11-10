YOMI 1.2.0 reúne as melhorias de interface e confiabilidade da linha Beta em
uma distribuição estável assinada com a chave permanente do proprietário.

- Logo centralizada, busca e ordenação agrupadas, menus recolhidos ao rolar;
- Aparência de vidro suave opcional e respeito ao alto contraste/redução de movimento;
- Filtros por grupos, rascunho cancelável e tags com contraste sobre superfícies escuras;
- Cache de páginas em memória/disco, recuperação de URLs expiradas e nova tentativa manual;
- Verificação das imagens offline, compartilhamento de downloads simultâneos e exclusão confirmada;
- Histórico e métricas protegidos contra gravações concorrentes e registros legados inválidos;
- Feedback Android de bateria baixa, economia, ausência de internet e respostas lentas.

Escolha **arm64-v8a** para celulares ARM64, **armeabi-v7a** para ARM de 32 bits
ou **x86_64** para emuladores Android x86 de 64 bits. Os checksums estão em
`SHA256SUMS.txt`; `release.json` identifica o código-fonte e o certificado.

A Beta e a estável têm dados separados. Exporte o backup na Beta e importe na
estável; as imagens offline devem ser baixadas novamente. Se o Android recusar
uma atualização de uma estável antiga por certificado incompatível, guarde o
backup antes de desinstalá-la.

A análise estática, os testes automatizados e a verificação dos APKs são
obrigatórios no workflow. A compatibilidade com cada aparelho e a disponibilidade
das fontes externas continuam dependendo das condições reais de uso.
