import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class IgdbCredentials {
  final String clientId;
  final String clientSecret;

  const IgdbCredentials({this.clientId = '', this.clientSecret = ''});

  bool get ready => clientId.isNotEmpty && clientSecret.isNotEmpty;
}

class IgdbCredentialStore {
  IgdbCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const _key = 'igdb.credentials.v1';
  final FlutterSecureStorage _storage;

  Future<IgdbCredentials> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return const IgdbCredentials();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const IgdbCredentials();
      return IgdbCredentials(
        clientId: '${decoded['client_id'] ?? ''}'.trim(),
        clientSecret: '${decoded['client_secret'] ?? ''}'.trim(),
      );
    } catch (_) {
      return const IgdbCredentials();
    }
  }

  Future<void> write(IgdbCredentials credentials) async {
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'client_id': credentials.clientId.trim(),
        'client_secret': credentials.clientSecret.trim(),
      }),
    );
  }

  Future<void> clear() => _storage.delete(key: _key);
}
