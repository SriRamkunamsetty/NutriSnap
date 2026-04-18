import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/models/user_profile.dart';

class UserState extends Equatable {
  final User? authUser;
  final UserProfile? profile;
  // Note: scans and daily summary removed from base User/Auth state.
  // In Riverpod, lists and histories are handled better in isolated feature providers 
  // rather than a monolithic context block.
  final bool isLoading;
  final String? errorMessage;

  const UserState({
    this.authUser,
    this.profile,
    this.isLoading = false,
    this.errorMessage,
  });

  UserState copyWith({
    User? authUser,
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
