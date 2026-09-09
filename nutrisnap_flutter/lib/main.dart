import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() async {
  // App Bootstrap Flow
  WidgetsFlutterBinding.ensureInitialized();
  
  // NutriSnap AI runs 100% on-device with zero external cloud dependencies
  runApp(
    const ProviderScope(
      child: NutriSnapApp(),
    ),
  );
}
