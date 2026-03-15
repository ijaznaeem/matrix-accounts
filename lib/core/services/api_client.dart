import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  final String baseUrl;
  final SharedPreferences prefs;
  static const String _whatsappApiKey =
      'sk_5fdb92a0e35fc302d65009777e79f76fbadb78e6591bc2d5b50bbc69c72cc71a';

  ApiClient({
    required this.baseUrl,
    required this.prefs,
  });

  Future<bool>? _refreshInFlight;

  String? get token => prefs.getString('auth_token');
  String? get refreshToken => prefs.getString('refresh_token');
  String? get deviceId => prefs.getString('device_id');
  String get whatsappApiKey => _whatsappApiKey;

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        if (deviceId != null) 'X-Device-Id': deviceId!,
      };

  Map<String, String> get whatsappHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-API-Key': _whatsappApiKey,
        if (deviceId != null) 'X-Device-Id': deviceId!,
      };

  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    final response = await _sendWithAuthRetry(
      endpoint: endpoint,
      send: (requestHeaders) => http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: requestHeaders,
        body: jsonEncode(data),
      ),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    var uri = Uri.parse('$baseUrl$endpoint');
    if (queryParams != null) {
      uri = uri.replace(queryParameters: queryParams);
    }

    final response = await _sendWithAuthRetry(
      endpoint: endpoint,
      send: (requestHeaders) => http.get(uri, headers: requestHeaders),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> put(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    final response = await _sendWithAuthRetry(
      endpoint: endpoint,
      send: (requestHeaders) => http.put(
        Uri.parse('$baseUrl$endpoint'),
        headers: requestHeaders,
        body: jsonEncode(data),
      ),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> delete(String endpoint) async {
    final response = await _sendWithAuthRetry(
      endpoint: endpoint,
      send: (requestHeaders) => http.delete(
        Uri.parse('$baseUrl$endpoint'),
        headers: requestHeaders,
      ),
    );

    return _handleResponse(response);
  }

  Future<http.Response> _sendWithAuthRetry({
    required String endpoint,
    required Future<http.Response> Function(Map<String, String> requestHeaders)
        send,
  }) async {
    var response = await send(headers);

    if (_shouldAttemptRefresh(endpoint, response.statusCode)) {
      final refreshed = await _tryRefreshToken();
      if (refreshed) {
        response = await send(headers);
      }
    }

    return response;
  }

  bool _shouldAttemptRefresh(String endpoint, int statusCode) {
    if (statusCode != 401) {
      return false;
    }

    if ((refreshToken ?? '').isEmpty) {
      return false;
    }

    return endpoint != '/api/auth/login' &&
        endpoint != '/api/auth/register' &&
        endpoint != '/api/auth/refresh';
  }

  Future<bool> _tryRefreshToken() async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final completer = Completer<bool>();
    _refreshInFlight = completer.future;

    try {
      final storedRefreshToken = refreshToken;
      if (storedRefreshToken == null || storedRefreshToken.isEmpty) {
        completer.complete(false);
        return false;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (deviceId != null) 'X-Device-Id': deviceId!,
        },
        body: jsonEncode({
          'refresh_token': storedRefreshToken,
          if (deviceId != null) 'device_id': deviceId,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          await prefs.remove('auth_token');
          await prefs.remove('refresh_token');
        }
        completer.complete(false);
        return false;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        completer.complete(false);
        return false;
      }

      final newAccessToken = decoded['token']?.toString();
      final newRefreshToken = decoded['refresh_token']?.toString();

      if (newAccessToken == null ||
          newAccessToken.isEmpty ||
          newRefreshToken == null ||
          newRefreshToken.isEmpty) {
        completer.complete(false);
        return false;
      }

      await prefs.setString('auth_token', newAccessToken);
      await prefs.setString('refresh_token', newRefreshToken);

      completer.complete(true);
      return true;
    } catch (_) {
      completer.complete(false);
      return false;
    } finally {
      _refreshInFlight = null;
    }
  }

  // WhatsApp API specific methods
  Future<Map<String, dynamic>> sendWhatsAppMessage({
    required String phoneNumber,
    required String message,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/v1/send'),
      headers: whatsappHeaders,
      body: jsonEncode({
        'to': phoneNumber,
        'message': message,
      }),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> whatsappPost(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: whatsappHeaders,
      body: jsonEncode(data),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> whatsappGet(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    var uri = Uri.parse('$baseUrl$endpoint');
    if (queryParams != null) {
      uri = uri.replace(queryParameters: queryParams);
    }

    final response = await http.get(uri, headers: whatsappHeaders);
    return _handleResponse(response);
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    final body = response.body;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        throw ApiException(
          response.statusCode,
          'Invalid JSON object response: ${body.substring(0, body.length > 240 ? 240 : body.length)}',
        );
      } on FormatException {
        final snippet =
            body.substring(0, body.length > 240 ? 240 : body.length);
        throw ApiException(
          response.statusCode,
          'Non-JSON response from server: $snippet',
        );
      }
    }

    throw ApiException(
      response.statusCode,
      body,
    );
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String body;

  ApiException(this.statusCode, this.body);

  @override
  String toString() => 'ApiException: $statusCode - $body';
}
