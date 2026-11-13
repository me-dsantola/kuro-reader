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
              'Restaurar Código de Backup YOMI',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cole o backup para mesclar perfil, favoritos, listas, histórico e preferências. Imagens baixadas não são restauradas. O código não é criptografado.',
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
                        'Itens com a mesma chave serão substituídos. '
                        'Salve um backup atual antes de continuar.',
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
                  final ok = await StorageService.importFullBackupJson(
                    ctrl.text,
                  );
                  if (!ctx.mounted) return;
                  AppFeedback.show(
                    ctx,
                    SnackBar(
                      content: Text(
                        ok
                            ? 'Perfil, favoritos, listas e histórico mesclados com sucesso.'
                            : 'Backup inválido ou erro ao restaurar. Confira seus dados locais.',
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
          appBar: AppBar(
            title: Row(
              children: [
                Icon(Icons.settings_rounded, color: palette.primary),
                const SizedBox(width: 10),
                const Text('Configurações'),
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
                    padding: const EdgeInsets.all(16),
                    children: [
                      const AppearanceSettings(),
                      const SizedBox(height: 22),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Abrir o Perfil ao iniciar'),
                        subtitle: const Text(
                          'Desative para iniciar pela tela de leituras recentes.',
                          style: TextStyle(fontSize: 12, color: Colors.white60),
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
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 10),
                      Text(
                        'Filtro de Conteúdo Sensível / Adulto (18+)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: palette.soft,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: palette.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Colors.white10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (final mode in NsfwDisplayMode.values)
                              ListTile(
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
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  mode.subtitle,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white60,
                                  ),
                                ),
                                onTap: () => StorageService.setNsfwMode(mode),
                              ),
                            const Divider(color: Colors.white10, height: 1),
                            SwitchListTile(
                              activeThumbColor: palette.primary,
                              title: const Text(
                                'Sempre iniciar com Conteúdo Adulto Desligado',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                'Garante que toda vez que o app for aberto, o modo 18+ volte automaticamente para Seguro (Oculto).',
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
                      const SizedBox(height: 22),
                      Text(
                        'Catálogo & Leitor de Alta Performance',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: palette.soft,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: palette.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Colors.white10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            SwitchListTile(
                              activeThumbColor: palette.primary,
                              title: const Text(
                                'Ocultar totalmente obras "Só Capa" (0 capítulos)',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                'Ative para ocultar títulos sem capítulos confirmados nesta fonte.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white54,
                                ),
                              ),
                              value: hideZero,
                              onChanged: (val) =>
                                  StorageService.setHideZeroChapterTitles(val),
                            ),
                            const Divider(color: Colors.white10, height: 1),
                            SwitchListTile(
                              activeThumbColor: palette.primary,
                              title: const Text(
                                'Economia de Dados (Data Saver)',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                'Prefere as páginas de menor tamanho oferecidas pela fonte, quando disponíveis.',
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
                      const SizedBox(height: 22),
                      Text(
                        'Backup na Nuvem (Google / Firestore)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: palette.soft,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder(
                        valueListenable: CloudAuthService.currentUser,
                        builder: (context, user, _) {
                          return ValueListenableBuilder(
                            valueListenable: CloudSyncService.syncStatus,
                            builder: (context, status, _) {
                              final isSyncing = status == CloudSyncStatus.syncing;
                              final isFirebaseReady =
                                  CloudAuthService.isFirebaseAvailable.value;

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: palette.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: palette.primary.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          user != null
                                              ? Icons.cloud_done_rounded
                                              : Icons.cloud_queue_rounded,
                                          color: palette.primary,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            user != null
                                                ? 'Conta Google Conectada'
                                                : 'Sincronização na Nuvem',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                        ),
                                        if (isSyncing)
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      user != null
                                          ? 'Logado como: ${user.email ?? user.displayName ?? "Usuário Google"}\nSeus favoritos, histórico e perfil sincronizam com o Firestore.'
                                          : 'Conecte sua conta Google para salvar sua biblioteca, histórico e preferências na nuvem com restauração em 1 clique.',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white70,
                                        height: 1.35,
                                      ),
                                    ),
                                    if (!isFirebaseReady) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: Colors.amber.withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline_rounded,
                                              size: 14,
                                              color: Colors.amber,
                                            ),
                                            SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Firebase pendente: adicione o google-services.json no app para ativar.',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.amber,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    if (user == null)
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: palette.primary,
                                            foregroundColor: Colors.white,
                                          ),
                                          onPressed: () async {
                                            final signedUser =
                                                await CloudAuthService.signInWithGoogle();
                                            if (!context.mounted) return;
                                            if (signedUser != null) {
                                              AppFeedback.show(
                                                context,
                                                SnackBar(
                                                  content: Text(
                                                    'Conectado com sucesso como ${signedUser.email}!',
                                                  ),
                                                ),
                                              );
                                              // Prompt or auto-backup
                                              await CloudSyncService.backupToCloud(
                                                silent: true,
                                              );
                                            } else {
                                              final err =
                                                  CloudAuthService.lastAuthError.value;
                                              if (err != null) {
                                                AppFeedback.show(
                                                  context,
                                                  SnackBar(content: Text(err)),
                                                );
                                              }
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.login_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Conectar com Google'),
                                        ),
                                      )
                                    else
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: FilledButton.icon(
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor:
                                                        palette.primary,
                                                    foregroundColor: Colors.white,
                                                  ),
                                                  onPressed: isSyncing
                                                      ? null
                                                      : () async {
                                                          final ok =
                                                              await CloudSyncService.backupToCloud();
                                                          if (!context.mounted) {
                                                            return;
                                                          }
                                                          AppFeedback.show(
                                                            context,
                                                            SnackBar(
                                                              content: Text(
                                                                ok
                                                                    ? 'Backup sincronizado na nuvem com sucesso!'
                                                                    : (CloudSyncService.syncErrorMessage.value ??
                                                                        'Falha ao sincronizar na nuvem.'),
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                  icon: const Icon(
                                                    Icons.cloud_upload_rounded,
                                                    size: 18,
                                                  ),
                                                  label: const Text(
                                                    'Salvar na Nuvem',
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: isSyncing
                                                      ? null
                                                      : () async {
                                                          final ok =
                                                              await CloudSyncService.restoreFromCloud();
                                                          if (!context.mounted) {
                                                            return;
                                                          }
                                                          AppFeedback.show(
                                                            context,
                                                            SnackBar(
                                                              content: Text(
                                                                ok
                                                                    ? 'Dados restaurados da nuvem com sucesso!'
                                                                    : (CloudSyncService.syncErrorMessage.value ??
                                                                        'Nenhum backup encontrado na nuvem.'),
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                  icon: const Icon(
                                                    Icons.cloud_download_rounded,
                                                    size: 18,
                                                  ),
                                                  label: const Text(
                                                    'Restaurar da Nuvem',
                                                  ),
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
                                                  const SnackBar(
                                                    content: Text('Conta desconectada.'),
                                                  ),
                                                );
                                              },
                                              icon: const Icon(
                                                Icons.logout_rounded,
                                                size: 14,
                                              ),
                                              label: const Text(
                                                'Desconectar conta',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Arquivos de Backup (.kuro)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: palette.soft,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: palette.primary.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.file_present_rounded,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Exportar ou Importar Arquivo de Backup',
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
                              'Gere um arquivo de backup para salvar no seu Google Drive, WhatsApp ou pasta Downloads, ou restaure um arquivo .kuro salvo anteriormente.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
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
                                    ),
                                    onPressed: () async {
                                      final ok =
                                          await StorageService.exportBackupToFile();
                                      if (!context.mounted) return;
                                      if (!ok) {
                                        AppFeedback.show(
                                          context,
                                          const SnackBar(
                                            content: Text(
                                              'Não foi possível exportar o arquivo de backup.',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.share_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Exportar Arquivo'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final ok =
                                          await StorageService.importBackupFromFile();
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
                                    icon: const Icon(
                                      Icons.file_open_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Importar Arquivo'),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white12, height: 22),
                            const Row(
                              children: [
                                Icon(
                                  Icons.phone_android_rounded,
                                  color: Colors.white70,
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Backup automático ativo no seu aparelho',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final ok =
                                          await StorageService.syncAutoBackupNow();
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
                                    icon: const Icon(
                                      Icons.save_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Salvar no Aparelho'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
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
                                    icon: const Icon(
                                      Icons.settings_backup_restore_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Restaurar do Aparelho'),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white12, height: 22),
                            const Row(
                              children: [
                                Icon(
                                  Icons.qr_code_rounded,
                                  color: Colors.white70,
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Área de Transferência (Avançado)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final code =
                                          StorageService.exportFullBackupJson();
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
                                    icon: const Icon(
                                      Icons.copy_all_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Copiar Código'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _showRestoreBackupModal,
                                    icon: const Icon(
                                      Icons.restore_rounded,
                                      size: 16,
                                    ),
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
}

