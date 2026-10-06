@TestOn('vm')
library;

import 'package:spider_sdk/src/transport.dart' show backgroundDecodeMinLength;
import 'package:test/test.dart';

import 'spider_sdk_test.dart' as sdk;

// The whole suite again with every response decoded on a background isolate, so a decoder that captures
// something an isolate cannot be sent fails here rather than only on a production-sized response.
void main() {
  setUpAll(() => backgroundDecodeMinLength = 0);
  sdk.main();
}
