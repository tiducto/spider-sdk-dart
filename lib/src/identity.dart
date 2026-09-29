import 'version.dart';

// Identity headers sent on every request. `apikey` carries the raw key; the two telemetry headers let the
// gateway track contract/SDK adoption. `x-spider-sdk` is `<lang>/<semver>`.
const contractHeader = 'x-spider-contract-version';
const sdkHeader = 'x-spider-sdk';
const sdkIdentity = 'dart/$sdkVersion';
