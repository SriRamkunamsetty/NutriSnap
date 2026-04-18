import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebaseExceptionHandler {
  static String handleException(dynamic exception, [String context = '']) {
    String message = 'An unknown error occurred.';
    
    if (exception is FirebaseAuthException) {
      message = _handleAuthException(exception);
    } else if (exception is FirebaseException) {
      message = _handleFirestoreException(exception);
    } else {
      message = exception.toString();
    }

    debugPrint('🔥 Firebase Error [$context]: $message\nRaw: $exception');
    return message;
  }

  static String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'email-already-in-use':
        return 'An account already exists with that email.';
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'requires-recent-login':
        return 'Please log in again before trying this operation.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      default:
        return e.message ?? 'Authentication failed.';
    }
  }

  static String _handleFirestoreException(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'You do not have permission to perform this action.';
      case 'unavailable':
        return 'The service is currently unavailable. Please check your connection.';
      case 'not-found':
        return 'The requested document was not found.';
      default:
        return e.message ?? 'A database error occurred.';
    }
  }
}
