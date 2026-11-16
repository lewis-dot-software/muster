import 'package:grit/grit.dart';
import 'package:muster/src/model/checkout_found.dart';
import 'package:muster/src/model/checkout_step.dart';
import 'package:muster/src/model/choose_checkout_step.dart';
import 'package:muster/src/model/choose_clone_step.dart';
import 'package:muster/src/model/clone_state.dart';
import 'package:muster/src/model/clone_step.dart';
import 'package:test/test.dart';

/// The acts [chooseCloneStep] takes on a clone the cache first reads as
/// [first], in order, read again after each act as the cache reads it,
/// holding the pin's commit after a clone afresh where [cloneHolds] and
/// after a fetch where [fetchHolds], through its last, [CloneStep.use] or
/// [CloneStep.pinMissing].
List<CloneStep> _steps(
  CloneState first, {
  required bool cloneHolds,
  required bool fetchHolds,
}) {
  final List<CloneStep> steps = [];
  CloneState state = first;
  bool fetched = false;
  while (steps.length < 4) {
    final CloneStep step = chooseCloneStep(state, fetched: fetched);
    steps.add(step);
    switch (step) {
      case .clone:
        state = cloneHolds ? .holding : .lacking;
      case .fetch:
        fetched = true;
        state = fetchHolds ? .holding : .lacking;
      case .use || .pinMissing:
        return steps;
    }
  }
  fail('no last step in $steps');
}

void main() {
  property(
    'A clone that is missing is cloned, one that lacks the pin\'s commit is '
    'fetched, and one that holds it is left untouched.',
    (Draw draw) {
      final CloneState first = draw(
        .element(CloneState.values),
        label: 'first',
      );
      final bool cloneHolds = draw(.boolean(), label: 'cloneHolds');
      final bool fetchHolds = draw(.boolean(), label: 'fetchHolds');
      final List<CloneStep> steps = _steps(
        first,
        cloneHolds: cloneHolds,
        fetchHolds: fetchHolds,
      );
      expect(steps.first, switch (first) {
        .missing => CloneStep.clone,
        .lacking => CloneStep.fetch,
        .holding => CloneStep.use,
      });
      expect(steps.where((CloneStep s) => s == .clone).length, lessThan(2));
      expect(steps.where((CloneStep s) => s == .fetch).length, lessThan(2));
      final bool holds = switch (steps.reversed.skip(1).firstOrNull) {
        null => true,
        .clone => cloneHolds,
        .fetch => fetchHolds,
        .use || .pinMissing => fail('a step after the last in $steps'),
      };
      expect(steps.last, holds ? CloneStep.use : CloneStep.pinMissing);
      expect(
        steps.contains(CloneStep.pinMissing),
        steps.contains(CloneStep.fetch) && !holds,
      );
    },
    settings: .new(runs: 100),
  );

  property(
    'A checkout that is a worktree of its URL\'s clone is moved to its pin, '
    'and any other is removed and added afresh.',
    (Draw draw) {
      final CheckoutFound found = draw(
        .element(CheckoutFound.values),
        label: 'found',
      );
      expect(
        chooseCheckoutStep(found),
        found == .worktreeOfClone ? CheckoutStep.move : CheckoutStep.replace,
      );
    },
  );
}
