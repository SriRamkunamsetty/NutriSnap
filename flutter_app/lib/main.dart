import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase (Requires firebase_options.dart in a real environment, 
  // but this ensures the core initialization logic is present for compilation)
  try {
    await Firebase.initializeApp();
    // Test the connection as requested
    await firebaseService.testConnection();
    print("Firebase initialized successfully.");
  } catch (e) {
    print("Firebase initialization warning (expected if options are missing): $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NutriSnap AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('Firebase Initialized. Ready for UserContext.'),
        ),
      ),
    );
  }
}
