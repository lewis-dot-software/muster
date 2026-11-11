import 'checkout_path.dart';

/// The file of a checkout's stamp, the record of what resolved it.
extension type const StampPath._(String path) {
  /// The stamp of [checkout], beside it, its directory's name with `.stamp`
  /// after it.
  static StampPath beside(CheckoutPath checkout) =>
      ._('${checkout.path}.stamp');
}
