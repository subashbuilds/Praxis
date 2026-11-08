/// Independent Phase 1 switches. Every flag defaults on in a development build
/// and can be turned off without a code change, for example:
///
/// ```sh
/// flutter run --dart-define=PRAXIS_PREFETCH=false
/// flutter run --dart-define=PRAXIS_COMPOUND_TOOLS=false
/// ```
///
/// The flags are deliberately separate so a change that does not reduce model
/// rounds can be left off without disabling the other improvements.
class Phase1Flags {
  const Phase1Flags({
    this.contextPrefetch = true,
    this.compoundTools = true,
    this.batchedExecution = true,
    this.loopGuards = true,
    this.resultSizing = true,
  });

  static const defaults = Phase1Flags(
    contextPrefetch: bool.fromEnvironment(
      'PRAXIS_PREFETCH',
      defaultValue: true,
    ),
    compoundTools: bool.fromEnvironment(
      'PRAXIS_COMPOUND_TOOLS',
      defaultValue: true,
    ),
    batchedExecution: bool.fromEnvironment(
      'PRAXIS_BATCHED_EXECUTION',
      defaultValue: true,
    ),
    loopGuards: bool.fromEnvironment(
      'PRAXIS_LOOP_GUARDS',
      defaultValue: true,
    ),
    resultSizing: bool.fromEnvironment(
      'PRAXIS_RESULT_SIZING',
      defaultValue: true,
    ),
  );

  static const disabled = Phase1Flags(
    contextPrefetch: false,
    compoundTools: false,
    batchedExecution: false,
    loopGuards: false,
    resultSizing: false,
  );

  final bool contextPrefetch;
  final bool compoundTools;
  final bool batchedExecution;
  final bool loopGuards;
  final bool resultSizing;

  /// Repeated calls are stopped on the third identical attempt by default.
  static const int repeatLimit = 3;

  /// The read-only tools that are safe to run concurrently when the provider
  /// returns several calls in one reply.
  static const Set<String> readOnlyTools = {
    'read_file',
    'read_files',
    'list_files',
    'search_and_read',
  };
}
