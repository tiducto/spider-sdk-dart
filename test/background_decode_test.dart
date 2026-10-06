@TestOn('vm')
library;

import 'package:spider_sdk/src/transport.dart' show backgroundDecodeMinLength;
import 'package:test/test.dart';

import 'spider_sdk_test.dart' as sdk;

void main() {
  setUpAll(() => backgroundDecodeMinLength = 0);
  sdk.main();
}
