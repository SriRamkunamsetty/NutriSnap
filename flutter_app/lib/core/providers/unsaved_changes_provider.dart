import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks if there are unsaved changes on any screen (like Settings).
/// Used to prevent accidental navigation loss.
final unsavedChangesProvider = StateProvider<bool>((ref) => false);
