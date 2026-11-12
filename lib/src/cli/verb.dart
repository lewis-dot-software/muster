/// A command the `muster` command line names.
enum Verb {
  /// `muster fetch`.
  fetch('Brings every codebase to its pin, resolved, and prints a row each.'),

  /// `muster lock`.
  lock('Writes the kept locks lacking, and removes those none names.');

  const Verb(this.summary);

  /// What the command does, as its usage gives it.
  final String summary;
}
