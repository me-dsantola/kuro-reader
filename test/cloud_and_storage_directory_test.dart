import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/services/app_directory_service.dart';
import 'package:kuro_reader/services/cloud_auth_service.dart';
import 'package:kuro_reader/services/cloud_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kuro_test_storage_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('AppDirectoryService', () {
    test('resolves downloads and covers directories', () async {
      final downloadsDir = await AppDirectoryService.getDownloadsDirectory();
      expect(downloadsDir.existsSync(), isTrue);

      final chaptersDir = await AppDirectoryService.getChaptersDirectory();
      expect(chaptersDir.path, contains('chapters'));
      expect(chaptersDir.existsSync(), isTrue);

      final coversDir = await AppDirectoryService.getCoversDirectory();
      expect(coversDir.path, contains('covers'));
      expect(coversDir.existsSync(), isTrue);

      final candidates = await AppDirectoryService.getAllCandidateBaseDirectories();
      expect(candidates.isNotEmpty, isTrue);
    });
  });

  group('CloudAuthService & CloudSyncService Safe Fallbacks', () {
    test('defaults to null user and handles missing Firebase gracefully', () async {
      expect(CloudAuthService.currentUser.value, isNull);
      expect(CloudSyncService.syncStatus.value, equals(CloudSyncStatus.idle));

      // Attempting backup without authentication must fail safely without throwing
      final backupResult = await CloudSyncService.backupToCloud();
      expect(backupResult, isFalse);

      final restoreResult = await CloudSyncService.restoreFromCloud();
      expect(restoreResult, isFalse);
    });
  });
}
