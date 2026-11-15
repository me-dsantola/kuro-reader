import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/app_version.dart';

void main() {
  test('kAppVersion e kAppBuildNumber batem com o pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', multiLine: true)
        .firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml sem campo version válido');
    expect(kAppVersion, match!.group(1),
        reason: 'Atualize lib/app_version.dart para a versão do pubspec.yaml');
    expect(kAppBuildNumber, int.parse(match.group(2)!),
        reason: 'Atualize kAppBuildNumber em lib/app_version.dart');
  });
}
