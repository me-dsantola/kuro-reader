import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'cloud_auth_service.dart';

class _DriveClient extends http.BaseClient {
  final http.Client _client = http.Client();
  final GoogleSignInAccount account;
  final String uid;
  _DriveClient(this.account, this.uid);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('A conta mudou. Reconecte o Drive.');
    }
    request.headers.addAll(await account.authHeaders);
    return _client.send(request);
  }

  @override
  void close() => _client.close();
}

class ProfileDrive {
  final String uid;
  final _DriveClient _client;
  late final api = drive.DriveApi(_client);
  ProfileDrive._(this.uid, this._client);
  void close() => _client.close();

  static Future<ProfileDrive> connect() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Entre no YOMI.');
    final google = GoogleSignIn(
      serverClientId: CloudAuthService.serverClientId,
      scopes: ['email', 'profile'],
    );
    final account = await google.signIn();
    if (account == null) throw StateError('Conexão cancelada.');
    final tokens = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: tokens.idToken,
      accessToken: tokens.accessToken,
    );
    if (user.providerData.any((p) => p.providerId == 'google.com')) {
      await user.reauthenticateWithCredential(credential);
    } else {
      await user.linkWithCredential(credential);
    }
    if (!await google.requestScopes([drive.DriveApi.driveAppdataScope])) {
      throw StateError('Permissão do Drive não concedida.');
    }
    return ProfileDrive._(user.uid, _DriveClient(account, user.uid));
  }

  Future<String?> _find(String slot) async {
    final result = await api.files.list(
      spaces: 'appDataFolder',
      q: "trashed = false and name = 'yomi-$uid-$slot'",
      orderBy: 'modifiedTime desc',
      pageSize: 1,
      $fields: 'files(id)',
    );
    return result.files?.firstOrNull?.id;
  }

  static const limit = 16 * 1024 * 1024;
  Future<void> save(String slot, Uint8List bytes, String mime) async {
    if (bytes.length > limit) throw StateError('Limite de 16 MiB por arquivo.');
    final id = await _find(slot);
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: mime,
    );
    if (id == null) {
      await api.files.create(
        drive.File()
          ..name = 'yomi-$uid-$slot'
          ..parents = ['appDataFolder']
          ..mimeType = mime,
        uploadMedia: media,
      );
    } else {
      await api.files.update(
        drive.File()..mimeType = mime,
        id,
        uploadMedia: media,
      );
    }
  }

  Future<Uint8List?> read(String slot) async {
    final id = await _find(slot);
    if (id == null) return null;
    final media =
        await api.files.get(
              id,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;
    final data = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      if (data.length + chunk.length > limit) {
        throw StateError('Arquivo acima de 16 MiB.');
      }
      data.add(chunk);
    }
    return data.takeBytes();
  }
}
