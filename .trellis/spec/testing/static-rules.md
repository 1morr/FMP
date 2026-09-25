# Static-rule tests

A static-rule test reads `lib/` source to hold a boundary that behaviour tests
cannot see. List them with
`find test -name '*_static_rule_test.dart'`; each file's top dartdoc is the
rule's rationale. AGENTS.md names only the ones an agent is most likely to trip.

Prefer a behavioural test when one can observe the rule (`20a96dc9`, `175e5d2a`
replaced static rules with behaviour tests).

## Placement

A test that opens a `lib/` path is named `*_static_rule_test.dart` and lives in
`test/support/` (cross-layer) or `test/<layer>/static_rules/` (one layer) —
gated by `test/support/static_rule_placement_static_rule_test.dart`, with no
exception list.

## Anatomy

Follow `test/support/outbound_hosts_static_rule_test.dart` or
`test/support/periodic_timer_static_rule_test.dart` (older rules such as
`isar_boundary_static_rule_test.dart` predate points 1 and 6):

1. **Top dartdoc is the rationale**, with the issue or commit that motivated it,
   then `library;`.
2. **Strip comments first** with `stripDartComments(source)` from
   `test/support/dart_source.dart`. It understands string literals, so a URL is not
   treated as a comment.
3. **Exceptions are a `const` map of path or name → reason**
   (`_lowerLayerExceptions`, `_anchoredProviders`, `_hosts`; `_timers` maps to
   `_Periodic` records that also say who asked and whether it can be turned off).
   A bare path list needs the reasons in the dartdoc above it.
4. **Stale-exception test**: every entry must still exist or still be needed, so
   an exception that stopped applying turns red.
5. **Scan sanity**: `expect(scanned, greaterThan(N))`, so a wrong path cannot
   make the offender list silently empty. Normalise paths with
   `.replaceAll('\\', '/')`.
6. **Compare sets, not substring presence**: the found set must equal the
   declared set, so one extra and one missing are both red (`12c487ab`).
7. **Two-way mutation tests inside the file**, in their own group: feed a
   synthesised violation to the detector and assert it is caught; feed a harmless
   variant — comment, reformatting, line break, look-alike name — and assert it is
   not. Detectors are public top-level functions (`upwardImportOffenders`,
   `fixedPumpOffenders`) so they can take strings. A rule that only asserts that
   source contains a string fails the second half.
8. The failure `reason:` says what to do instead.

## When a rule fires on your change

Fix the code. If the exception is legitimate, add the entry with a real reason
in the same commit. When the thing an entry names goes away, delete the entry. A
rule whose last consumer is gone is deleted together with the code it guarded.
