import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  test('Laravel API health check', () async {
    final response = await http.get(
      Uri.parse('http://127.0.0.1:8000/api/health'),
    );

    print('Status code: ${response.statusCode}');
    print('Response body: ${response.body}');

    expect(response.statusCode, 200);

    final data = jsonDecode(response.body);
    expect(data['status'], 'ok');
  });

  test('Laravel API user registration', () async {
    final response = await http.post(
      Uri.parse('http://127.0.0.1:8000/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': 'Flutter Test User',
        'email': 'flutter_test_${DateTime.now().millisecondsSinceEpoch}@example.com',
        'password': 'password123',
        'password_confirmation': 'password123',
      }),
    );

    print('Registration status code: ${response.statusCode}');
    print('Registration response: ${response.body}');

    expect(response.statusCode, 201);

    final data = jsonDecode(response.body);
    expect(data['user'], isNotNull);
    expect(data['token'], isNotNull);
  }, timeout: const Timeout(Duration(seconds: 10)));
}
