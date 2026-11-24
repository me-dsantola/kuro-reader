/// Versão do app enviada para a nuvem e exibida no Portal Companion.
///
/// Deve ser idêntica ao campo `version:` do pubspec.yaml
/// (`kAppVersion+kAppBuildNumber`). O teste `test/app_version_test.dart`
/// falha no CI se os dois divergirem, então lembre de atualizar aqui
/// sempre que fizer bump de versão.
const String kAppVersion = '1.4.0';
const int kAppBuildNumber = 24;
