import 'package:glados/glados.dart';
import 'package:muster/src/model/checkout_found.dart';
import 'package:muster/src/model/checkout_step.dart';
import 'package:muster/src/model/choose_checkout_step.dart';
import 'package:muster/src/model/choose_clone_step.dart';
import 'package:muster/src/model/clone_state.dart';
import 'package:muster/src/model/clone_step.dart';

/// A clone as the cache first reads it, and whether a clone afresh and a
/// fetch would each leave it holding the pin's commit.
typedef _Clone = ({CloneState first, bool cloneHolds, bool fetchHolds});

final Generator<_Clone> _clone = any.combine3(
  any.choose(CloneState.values),
  any.bool,
  any.bool,
  (CloneState first, bool cloneHolds, bool fetchHolds) =>
      (first: first, cloneHolds: cloneHolds, fetchHolds: fetchHolds),
);

/// The acts [chooseCloneStep] takes on [clone], in order, read again after
/// each act as the cache reads it, through its last, [CloneStep.use] or
/// [CloneStep.pinMissing].
List<CloneStep> _steps(_Clone clone) {
  final List<CloneStep> steps = [];
  CloneState state = clone.first;
  bool fetched = false;
  while (steps.length < 4) {
    final CloneStep step = chooseCloneStep(state, fetched: fetched);
    steps.add(step);
    switch (step) {
      case .clone:
        state = clone.cloneHolds ? .holding : .lacking;
      case .fetch:
        fetched = true;
        state = clone.fetchHolds ? .holding : .lacking;
      case .use || .pinMissing:
        return steps;
    }
  }
  fail('no last step in $steps');
}

void main() {
  Glados(_clone, .new(numRuns: 100)).test(
    'A clone that is missing is cloned, one that lacks the pin\'s commit is '
    'fetched, and one that holds it is left untouched.',
    (_Clone clone) {
      final List<CloneStep> steps = _steps(clone);
      expect(steps.first, switch (clone.first) {
        .missing => CloneStep.clone,
        .lacking => CloneStep.fetch,
        .holding => CloneStep.use,
      });
      expect(steps.where((CloneStep s) => s == .clone).length, lessThan(2));
      expect(steps.where((CloneStep s) => s == .fetch).length, lessThan(2));
      final bool holds = switch (steps.reversed.skip(1).firstOrNull) {
        null => true,
        .clone => clone.cloneHolds,
        .fetch => clone.fetchHolds,
        .use || .pinMissing => fail('a step after the last in $steps'),
      };
      expect(steps.last, holds ? CloneStep.use : CloneStep.pinMissing);
      expect(
        steps.contains(CloneStep.pinMissing),
        steps.contains(CloneStep.fetch) && !holds,
      );
    },
  );

  Glados(any.choose(CheckoutFound.values)).test(
    'A checkout that is a worktree of its URL\'s clone is moved to its pin, '
    'and any other is removed and added afresh.',
    (CheckoutFound found) {
      expect(
        chooseCheckoutStep(found),
        found == .worktreeOfClone ? CheckoutStep.move : CheckoutStep.replace,
      );
    },
  );
}
