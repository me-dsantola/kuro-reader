import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
      return {
        'updatedAt': data['updatedAtLocal'] ?? '',
        'favoritesCount': data['favoritesCount'] ?? 0,
        'historyCount': data['historyCount'] ?? 0,
        'appVersion': data['appVersion'] ?? '',
      };
    } catch (e) {
      debugPrint('Erro ao verificar metadados no Firestore: $e');
      return null;
    }
  }

  /// Sends full local backup payload to Cloud Firestore.
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
      final rawPayload = StorageService.exportFullBackupJson();
      final decoded = BackupCodec.decode(rawPayload);

      final profile = StorageService.userProfile;
      String? avatarBase64;
      String? bannerBase64;

      if (!kIsWeb) {
        // Encode custom avatar image to Base64 (up to 600KB)
        final avPath = profile.avatarImagePath?.trim();
        if (avPath != null &&
            avPath.isNotEmpty &&
            !avPath.startsWith('http://') &&
            !avPath.startsWith('https://')) {
          try {
            final avFile = File(avPath);
            if (avFile.existsSync()) {
              final bytes = await avFile.readAsBytes();
              if (bytes.lengthInBytes <= 600 * 1024) {
                avatarBase64 = base64Encode(bytes);
              }
            }
          } catch (e) {
            debugPrint('Erro ao ler foto de perfil para nuvem: $e');
          }
        }

        // Encode custom banner image to Base64 (up to 600KB)
        final banPath = profile.bannerImagePath?.trim();
        if (banPath != null &&
            banPath.isNotEmpty &&
            !banPath.startsWith('http://') &&
            !banPath.startsWith('https://') &&
            !banPath.startsWith('preset:')) {
          try {
            final banFile = File(banPath);
            if (banFile.existsSync()) {
              final bytes = await banFile.readAsBytes();
              if (bytes.lengthInBytes <= 600 * 1024) {
                bannerBase64 = base64Encode(bytes);
              }
            }
          } catch (e) {
            debugPrint('Erro ao ler banner para nuvem: $e');
          }
        }
      }

      final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final now = DateTime.now();
      final settings = decoded['settings'] as Map? ?? {};
      final readingLists = settings['user_reading_lists'] as List? ?? [];

      await docRef.set({
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtLocal': now.toIso8601String(),
        'appVersion': '1.2.7',
        'payload': rawPayload,
        'profile': decoded['profile'],
        'avatarBase64': ?avatarBase64,
        'bannerBase64': ?bannerBase64,
        'hasCustomAvatar': avatarBase64 != null,
        'hasCustomBanner': bannerBase64 != null,
        'favoritesCount': (decoded['favorites'] as Map?)?.length ?? 0,
        'historyCount': (decoded['history'] as Map?)?.length ?? 0,
        'readingListsCount': readingLists.length,
        'mascotName': profile.effectiveBlobatarName,
        'userEmail': user.email,
        'userDisplayName': user.displayName,
      }, SetOptions(merge: true));

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
      final payload = data['payload'];
      if (payload is! String || payload.trim().isEmpty) {
        syncStatus.value = CloudSyncStatus.error;
        syncErrorMessage.value = 'Dados de backup corrompidos na nuvem.';
        return false;
      }

      final ok = await StorageService.importFullBackupJson(payload.trim());
      if (ok) {
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
}
