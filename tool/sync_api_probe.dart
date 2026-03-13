import 'dart:convert';
import 'dart:io';

class ProbeConfig {
  final String baseUrl;
  final String email;
  final String password;
  final int companyId;
  final String deviceId;

  ProbeConfig({
    required this.baseUrl,
    required this.email,
    required this.password,
    required this.companyId,
    required this.deviceId,
  });
}

Future<void> main(List<String> args) async {
  final config = _parseArgs(args);
  if (config == null) {
    _printUsage();
    exitCode = 64;
    return;
  }

  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 20);

  try {
    print('=== Sync API Probe ===');
    print('Base URL: ${config.baseUrl}');
    print('Company ID: ${config.companyId}');
    print('Device ID: ${config.deviceId}');
    print('');

    final loginResponse = await _postJson(
      client: client,
      url: Uri.parse('${config.baseUrl}/api/auth/login'),
      body: {
        'email': config.email,
        'password': config.password,
        'device_id': config.deviceId,
      },
      headers: {'Accept': 'application/json'},
    );

    _printResponse('POST /api/auth/login', loginResponse);

    final token = _extractToken(loginResponse.jsonBody);
    if (token == null || token.isEmpty) {
      print('\n[FAIL] No auth token returned. Cannot continue.');
      exitCode = 1;
      return;
    }

    final authHeaders = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    final companiesResponse = await _get(
      client: client,
      url: Uri.parse('${config.baseUrl}/api/companies'),
      headers: authHeaders,
    );
    _printResponse('GET /api/companies', companiesResponse);

    final statusUri = Uri.parse(
      '${config.baseUrl}/api/sync/status?company_id=${config.companyId}&device_id=${Uri.encodeComponent(config.deviceId)}',
    );

    final statusResponse = await _get(
      client: client,
      url: statusUri,
      headers: authHeaders,
    );
    _printResponse('GET /api/sync/status', statusResponse);

    final pullResponse = await _postJson(
      client: client,
      url: Uri.parse('${config.baseUrl}/api/sync/pull'),
      headers: authHeaders,
      body: {
        'company_id': config.companyId,
        'device_id': config.deviceId,
        'last_version': 0,
      },
    );
    _printResponse('POST /api/sync/pull (last_version=0)', pullResponse);

    if (pullResponse.statusCode >= 500 || statusResponse.statusCode >= 500) {
      print('\n[FAIL] Server returned 5xx on sync endpoint(s).');
      exitCode = 2;
      return;
    }

    print('\n[OK] Probe completed.');
  } catch (error, stackTrace) {
    print('\n[EXCEPTION] $error');
    print(stackTrace);
    exitCode = 3;
  } finally {
    client.close(force: true);
  }
}

ProbeConfig? _parseArgs(List<String> args) {
  final map = <String, String>{};
  for (var index = 0; index < args.length; index++) {
    final token = args[index];
    if (!token.startsWith('--')) continue;

    final key = token.substring(2);
    if (index + 1 < args.length && !args[index + 1].startsWith('--')) {
      map[key] = args[index + 1];
      index++;
    } else {
      map[key] = 'true';
    }
  }

  final baseUrl = map['base-url'];
  final email = map['email'];
  final password = map['password'];
  final companyIdRaw = map['company-id'];
  final deviceId = map['device-id'] ??
      'sync-api-probe-${DateTime.now().millisecondsSinceEpoch}';

  final companyId = int.tryParse(companyIdRaw ?? '');
  if (baseUrl == null ||
      email == null ||
      password == null ||
      companyId == null) {
    return null;
  }

  return ProbeConfig(
    baseUrl: baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl,
    email: email,
    password: password,
    companyId: companyId,
    deviceId: deviceId,
  );
}

void _printUsage() {
  print('Usage:');
  print(
      '  dart run tool/sync_api_probe.dart \\\n    --base-url https://veyo.octavions.com \\\n    --email admin@veyo.com \\\n    --password <PASSWORD> \\\n    --company-id 1 \\\n    [--device-id probe-device-1]');
}

String? _extractToken(dynamic jsonBody) {
  if (jsonBody is! Map<String, dynamic>) return null;
  final value = jsonBody['token'];
  return value?.toString();
}

class HttpResult {
  final int statusCode;
  final Map<String, List<String>> headers;
  final String rawBody;
  final dynamic jsonBody;

  HttpResult({
    required this.statusCode,
    required this.headers,
    required this.rawBody,
    required this.jsonBody,
  });
}

Future<HttpResult> _get({
  required HttpClient client,
  required Uri url,
  required Map<String, String> headers,
}) async {
  final request = await client.getUrl(url);
  headers.forEach(request.headers.set);
  final response = await request.close();
  final rawBody = await response.transform(utf8.decoder).join();
  return _toResult(response, rawBody);
}

Future<HttpResult> _postJson({
  required HttpClient client,
  required Uri url,
  required Map<String, dynamic> body,
  Map<String, String>? headers,
}) async {
  final request = await client.postUrl(url);
  final mergedHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    ...?headers,
  };
  mergedHeaders.forEach(request.headers.set);
  request.write(jsonEncode(body));
  final response = await request.close();
  final rawBody = await response.transform(utf8.decoder).join();
  return _toResult(response, rawBody);
}

HttpResult _toResult(HttpClientResponse response, String rawBody) {
  dynamic jsonBody;
  try {
    jsonBody = jsonDecode(rawBody);
  } catch (_) {
    jsonBody = null;
  }

  final headers = <String, List<String>>{};
  response.headers.forEach((name, values) {
    headers[name] = values;
  });

  return HttpResult(
    statusCode: response.statusCode,
    headers: headers,
    rawBody: rawBody,
    jsonBody: jsonBody,
  );
}

void _printResponse(String label, HttpResult result) {
  print('--- $label ---');
  print('HTTP ${result.statusCode}');

  final contentType = result.headers['content-type']?.join(', ');
  if (contentType != null) {
    print('Content-Type: $contentType');
  }

  if (result.jsonBody != null) {
    final pretty = const JsonEncoder.withIndent('  ').convert(result.jsonBody);
    print(pretty);
  } else {
    final snippet = result.rawBody.length > 1200
        ? '${result.rawBody.substring(0, 1200)}\n...<truncated>'
        : result.rawBody;
    print(snippet);
  }

  print('');
}
