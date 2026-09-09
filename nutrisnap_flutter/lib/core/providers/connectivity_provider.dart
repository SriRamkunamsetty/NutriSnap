import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Simple provider to check if we can reach Firestore
final isOnlineProvider = StreamProvider<bool>((ref) {
  // Firestore has a built-in mechanism to track connection state
  return FirebaseFirestore.instance
      .collection('.info')
      .doc('connected')
      .snapshots()
      .map((snapshot) => snapshot.data()?['connected'] == true);
});
