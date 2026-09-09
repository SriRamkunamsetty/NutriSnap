import 'package:equatable/equatable.dart';
import '../../../../core/models/user_profile.dart';

class LocalUser extends Equatable {
  final String uid;
  final String email;
  final String displayName;
  final String? photoURL;
  final bool emailVerified;

  const LocalUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoURL,
    this.emailVerified = true,
  });

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'email': email,
    'displayName': displayName,
    'photoURL': photoURL,
    'emailVerified': emailVerified,
  };

  factory LocalUser.fromMap(Map<String, dynamic> map) => LocalUser(
    uid: map['uid'] as String? ?? 'local_user_default',
    email: map['email'] as String? ?? 'private.user@on-device.local',
    displayName: map['displayName'] as String? ?? 'NutriSnap User',
    photoURL: map['photoURL'] as String?,
    emailVerified: map['emailVerified'] as bool? ?? true,
  );

  @override
  List<Object?> get props => [uid, email, displayName, photoURL, emailVerified];
}

class UserState extends Equatable {
  final LocalUser? authUser;
  final UserProfile? profile;
  final bool isLoading;
  final String? errorMessage;

  const UserState({
    this.authUser,
    this.profile,
    this.isLoading = false,
    this.errorMessage,
  });

  // Backward compatibility alias for UI elements referencing firebaseUser
  LocalUser? get firebaseUser => authUser;

  UserState copyWith({
    LocalUser? authUser,
    UserProfile? profile,
    bool? isLoading,
    String? errorMessage,
    bool clearAuthUser = false,
    bool clearProfile = false,
    bool clearError = false,
  }) {
    return UserState(
      authUser: clearAuthUser ? null : authUser ?? this.authUser,
      profile: clearProfile ? null : profile ?? this.profile,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [authUser, profile, isLoading, errorMessage];
}
