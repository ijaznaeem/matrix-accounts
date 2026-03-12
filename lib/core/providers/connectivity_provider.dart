import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams connectivity changes from the device.
final connectivityStreamProvider =
    StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// `true` when any non-none connectivity result is active.
/// Defaults to `true` until the first event arrives.
final isOnlineProvider = Provider<bool>((ref) {
  final connectivity = ref.watch(connectivityStreamProvider);
  return connectivity.maybeWhen(
    data: (results) =>
        results.isNotEmpty && results.any((r) => r != ConnectivityResult.none),
    orElse: () => true,
  );
});
