import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../app_version.dart';
import '../models/manga_models.dart';
import 'app_directory_service.dart';
import 'cloud_auth_service.dart';
import 'profile_palette_service.dart';
import 'storage_service.dart';
import 'backup_codec.dart';

enum CloudSyncStatus { idle, syncing, success, error, unconfigured }

/// Orchestrates cloud backup and restore with Cloud Firestore.
/// Retains the offline-first design: local Hive remains the source of truth,
/// and Firestore acts as the cloud mirror whenever online and authenticated.
class CloudSyncService {
  static final ValueNotifier<CloudSyncStatus> syncStatus =
      ValueNotifier<CloudSyncStatus>(CloudSyncStatus.idle);
  static final ValueNotifier<DateTime?> lastCloudSyncTime =
      ValueNotifier<DateTime?>(null);
  static final ValueNotifier<String?> syncErrorMessage =
      ValueNotifier<String?>(null);

  static const String lastCloudSyncKey = 'last_cloud_sync_at_v1';
  static Timer? _debounceTimer;
  static bool _restoringCloud = false;

  /// Initializes cloud sync listeners and reads previous sync timestamp.
  static void initialize() {
    if (StorageService.settingsBox.isOpen) {
      final storedTime = StorageService.settingsBox.get(lastCloudSyncKey);
      if (storedTime is String) {
        lastCloudSyncTime.value = DateTime.tryParse(storedTime);
      }
    }

    // When the user logs in, listen for cloud backup availability
    CloudAuthService.currentUser.addListener(() {
      final user = CloudAuthService.currentUser.value;
      if (user != null) {
        // Auto-check cloud backup metadata upon sign-in
        unawaited(checkCloudBackupMetadata());
      }
    });
  }

  /// Checks if a cloud backup exists in Firestore for the currently logged-in user.
  static Future<Map<String, dynamic>?> checkCloudBackupMetadata() async {
    final user = CloudAuthService.currentUser.value;
    if (user == null || !CloudAuthService.isFirebaseAvailable.value) return null;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists || doc.data() == null) return null;
      final data = doc.data()!;
      // Confirma que os dados da nuvem pertencem a este email se presente
      if (data['userEmail'] != null &&
          user.email != null &&
          (data['userEmail'] as String).toLowerCase() != user.email!.toLowerCase()) {
        debugPrint('Backup em nuvem com email conflitante ignorado.');
        return null;
      }
      return {
        'updatedAt': data['updatedAtLocal'] ?? '',
        'favoritesCount': data['favoritesCount'] ?? 0,
        'historyCount': data['historyCount'] ?? 0,
        'appVersion': data['appVersion'] ?? '',
        'userEmail': data['userEmail'] ?? '',
        'profileName': data['userDisplayName'] ?? (data['profile'] is Map ? data['profile']['name'] : null),
      };
    } catch (e) {
      debugPrint('Erro ao verificar metadados no Firestore: $e');
      return null;
    }
  }

  static const int _maxCloudImageBytes = 250 * 1024;
  static const int _maxFirestoreBudgetBytes = 800 * 1024;

  static Future<String?> _readEncodedMediaUnderLimit(
    String? rawPath, {
    bool ignorePreset = false,
  }) async {
    if (kIsWeb) return null;
    final path = rawPath?.trim();
    if (path == null ||
        path.isEmpty ||
        path.startsWith('http://') ||
        path.startsWith('https://') ||
        (ignorePreset && path.startsWith('preset:'))) {
      return null;
    }
    try {
      final preview = File('$path.preview');
      final mediaDir = await AppDirectoryService.getProfileMediaDirectory();
      final managed = File(path).parent.absolute.path == mediaDir.absolute.path &&
          File(path).uri.pathSegments.last.startsWith('profile_');
      final file = managed && await preview.exists() ? preview : File(path);
      if (!file.existsSync()) return null;
      if (await file.length() > _maxCloudImageBytes) return null;
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > _maxCloudImageBytes) return null;
      return base64Encode(bytes);
    } catch (e) {
      debugPrint('Erro ao ler mídia de perfil para nuvem: $e');
      return null;
    }
  }

  /// Sends full local backup payload to Cloud Firestore with conflict-safe
  /// timestamp merge and size protection for the 1 MB Firestore limit.
  static Future<bool> backupToCloud({bool silent = false}) async {
    if (_restoringCloud) return false;
    final user = CloudAuthService.currentUser.value;
    if (user == null) {
      if (!silent) syncErrorMessage.value = 'Nenhum usuário conectado.';
      return false;
    }
    if (!CloudAuthService.isFirebaseAvailable.value) {
      if (!silent) syncErrorMessage.value = 'Firebase não disponível.';
      return false;
    }

    try {
      if (!silent) syncStatus.value = CloudSyncStatus.syncing;
      final localRawPayload = StorageService.exportFullBackupJson();
      final localDecoded = BackupCodec.decode(localRawPayload);

      final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final existingSnap = await docRef.get();

      Map<String, dynamic> mergedDecoded = localDecoded;
      bool cloudIsNewer = false;

      if (existingSnap.exists && existingSnap.data() != null) {
        final existingData = existingSnap.data()!;
        if (existingData['userEmail'] != null &&
            user.email != null &&
            (existingData['userEmail'] as String).toLowerCase() !=
                user.email!.toLowerCase()) {
          if (!silent) {
            syncStatus.value = CloudSyncStatus.error;
            syncErrorMessage.value =
                'Os dados na nuvem pertencem a outra conta de email.';
          }
          return false;
        }

        final existingPayload = existingData['payload'];
        if (existingPayload is String && existingPayload.trim().isNotEmpty) {
          try {
            final cloudDecoded = BackupCodec.decode(existingPayload);
            final remoteAt = DateTime.tryParse(
              (existingData['updatedAtLocal'] ?? '').toString(),
            );
            final localSyncAt = lastCloudSyncTime.value;
            cloudIsNewer =
                remoteAt != null &&
                (localSyncAt == null || remoteAt.isAfter(localSyncAt));

            mergedDecoded = BackupCodec.mergeCloudAndLocal(
              cloudDecoded,
              localDecoded,
              cloudIsNewer: cloudIsNewer,
            );
          } catch (e) {
            debugPrint('Aviso ao mesclar backup existente na nuvem: $e');
          }
        }
      }

      final compacted = BackupCodec.stripEphemeralCacheForCloud(mergedDecoded);
      final mergedRawPayload = BackupCodec.encode(compacted);

      if (cloudIsNewer) {
        _restoringCloud = true;
        try {
          await StorageService.importFullBackupJson(
            mergedRawPayload,
            clearExisting: false,
          );
          await ProfilePaletteService.refreshGlobalPalette(
            StorageService.userProfile,
          );
        } finally {
          _restoringCloud = false;
        }
      }

      final profile = StorageService.userProfile;
      String? avatarBase64 = await _readEncodedMediaUnderLimit(
        profile.avatarImagePath,
      );
      String? bannerBase64 = await _readEncodedMediaUnderLimit(
        profile.bannerImagePath,
        ignorePreset: true,
      );

      final payloadBytes = utf8.encode(mergedRawPayload).length +
          utf8.encode(jsonEncode(compacted['profile'])).length;
      if (payloadBytes > _maxFirestoreBudgetBytes) {
        throw StateError('Backup grande demais para sincronizar. Salve o backup completo no Google Drive pelo perfil.');
      }
      if (payloadBytes +
              (avatarBase64?.length ?? 0) +
              (bannerBase64?.length ?? 0) >
          _maxFirestoreBudgetBytes) {
        bannerBase64 = null;
      }
      if (payloadBytes + (avatarBase64?.length ?? 0) >
          _maxFirestoreBudgetBytes) {
        avatarBase64 = null;
      }

      final now = DateTime.now();
      final settings = compacted['settings'] as Map? ?? {};
      final readingLists = settings['user_reading_lists'] as List? ?? [];
      final profileMap = compacted['profile'] as Map?;
      final mascotName =
          profileMap?['blobatarName']?.toString().trim().isNotEmpty == true
              ? profileMap!['blobatarName'].toString().trim()
              : profile.effectiveBlobatarName;

      await docRef.set({
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtLocal': now.toIso8601String(),
        'appVersion': kAppVersion,
        'appBuild': kAppBuildNumber,
        'uid': user.uid,
        'userEmail': user.email,
        'userDisplayName': user.displayName,
        'payload': mergedRawPayload,
        'profile': compacted['profile'],
        'avatarBase64': ?avatarBase64,
        'bannerBase64': ?bannerBase64,
        'hasCustomAvatar': avatarBase64 != null,
        'hasCustomBanner': bannerBase64 != null,
        'favoritesCount': (compacted['favorites'] as Map?)?.length ?? 0,
        'historyCount': (compacted['history'] as Map?)?.length ?? 0,
        'readingListsCount': readingLists.length,
        'mascotName': mascotName,
      }, SetOptions(merge: true));

      await StorageService.setActiveUserUid(user.uid);

      lastCloudSyncTime.value = now;
      if (StorageService.settingsBox.isOpen) {
        await StorageService.settingsBox.put(
          lastCloudSyncKey,
          now.toIso8601String(),
        );
      }

      syncStatus.value = CloudSyncStatus.success;
      syncErrorMessage.value = null;
      return true;
    } catch (e) {
      syncStatus.value = CloudSyncStatus.error;
      syncErrorMessage.value = 'Erro ao sincronizar na nuvem: $e';
      debugPrint('Erro Firestore backup: $e');
      return false;
    }
  }

  /// Restores complete state from Cloud Firestore into local Hive.
  static Future<bool> restoreFromCloud() async {
    final user = CloudAuthService.currentUser.value;
    if (user == null) {
      syncErrorMessage.value = 'Faça login com sua conta Google primeiro.';
      return false;
    }
    if (!CloudAuthService.isFirebaseAvailable.value) {
      syncErrorMessage.value = 'Firebase não configurado.';
      return false;
    }

    _restoringCloud = true;
    syncStatus.value = CloudSyncStatus.syncing;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists || doc.data() == null) {
        syncStatus.value = CloudSyncStatus.error;
        syncErrorMessage.value = 'Nenhum backup em nuvem encontrado nesta conta.';
        return false;
      }

      final data = doc.data()!;
      // Garante que o documento recuperado não pertença a outro email
      if (data['userEmail'] != null &&
          user.email != null &&
          (data['userEmail'] as String).toLowerCase() != user.email!.toLowerCase()) {
        syncStatus.value = CloudSyncStatus.error;
        syncErrorMessage.value = 'Os dados na nuvem pertencem a outra conta de email.';
        return false;
      }

      final payload = data['payload'];
      if (payload is! String || payload.trim().isEmpty) {
        syncStatus.value = CloudSyncStatus.error;
        syncErrorMessage.value = 'Dados de backup corrompidos na nuvem.';
        return false;
      }

      // Limpa dados locais residuais de qualquer sessão anterior antes de restaurar
      await StorageService.clearUserDataForNewSession();
      final ok = await StorageService.importFullBackupJson(payload.trim(), clearExisting: true);
      if (ok) {
        await StorageService.setActiveUserUid(user.uid);
        // Restore custom avatar and banner if present in Firestore
        var currentProfile = StorageService.profileNotifier.value;
        bool profileModified = false;

        if (!kIsWeb) {
          final avatarBase64 = data['avatarBase64'];
          if (avatarBase64 is String && avatarBase64.isNotEmpty) {
            try {
              final bytes = base64Decode(avatarBase64);
              final mediaDir = await AppDirectoryService.getProfileMediaDirectory();
              final avFile = File('${mediaDir.path}/avatar_${user.uid}.jpg');
              await avFile.writeAsBytes(bytes, flush: true);
              currentProfile = currentProfile.copyWith(avatarImagePath: avFile.path);
              profileModified = true;
            } catch (e) {
              debugPrint('Falha ao restaurar foto de perfil da nuvem: $e');
            }
          }

          final bannerBase64 = data['bannerBase64'];
          if (bannerBase64 is String && bannerBase64.isNotEmpty) {
            try {
              final bytes = base64Decode(bannerBase64);
              final mediaDir = await AppDirectoryService.getProfileMediaDirectory();
              final banFile = File('${mediaDir.path}/banner_${user.uid}.jpg');
              await banFile.writeAsBytes(bytes, flush: true);
              currentProfile = currentProfile.copyWith(bannerImagePath: banFile.path);
              profileModified = true;
            } catch (e) {
              debugPrint('Falha ao restaurar banner da nuvem: $e');
            }
          }
        }

        // Fill Google name / photo if profile still has default values
        if (!currentProfile.isConfigured || currentProfile.name == 'Leitor YOMI') {
          if (user.displayName != null && user.displayName!.isNotEmpty) {
            currentProfile = currentProfile.copyWith(name: user.displayName);
            profileModified = true;
          }
        }
        if (currentProfile.avatarImagePath == null &&
            user.photoURL != null &&
            user.photoURL!.isNotEmpty) {
          currentProfile = currentProfile.copyWith(avatarImagePath: user.photoURL);
          profileModified = true;
        }

        if (profileModified) {
          await StorageService.updateUserProfile(currentProfile);
          await ProfilePaletteService.refreshGlobalPalette(currentProfile);
        }

        final now = DateTime.now();
        lastCloudSyncTime.value = now;
        if (StorageService.settingsBox.isOpen) {
          await StorageService.settingsBox.put(
            lastCloudSyncKey,
            now.toIso8601String(),
          );
        }
        syncStatus.value = CloudSyncStatus.success;
        syncErrorMessage.value = null;
        return true;
      } else {
        syncStatus.value = CloudSyncStatus.error;
        syncErrorMessage.value = 'Falha ao restaurar dados locais.';
        return false;
      }
    } catch (e) {
      syncStatus.value = CloudSyncStatus.error;
      syncErrorMessage.value = 'Erro ao baixar backup da nuvem: $e';
      return false;
    } finally {
      _restoringCloud = false;
    }
  }

  /// Automatically schedules a background cloud backup when local data changes.
  static void scheduleAutoCloudSync() {
    if (_restoringCloud) return;
    if (CloudAuthService.currentUser.value == null) return;
    if (!CloudAuthService.isFirebaseAvailable.value) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 4), () {
      unawaited(backupToCloud(silent: true));
    });
  }

  /// Cancela qualquer sincronização pendente e zera os estados de sincronização.
  static void cancelPendingSync() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    syncStatus.value = CloudSyncStatus.idle;
    lastCloudSyncTime.value = null;
    syncErrorMessage.value = null;
  }

  /// Limpa integralmente o backup na nuvem (Firestore) do usuário atual
  /// e redefine o armazenamento local para um perfil recém-criado,
  /// permitindo que o usuário comece 100% do zero.
  static Future<bool> resetCloudData() async {
    final user = CloudAuthService.currentUser.value;
    if (user == null || !CloudAuthService.isFirebaseAvailable.value) return false;

    try {
      syncStatus.value = CloudSyncStatus.syncing;
      final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await docRef.delete();
      await StorageService.clearUserDataForNewSession();
      final freshProfile = UserProfile(
        name: (user.displayName != null && user.displayName!.trim().isNotEmpty)
            ? user.displayName!.trim()
            : 'Leitor YOMI',
        avatarImagePath: user.photoURL,
        isConfigured: false,
      );
      await StorageService.updateUserProfile(freshProfile);
      await ProfilePaletteService.refreshGlobalPalette(freshProfile);
      await StorageService.setActiveUserUid(user.uid);
      syncStatus.value = CloudSyncStatus.idle;
      lastCloudSyncTime.value = null;
      syncErrorMessage.value = null;
      return true;
    } catch (e) {
      debugPrint('Erro ao resetar dados na nuvem: $e');
      syncStatus.value = CloudSyncStatus.error;
      syncErrorMessage.value = 'Erro ao limpar dados na nuvem: $e';
      return false;
    }
  }
}
