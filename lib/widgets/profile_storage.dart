import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/app_directory_service.dart';
import '../services/cloud_auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/profile_drive.dart';
import '../services/storage_service.dart';

class ProfileStorage extends StatefulWidget {
  const ProfileStorage({super.key, required this.uid});
  final String uid;
  @override
  State<ProfileStorage> createState() => _ProfileStorageState();
}

class _ProfileStorageState extends State<ProfileStorage> {
  ProfileDrive? drive;
  bool busy = false;
  String status = '';
  bool get active =>
      mounted && CloudAuthService.currentUser.value?.uid == widget.uid;

  @override
  void dispose() {
    drive?.close();
    super.dispose();
  }

  Future<void> run(Future<String> Function() action) async {
    if (busy || !active) return;
    setState(() => busy = true);
    try {
      final result = await action();
      if (active) setState(() => status = result);
    } catch (e) {
      if (active) {
        setState(
          () => status = e is StateError
              ? e.message
              : 'Falha na operação. Confira sua conexão e as permissões da conta Google.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String mime(Uint8List bytes) {
    if (bytes.length >= 12) {
      final prefix = latin1.decode(bytes.sublist(0, 12));
      if (prefix.startsWith('GIF87a') || prefix.startsWith('GIF89a')) {
        return 'image/gif';
      }
      if (prefix.startsWith('RIFF') && prefix.endsWith('WEBP')) {
        return 'image/webp';
      }
      if (prefix.startsWith('\x89PNG')) return 'image/png';
      if (bytes[0] == 255 && bytes[1] == 216) return 'image/jpeg';
    }
    throw StateError('Escolha JPG, PNG, GIF ou WebP.');
  }

  Future<Uint8List> preview(Uint8List bytes) async {
    for (final edge in [480, 240, 120]) {
      final codec = await ui.instantiateImageCodecWithSize(
        await ui.ImmutableBuffer.fromUint8List(bytes),
        getTargetSize: (w, h) {
          final scale = math.min(1.0, edge / math.max(w, h));
          return ui.TargetImageSize(
            width: math.max(1, (w * scale).round()),
            height: math.max(1, (h * scale).round()),
          );
        },
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          if (bytes.length <= 65536) return bytes;
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data != null && data.lengthInBytes <= 65536) {
            return data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
    throw StateError('Escolha uma imagem menor.');
  }

  Future<void> apply(
    String slot,
    Uint8List bytes, {
    required bool upload,
  }) async {
    final type = mime(bytes);
    final small = await preview(bytes);
    if (!active) return;
    if (upload && drive != null) await drive!.save(slot, bytes, type);
    final dir = await AppDirectoryService.getProfileMediaDirectory();
    final file = File(
      '${dir.path}/profile_${widget.uid}_${slot}_${DateTime.now().microsecondsSinceEpoch}',
    );
    await file.writeAsBytes(drive == null ? small : bytes);
    await File('${file.path}.preview').writeAsBytes(small);
    if (!active) return;
    final profile = StorageService.userProfile;
    await StorageService.updateUserProfile(
      slot == 'avatar'
          ? profile.copyWith(
              avatarImagePath: file.path,
              useBlobatarAsAvatar: upload ? false : profile.useBlobatarAsAvatar,
            )
          : profile.copyWith(bannerImagePath: file.path),
    );
  }

  Future<String> choose(String slot) async {
    final picked = await FilePicker.pickFile();
    if (picked == null) return 'Seleção cancelada.';
    if (picked.path != null &&
        await File(picked.path!).length() > ProfileDrive.limit) {
      throw StateError('Escolha uma imagem de até 16 MiB.');
    }
    final bytes = await picked.readAsBytes();
    if (bytes.length > ProfileDrive.limit) {
      throw StateError('Escolha uma imagem de até 16 MiB.');
    }
    await apply(slot, bytes, upload: true);
    if (!active) return '';
    final ok = await CloudSyncService.backupToCloud();
    return ok
        ? 'Imagem salva.'
        : 'Imagem salva neste aparelho. A sincronização da prévia está pendente.';
  }

  @override
  Widget build(BuildContext context) {
    Widget button(String label, Future<String> Function() action) => TextButton(
      onPressed: busy ? null : () => run(action),
      child: Text(label),
    );
    return ExpansionTile(
      title: const Text('Fotos e armazenamento'),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Foto e banner compactos de até 64 KiB cada. Conecte o Drive para manter originais e GIFs de até 16 MiB e guardar backups.',
          ),
        ),
        Wrap(
          children: [
            button(
              drive == null ? 'Conectar Google Drive' : 'Reconectar Drive',
              () async {
                final session = await ProfileDrive.connect();
                if (!active) {
                  session.close();
                  return '';
                }
                drive?.close();
                drive = session;
                return 'Drive conectado.';
              },
            ),
            if (drive != null)
              button('Usar originais do Drive', () async {
                final session = drive!;
                var found = false;
                for (final slot in ['avatar', 'banner']) {
                  final bytes = await session.read(slot);
                  if (bytes != null && active) {
                    await apply(slot, bytes, upload: false);
                    found = true;
                  }
                }
                return found
                    ? 'Originais carregados.'
                    : 'Nenhuma foto arquivada no Drive.';
              }),
            button('Alterar foto', () => choose('avatar')),
            button('Alterar banner', () => choose('banner')),
            if (drive != null)
              button('Salvar backup no Drive', () async {
                await drive!.save(
                  'backup',
                  utf8.encode(StorageService.exportFullBackupJson()),
                  'application/octet-stream',
                );
                return 'Backup salvo no Drive.';
              }),
            if (drive != null)
              button('Restaurar backup do Drive', () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Mesclar backup com a biblioteca?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Restaurar'),
                      ),
                    ],
                  ),
                );
                if (ok != true || !active) return 'Restauração cancelada.';
                final data = await drive!.read('backup');
                if (data == null) return 'Nenhum backup no Drive.';
                if (!active ||
                    !await StorageService.importFullBackupJson(
                      utf8.decode(data),
                      clearExisting: false,
                    )) {
                  throw StateError('Não foi possível restaurar o backup.');
                }
                return 'Backup restaurado.';
              }),
          ],
        ),
        if (busy || status.isNotEmpty)
          Semantics(liveRegion: true, child: Text(busy ? 'Aguarde…' : status)),
      ],
    );
  }
}
