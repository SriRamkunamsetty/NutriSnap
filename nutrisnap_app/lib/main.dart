import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';

void main() async {
  // 1. App Bootstrap Flow
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Initialize Core Services (e.g. Firebase) 
  // Make sure you place GoogleService-Info.plist and google-services.json natively.
  await Firebase.initializeApp();

  // 3. ProviderScope Setup wrapping our root
  runApp(
    const ProviderScope(
      child: NutriSnapApp(),
    ),
  );
}
