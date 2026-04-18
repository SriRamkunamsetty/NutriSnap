import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();

  factory FirebaseService() {
    return _instance;
  }

  FirebaseService._internal();

  FirebaseAuth get auth => FirebaseAuth.instance;
  FirebaseFirestore get db => FirebaseFirestore.instance;
  FirebaseStorage get storage => FirebaseStorage.instance;

  Future<void> testConnection() async {
    try {
      await db.collection('test').doc('connection').get(const GetOptions(source: Source.server));
    } catch (e) {
      if (e.toString().contains('the client is offline')) {
        print("Please check your Firebase configuration. The client is offline.");
      }
    }
  }
}

final firebaseService = FirebaseService();
