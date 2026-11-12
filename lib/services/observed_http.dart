import 'dart:convert';
import 'package:http/http.dart' as http;
import 'device_state_service.dart';

/// Retains the existing HTTP client and request behavior, adding local feedback.
class ObservedHttp {
  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 12),
  }) => DeviceStateService.instance.observe(() {
    if (DeviceStateService.instance.isOffline) {
      throw http.ClientException(
        'Modo offline: recurso disponível após reconectar.',
        url,
      );
    }
    return http.get(url, headers: headers).timeout(timeout);
  });

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => DeviceStateService.instance.observe(() {
    if (DeviceStateService.instance.isOffline) {
      throw http.ClientException(
        'Modo offline: recurso disponível após reconectar.',
        url,
      );
    }
    return http
        .post(url, headers: headers, body: body, encoding: encoding)
        .timeout(const Duration(seconds: 12));
  });
}
