// Generated from the published contract's x-persisted-query-id by scripts/generate-contract.sh. Do not edit.
//
// The gateway enforces a persisted-query allowlist: clients POST { id, variables } and the id is the
// lowercase-hex SHA-256 of the canonical query text. An id the gateway has not registered is rejected 403,
// so these must never drift from the published contract — they are generated, never hand-typed.

class PersistedOp {
  final String id;
  final String path;
  const PersistedOp(this.id, this.path);
}

class PersistedQueries {
  static const departures = PersistedOp(
      'e4ae3f49e06982173b38e945c3c02ef113be05e12564145faeade7758295f536',
      'departures');
  static const plan = PersistedOp(
      '679549e87f9653ff7a5a021c0b329a2c9658d4701c836139e63712dd9b77981f',
      'plan');
  static const planstream = PersistedOp(
      '40380fc4cf10397a4c20d039cc9428b73757c7fce0de2072ae1685a43efbfc15',
      'plan-stream');
  static const trip = PersistedOp(
      '4a10717f45697a241a0843902808cd696eb8ffd102e93238bf753f865d939a3f',
      'trip');
}
