import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/cloud_auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/appearance_settings.dart';
import '../widgets/yomi_brand_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _showRestoreBackupModal() {
    final ctrl = TextEditingController();
    final palette = ProfilePaletteService.paletteNotifier.value;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Restaurar Código de Backup',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cole o código de backup para mesclar perfil, favoritos, listas, histórico e preferências. Imagens baixadas não são restauradas.',
              style: TextStyle(fontSize: 12.5, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Cole o código de backup aqui...',
                filled: true,
                fillColor: YomiPalette.pitchBlack,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: palette.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: ctx,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Restaurar dados?'),
                      content: const Text(
                        'O backup será mesclado aos dados locais. '
                        'Itens com a mesma chave serão substituídos.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Restaurar'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true || !ctx.mounted) return;
                  final ok = await StorageService.importFullBackupJson(ctrl.text);
                  if (!ctx.mounted) return;
                  AppFeedback.show(
                    ctx,
                    SnackBar(
                      content: Text(
                        ok
                            ? 'Dados mesclados com sucesso.'
                            : 'Backup inválido ou corrompido.',
                      ),
                    ),
                  );
                  if (ok) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Restaurar Agora'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileAdaptivePalette>(
      valueListenable: ProfilePaletteService.paletteNotifier,
      builder: (context, palette, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF070709),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Row(
              children: [
                Icon(Icons.settings_rounded, color: palette.primary, size: 22),
                const SizedBox(width: 10),
                const Text(
                  'Configurações',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
          ),
          body: ValueListenableBuilder<NsfwDisplayMode>(
            valueListenable: StorageService.nsfwModeNotifier,
            builder: (context, nsfwMode, _) {
              return ValueListenableBuilder(
                valueListenable: StorageService.settingsBox.listenable(),
                builder: (context, Box settingsBox, _) {
                  final lockNsfwStartup = StorageService.lockNsfwOnStartup;
                  final hideZero = StorageService.hideZeroChapterTitles;
                  final dataSaver = StorageService.dataSaverEnabled;

                  return ListView(
                    // generous bottom padding so the floating navbar never cuts off content
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 130),
                    children: [
                      // 1. CONTA E NUVEM (GOOGLE / FIRESTORE)
                      _buildSectionTitle('Conta & Sincronização em Nuvem', palette),
                      const SizedBox(height: 8),
                      _buildCloudAccountCard(context, palette),

                      const SizedBox(height: 24),

                      // 2. BACKUP EM ARQUIVO & LOCAL NO APARELHO
                      _buildSectionTitle('Backup & Armazenamento', palette),
                      const SizedBox(height: 8),
                      _buildBackupFilesCard(context, palette),

                      const SizedBox(height: 24),

                      // 3. APARÊNCIA & INTERFACE
                      _buildSectionTitle('Aparência & Interface', palette),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const AppearanceSettings(),
                            const Divider(color: Colors.white10, height: 24),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Abrir o Perfil ao iniciar',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                'Desative para iniciar diretamente pela tela inicial de destaques.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white60,
                                ),
                              ),
                              activeThumbColor: palette.primary,
                              value: StorageService
                                  .profileNotifier
                                  .value
                                  .openOnProfileByDefault,
                              onChanged: (enabled) async {
                                final current = StorageService.profileNotifier.value;
                                await StorageService.updateUserProfile(
                                  current.copyWith(openOnProfileByDefault: enabled),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 4. LEITURA & DESEMPENHO
                      _buildSectionTitle('Catálogo & Desempenho', palette),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              activeThumbColor: palette.primary,
                              title: const Text(
                                'Ocultar obras "Só Capa" (0 capítulos)',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                'Oculta obras do catálogo que não possuem capítulos confirmados nesta fonte.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white54,
                                ),
                              ),
                              value: hideZero,
                              onChanged: (val) =>
                                  StorageService.setHideZeroChapterTitles(val),
                            ),
                            const Divider(color: Colors.white10, height: 20),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              activeThumbColor: palette.primary,
                              title: const Text(
                                'Economia de Dados (Data Saver)',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                'Prioriza imagens comprimidas da fonte para economizar internet.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white54,
                                ),
                              ),
                              value: dataSaver,
                              onChanged: (val) =>
                                  StorageService.setDataSaverEnabled(val),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 5. FILTRO DE CONTEÚDO ADULTO (18+)
                      _buildSectionTitle('Filtro de Conteúdo Adulto (18+)', palette),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Column(
                          children: [
                            for (final mode in NsfwDisplayMode.values)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  nsfwMode == mode
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: nsfwMode == mode
                                      ? palette.primary
                                      : Colors.white54,
                                ),
                                title: Text(
                                  mode.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                  ),
                                ),
                                subtitle: Text(
                                  mode.subtitle,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.white60,
                                  ),
                                ),
                                onTap: () => StorageService.setNsfwMode(mode),
                              ),
                            const Divider(color: Colors.white10, height: 16),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              activeThumbColor: palette.primary,
                              title: const Text(
                                'Sempre iniciar com Conteúdo Adulto Desligado',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                'Ao reiniciar o Yomi, o filtro 18+ volta para Seguro.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white54,
                                ),
                              ),
                              value: lockNsfwStartup,
                              onChanged: (val) =>
                                  StorageService.setLockNsfwOnStartup(val),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 6. ÁREA DE TRANSFERÊNCIA (CÓDIGO AVANÇADO)
                      _buildSectionTitle('Código de Backup (Avançado)', palette),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Copie ou cole o código bruto de backup para migração manual rápida.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final code = StorageService.exportFullBackupJson();
                                      await Clipboard.setData(
                                        ClipboardData(text: code),
                                      );
                                      if (!context.mounted) return;
                                      AppFeedback.show(
                                        context,
                                        const SnackBar(
                                          content: Text(
                                            'Código copiado para a área de transferência!',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.copy_all_rounded, size: 16),
                                    label: const Text('Copiar Código'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _showRestoreBackupModal,
                                    icon: const Icon(Icons.restore_rounded, size: 16),
                                    label: const Text('Colar Código'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title, ProfileAdaptivePalette palette) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: palette.soft,
        ),
      ),
    );
  }

  Widget _buildCloudAccountCard(
    BuildContext context,
    ProfileAdaptivePalette palette,
  ) {
    return ValueListenableBuilder(
      valueListenable: CloudAuthService.currentUser,
      builder: (context, user, _) {
        return ValueListenableBuilder(
          valueListenable: CloudSyncService.syncStatus,
          builder: (context, status, _) {
            final isSyncing = status == CloudSyncStatus.syncing;

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: user != null
                      ? palette.primary.withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: user != null
                              ? palette.primary.withValues(alpha: 0.18)
                              : Colors.white10,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: user != null && user.photoURL != null
                            ? ClipOval(
                                child: Image.network(
                                  user.photoURL!,
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Icon(
                                    Icons.person_rounded,
                                    color: palette.primary,
                                    size: 22,
                                  ),
                                ),
                              )
                            : Icon(
                                user != null
                                    ? Icons.cloud_done_rounded
                                    : Icons.cloud_off_rounded,
                                color: user != null
                                    ? palette.primary
                                    : Colors.white60,
                                size: 22,
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user != null
                                  ? (user.displayName ?? 'Conta Google')
                                  : 'Nenhuma conta conectada',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user != null
                                  ? (user.email ?? 'Sincronização ativa no Firestore')
                                  : 'Conecte sua conta Google para salvar sua biblioteca na nuvem.',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSyncing)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (user == null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1E1E1E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final signedUser = await CloudAuthService.signInWithGoogle();
                          if (!context.mounted) return;
                          if (signedUser != null) {
                            AppFeedback.show(
                              context,
                              SnackBar(
                                content: Text('Conectado como ${signedUser.email}!'),
                              ),
                            );
                            await CloudSyncService.backupToCloud(silent: true);
                          }
                        },
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: const Text(
                          'Conectar com Google',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: palette.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: isSyncing
                                ? null
                                : () async {
                                    final ok = await CloudSyncService.backupToCloud();
                                    if (!context.mounted) return;
                                    AppFeedback.show(
                                      context,
                                      SnackBar(
                                        content: Text(
                                          ok
                                              ? 'Biblioteca sincronizada na nuvem com sucesso!'
                                              : (CloudSyncService.syncErrorMessage.value ??
                                                  'Falha ao salvar na nuvem.'),
                                        ),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                            label: const Text('Salvar na Nuvem'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: isSyncing
                                ? null
                                : () async {
                                    final ok = await CloudSyncService.restoreFromCloud();
                                    if (!context.mounted) return;
                                    AppFeedback.show(
                                      context,
                                      SnackBar(
                                        content: Text(
                                          ok
                                              ? 'Dados restaurados da nuvem!'
                                              : (CloudSyncService.syncErrorMessage.value ??
                                                  'Nenhum backup encontrado na nuvem.'),
                                        ),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.cloud_download_rounded, size: 18),
                            label: const Text('Restaurar da Nuvem'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: Colors.white60,
                        ),
                        onPressed: () async {
                          await CloudAuthService.signOut();
                          if (!context.mounted) return;
                          AppFeedback.show(
                            context,
                            const SnackBar(content: Text('Conta desconectada.')),
                          );
                        },
                        icon: const Icon(Icons.logout_rounded, size: 14),
                        label: const Text(
                          'Desconectar conta',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBackupFilesCard(
    BuildContext context,
    ProfileAdaptivePalette palette,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.file_copy_rounded, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Arquivos de Backup (.kuro)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Exporte um arquivo para salvar no seu Google Drive, WhatsApp ou pasta Downloads, ou selecione um arquivo salvo anteriormente para restaurar.',
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.white60,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final ok = await StorageService.exportBackupToFile();
                    if (!context.mounted) return;
                    if (!ok) {
                      AppFeedback.show(
                        context,
                        const SnackBar(
                          content: Text('Não foi possível exportar o arquivo.'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('Exportar Arquivo'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final ok = await StorageService.importBackupFromFile();
                    if (!context.mounted) return;
                    AppFeedback.show(
                      context,
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Backup restaurado com sucesso!'
                              : 'Nenhum backup válido foi restaurado.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.file_open_rounded, size: 16),
                  label: const Text('Importar Arquivo'),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 24),
          const Row(
            children: [
              Icon(Icons.phone_android_rounded, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Backup automático ativo no seu aparelho',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Seus dados são salvos periodicamente no armazenamento interno do aparelho.',
            style: TextStyle(fontSize: 11.5, color: Colors.white54),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final ok = await StorageService.syncAutoBackupNow();
                    if (!context.mounted) return;
                    AppFeedback.show(
                      context,
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Backup salvo no aparelho com sucesso!'
                              : 'Adicione favoritos ou configure o perfil primeiro.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Salvar no Aparelho'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final restored =
                        await StorageService.tryRestoreFromDeviceAutoBackup();
                    if (!context.mounted) return;
                    AppFeedback.show(
                      context,
                      SnackBar(
                        content: Text(
                          restored
                              ? 'Dados restaurados do aparelho!'
                              : 'Nenhum backup salvo encontrado no aparelho.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings_backup_restore_rounded, size: 16),
                  label: const Text('Restaurar do Aparelho'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
