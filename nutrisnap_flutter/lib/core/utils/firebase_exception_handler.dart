import 'package:flutter/foundation.dart';

class FirebaseExceptionHandler {
  static String handleException(dynamic exception, [String context = '']) {
    String message = 'An unexpected error occurred.';
    
    if (exception != null) {
      final str = exception.toString();
      if (str.contains('user-not-found') || str.contains('wrong-password')) {
        message = 'Invalid email or password.';
      } else if (str.contains('email-already-in-use')) {
        message = 'An account already exists with that email.';
      } else if (str.contains('weak-password')) {
        message = 'The password provided is too weak.';
      } else {
        message = str.replaceAll('Exception: ', '');
      }
    }

    debugPrint('🔒 Local Service Message [$context]: $message\nRaw: $exception');
    return message;
  }
}
