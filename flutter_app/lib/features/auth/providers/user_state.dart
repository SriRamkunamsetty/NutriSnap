import 'package:equatable/equatable.dart';

import '../../../core/models/user_profile.dart';

/// State of the single on-device profile. NutriSnap has no accounts or login:
/// the profile *is* the user.
class UserState extends Equatable {
  final UserProfile? profile;
  final bool isLoading;
  final String? errorMessage;

  const UserState({
    this.profile,
    this.isLoading = false,
    this.errorMessage,
  });

  bool get hasCompletedOnboarding => profile?.hasCompletedOnboarding ?? false;

  UserState copyWith({
    UserProfile? profile,
    bool? isLoading,
    String? errorMessage,
    bool clearProfile = false,
    bool clearError = false,
  }) {
    return UserState(
      profile: clearProfile ? null : profile ?? this.profile,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [profile, isLoading, errorMessage];
}
