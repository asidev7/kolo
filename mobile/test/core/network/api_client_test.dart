import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/network/api_client.dart';

void main() {
  group('ApiClient — préfixe /api/v1', () {
    test("l'origine nue reçoit le préfixe de version", () {
      final client = ApiClient(baseUrl: 'https://api.example.com');
      expect(client.dio.options.baseUrl, 'https://api.example.com/api/v1');
    });

    test('une barre oblique finale est neutralisée', () {
      final client = ApiClient(baseUrl: 'https://api.example.com/');
      expect(client.dio.options.baseUrl, 'https://api.example.com/api/v1');
    });

    test('baseUrl exposé reste l’origine nue (config d’entrée)', () {
      final client = ApiClient(baseUrl: 'https://api.example.com');
      expect(client.baseUrl, 'https://api.example.com');
    });

    test('mode local : baseUrl vide reste vide (aucun préfixe)', () {
      final client = ApiClient(baseUrl: '');
      expect(client.dio.options.baseUrl, '');
    });
  });
}
