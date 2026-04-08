import 'dart:async';
import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../models/scan_result.dart';
import '../models/daily_summary.dart';
import '../models/chat_message.dart';
import '../services/firebase_service.dart';
import 'package:intl/intl.dart';

class UserProvider with ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService();
  
  UserProfile? _profile;
  List<ScanResult> _scans = [];
  DailySummary? _dailySummary;
  List<ChatMessage> _messages = [];
  bool _isLoading = true;

  UserProfile? get profile => _profile;
  List<ScanResult> get scans => _scans;
  DailySummary? get dailySummary => _dailySummary;
  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;

  StreamSubscription? _profileSub;
  StreamSubscription? _scansSub;
  StreamSubscription? _summarySub;
  StreamSubscription? _messagesSub;

  void init(String uid) {
    _isLoading = true;
    notifyListeners();

    _profileSub?.cancel();
    _scansSub?.cancel();
    _summarySub?.cancel();
    _messagesSub?.cancel();

    _profileSub = _firebaseService.streamUserProfile(uid).listen((p) {
      _profile = p;
      _isLoading = false;
      notifyListeners();
    });

    _scansSub = _firebaseService.streamScans(uid).listen((s) {
      _scans = s;
      notifyListeners();
    });

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _summarySub = _firebaseService.streamDailySummary(uid, today).listen((ds) {
      _dailySummary = ds;
      notifyListeners();
    });

    _messagesSub = _firebaseService.streamMessages(uid).listen((m) {
      _messages = m;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _scansSub?.cancel();
    _summarySub?.cancel();
    _messagesSub?.cancel();
    super.dispose();
  }
}
