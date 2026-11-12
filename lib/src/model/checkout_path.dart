import 'claim_path.dart';
import 'codebase_name.dart';
import 'consumer_root.dart';
import 'os.dart';
import 'stamp_path.dart';

/// The directory of one codebase's checkout, under its consumer's root.
extension type const CheckoutPath._(({String path, Os os}) _checkout) {
  /// The checkout of the codebase [name] under [root]:
  /// `.dart_tool/muster/<name>`.
  static CheckoutPath of(ConsumerRoot root, CodebaseName name) => ._((
    path: root.os.paths.join(root.path, '.dart_tool', 'muster', name.name),
    os: root.os,
  ));

  /// The checkout's path.
  String get path => _checkout.path;

  /// The system whose paths the checkout, and every path inside it, is
  /// written in.
  Os get os => _checkout.os;

  /// The checkout's stamp, the file beside it named `<name>.stamp`.
  StampPath get stamp => .beside(this);

  /// The claim on the checkout, the file beside it named `<name>.claim`.
  ClaimPath get claim => .ofCheckout(this);
}
