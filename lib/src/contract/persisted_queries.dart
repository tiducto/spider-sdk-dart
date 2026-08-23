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
      '70a644fe3c6b2cbf5b2d70cef8230c1428bea6357ae1766772162d86469563d0',
      'departures');
  static const plan = PersistedOp(
      'dad4f190af803a8cb50ec99c5852544297e94db8edc0d94220c8f79d98f065a7',
      'plan');
  static const trip = PersistedOp(
      'e8959a8d47a8e8437ee3ec740cd9c3e28bd401efdd236dde0502559daea53920',
      'trip');
}
