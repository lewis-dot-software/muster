import 'checkout_path.dart';
import 'command.dart';
import 'hosted_codebase.dart';

/// The command that unpacks [codebase]'s package at its version into
/// [checkout], from the host `PUB_HOSTED_URL` names and pub.dev where it is
/// unset, unresolved: `dart pub unpack`, whichever toolchain resolves it,
/// since Flutter's `pub` has no `unpack`.
Command unpackCommand(HostedCodebase codebase, CheckoutPath checkout) => (
  executable: .dart,
  arguments: [
    'pub',
    'unpack',
    '${codebase.package.name}@${codebase.version.version}',
    '--no-resolve',
    '--output=${checkout.path}',
  ],
);
