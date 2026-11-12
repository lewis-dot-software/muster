import '../model/fetch_outcome.dart';

/// [failure] as the failure a load would meet it as.
FetchFailure asFetchFailure(ActFailure failure) => switch (failure) {
  final CommandFailed failed => failed,
  final Unstartable unstartable => unstartable,
  final StoreFailed failed => failed,
  final PinMissing missing => missing,
};
