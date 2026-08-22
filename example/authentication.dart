// Authentication examples for the Spider Dart SDK. The docs site inlines the
// named regions below (between the START/END markers) as code samples.
import 'dart:io';
import 'package:spider_sdk/spider_sdk.dart';

/// Keep the API key out of source — read it from the environment.
SpiderClient authenticated() {
  // [START authenticated]
  final apiKey = Platform.environment['SPIDER_API_KEY'] ?? '';
  final client = SpiderClient('https://your-env-slug.api.tiducto.eu', apiKey);
  // [END authenticated]
  return client;
}

/// Each environment is its own hostname + key, so target them with their own
/// clients.
(SpiderClient, SpiderClient) targeting() {
  // [START targeting]
  final staging = SpiderClient(
    'https://your-env-staging.api.tiducto.eu',
    Platform.environment['SPIDER_STAGING_KEY'] ?? '',
  );

  final production = SpiderClient(
    'https://your-env-production.api.tiducto.eu',
    Platform.environment['SPIDER_PRODUCTION_KEY'] ?? '',
  );
  // [END targeting]
  return (staging, production);
}
