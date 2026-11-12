import 'checkout_path.dart';
import 'clone_path.dart';

/// The file a claim on one clone or one checkout is held on, beside what it
/// claims.
extension type const ClaimPath._(String path) {
  /// The claim on [checkout], its directory's name with `.claim` after it.
  static ClaimPath ofCheckout(CheckoutPath checkout) =>
      ._('${checkout.path}.claim');

  /// The claim on [clone], its directory's name with `.claim` after it.
  static ClaimPath ofClone(ClonePath clone) => ._('${clone.path}.claim');
}
