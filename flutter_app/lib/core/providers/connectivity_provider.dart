import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Real on-device network reachability signal (no cloud backend involved).
/// Used to gate cloud-AI escalation and to show the "Offline Mode" banner —
/// on-device Gemma inference and local storage work identically either way.
final isOnlineProvider = StreamProvider<bool>((ref) {
  final connectivity = Connectivity();
  return connectivity.onConnectivityChanged.map(
    (results) => results.any((r) => r != ConnectivityResult.none),
  );
});
