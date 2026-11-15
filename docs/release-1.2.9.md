# YOMI 1.2.9 — Notas da Versão

## Novidades desta versão

- **Sincronização em nuvem inteligente (Anti-conflito)**: ao detectar dados mais recentes na nuvem, o YOMI agora mescla biblioteca, capas, coleções, capítulos lidos e o maior progresso de página antes de gravar no Firestore, evitando sobrescrever avanços de outros dispositivos ou do portal web.
- **Compactação automática para o Firestore**: caches efêmeros de listas de capítulos são removidos da sincronização e históricos extensos são compactados automaticamente para respeitar com segurança o limite de 1 MB por documento na nuvem.
- **Login e cadastro com E-mail e Senha**: além do acesso com Google, agora é possível entrar ou criar conta com e-mail e senha diretamente no app, mantendo compatibilidade total entre Android, iOS e YOMI Web.

---

### Downloads recomendados

- **arm64-v8a**: para praticamente todos os celulares Android modernos (64 bits) — **Recomendado**.
- **armeabi-v7a**: para aparelhos Android antigos (32 bits).
- **x86_64**: para emuladores Android e tablets/Chromebooks x86.

> Confira os hashes em `SHA256SUMS.txt` para validar a integridade do APK antes de instalar.
