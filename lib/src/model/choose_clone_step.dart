import 'clone_state.dart';
import 'clone_step.dart';

/// The act the cache takes next on a clone in [state], [fetched] where it
/// has fetched the clone already: a missing clone cloned, one lacking the
/// pin's commit fetched once, then given up on, and one holding it used
/// untouched.
CloneStep chooseCloneStep(CloneState state, {required bool fetched}) =>
    switch (state) {
      .missing => .clone,
      .lacking => fetched ? .pinMissing : .fetch,
      .holding => .use,
    };
