import 'contract/contract_version.dart';
import 'errors.dart';
import 'version.dart';

// Identity headers sent on every request. `apikey` carries the raw key; the two telemetry headers let the
// gateway track contract/SDK adoption. `x-spider-sdk` is `<lang>/<semver>`.
const contractHeader = 'x-spider-contract-version';
const sdkHeader = 'x-spider-sdk';
const sdkIdentity = 'dart/$sdkVersion';

/// The major component of a `major.minor` version string (`5.0` -> `5`).
String majorVersion(String version) {
  final dot = version.indexOf('.');
  return dot < 0 ? version : version.substring(0, dot);
}

/// Compares only the MAJOR contract component against what the gateway declared. A missing/empty header is a
/// no-op; a major mismatch throws [SpiderContractMismatchError], escaping the [SpiderResult] channel.
void checkContract(String? declaredByGateway) {
  if (declaredByGateway == null || declaredByGateway.isEmpty) return;
  if (majorVersion(contractVersion) != majorVersion(declaredByGateway)) {
    throw SpiderContractMismatchError(contractVersion, declaredByGateway);
  }
}
