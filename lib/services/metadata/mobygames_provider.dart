import 'package:dio/dio.dart';

import 'metadata_provider.dart';
import 'mobygames_client.dart';

/// Credential slot only. Scores are filled by the background walk, so this
/// provider does not take part in description lookups.
class MobyGamesProvider extends GameMetadataProvider {
  MobyGamesProvider({MobyGamesClient? client})
      : _client = client ?? MobyGamesClient();

  final MobyGamesClient _client;

  @override
  bool get suppliesDescriptions => false;

  @override
  MetadataProviderInfo get info => const MetadataProviderInfo(
        id: 'mobygames',
        name: 'MobyGames',
      );

  @override
  List<CredentialField> get credentialFields => const [
        CredentialField(key: 'api_key', label: 'API key', obscure: true),
      ];

  @override
  Future<String?> validateCredentials(Map<String, String> creds) async {
    final key = creds['api_key']?.trim() ?? '';
    if (key.isEmpty) return 'Enter an API key';
    try {
      await _client.validate(key);
      return null;
    } on MobyUnauthorized {
      return 'MobyGames rejected that API key';
    } on MobyRateLimited {
      return 'MobyGames is rate limiting. Wait a moment and try again';
    } on DioException {
      return 'Could not reach MobyGames';
    } catch (_) {
      return 'Could not reach MobyGames';
    }
  }

  @override
  Future<MetadataResult> fetch({
    required String title,
    required String platform,
    required Map<String, String> creds,
  }) async {
    return const MetadataNoMatch();
  }
}
