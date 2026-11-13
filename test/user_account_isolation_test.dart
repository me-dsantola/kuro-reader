import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/services/cloud_sync_service.dart';
import 'package:kuro_reader/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('yomi_isolation_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(StorageService.favBoxName);
    await Hive.openBox(StorageService.historyBoxName);
    await Hive.openBox(StorageService.downloadsBoxName);
    await Hive.openBox(StorageService.settingsBoxName);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('StorageService isolates activeUserUid per account', () async {
    expect(StorageService.activeUserUid, isNull);

    await StorageService.setActiveUserUid('user_abc_123');
    expect(StorageService.activeUserUid, equals('user_abc_123'));

    await StorageService.setActiveUserUid('user_xyz_789');
    expect(StorageService.activeUserUid, equals('user_xyz_789'));

    await StorageService.setActiveUserUid(null);
    expect(StorageService.activeUserUid, isNull);
  });

  test('clearUserDataForNewSession clears all data and leaves profile unconfigured', () async {
    // Populate User A's data
    await StorageService.favBox.put('manga_1', {
      'id': 'manga_1',
      'title': 'Solo Leveling',
    });
    await StorageService.historyBox.put('manga_1', {
      'mangaId': 'manga_1',
      'title': 'Solo Leveling',
      'chapter': '10',
      'readAt': DateTime.now().toIso8601String(),
    });
    await StorageService.downloadsBox.put('ch_1', {'path': '/path/1'});
    await StorageService.settingsBox.put(StorageService.readingListsKey, [
      {'id': 'list_1', 'name': 'Lendo agora'}
    ]);
    const userAProfile = UserProfile(
      name: 'Davi Santiago',
      avatarImagePath: '/path/avatar.jpg',
      isConfigured: true,
    );
    await StorageService.updateUserProfile(userAProfile);
    expect(StorageService.favBox.isNotEmpty, isTrue);
    expect(StorageService.historyBox.isNotEmpty, isTrue);
    expect(StorageService.userProfile.isConfigured, isTrue);

    // Clear session for a new user
    await StorageService.clearUserDataForNewSession();

    expect(StorageService.favBox.isEmpty, isTrue);
    expect(StorageService.historyBox.isEmpty, isTrue);
    expect(StorageService.downloadsBox.isEmpty, isTrue);
    expect(StorageService.settingsBox.get(StorageService.readingListsKey), isNull);
    expect(StorageService.userProfile.isConfigured, isFalse);
  });

  test('importFullBackupJson with clearExisting: true replaces old user data completely', () async {
    // Old data from User A
    await StorageService.favBox.put('manga_old', {
      'id': 'manga_old',
      'title': 'Old Manga',
    });

    // New backup from User B
    await StorageService.clearUserDataForNewSession();
    await StorageService.favBox.put('manga_new', {
      'id': 'manga_new',
      'title': 'New Manga',
    });
    final backupPayload = StorageService.exportFullBackupJson();

    // Re-populate User A's data
    await StorageService.favBox.clear();
    await StorageService.favBox.put('manga_old', {
      'id': 'manga_old',
      'title': 'Old Manga',
    });

    // Import User B's backup with clearExisting: true
    final ok = await StorageService.importFullBackupJson(backupPayload, clearExisting: true);
    expect(ok, isTrue);

    // User A's manga_old MUST NOT exist anymore
    expect(StorageService.favBox.containsKey('manga_old'), isFalse);
    expect(StorageService.favBox.containsKey('manga_new'), isTrue);
  });

  test('CloudSyncService cancelPendingSync resets sync state', () {
    CloudSyncService.cancelPendingSync();
    expect(CloudSyncService.syncStatus.value, equals(CloudSyncStatus.idle));
    expect(CloudSyncService.lastCloudSyncTime.value, isNull);
    expect(CloudSyncService.syncErrorMessage.value, isNull);
  });
}
