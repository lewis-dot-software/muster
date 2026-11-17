import 'checkout_found.dart';
import 'checkout_step.dart';

/// How a git checkout where [found] stands is made again at its pin: a
/// worktree of its URL's clone moved, and anything else removed and added
/// afresh.
CheckoutStep chooseCheckoutStep(CheckoutFound found) => switch (found) {
  .worktreeOfClone => .move,
  .nothing || .other => .replace,
};
