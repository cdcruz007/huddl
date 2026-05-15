import '../services/onboarding_data_service.dart';

/// Centralised member photo resolution service.
///
/// All fake/hardcoded member name → photo mappings have been removed.
/// Photos are resolved only from:
///   1. The current user's actual profile photo (from OnboardingDataService)
///   2. A gender-appropriate default avatar based on parentType
///
/// Real member photos from other users come directly from their Firestore
/// profile documents (photoUrl field) and are passed through the UI by
/// the relevant service (FirestoreService, RealtimeDMService, etc.).
class MemberPhotoService {
  MemberPhotoService._();

  // ── Gender-based default avatars ──────────────────────────────────────
  // Male-presenting Pexels avatar for dads / unknown male
  static const String defaultDadAvatar =
      'https://images.pexels.com/photos/220453/pexels-photo-220453.jpeg?auto=compress&cs=tinysrgb&w=200';
  // Female-presenting Pexels avatar for mums / unknown female
  static const String defaultMumAvatar =
      'https://images.pexels.com/photos/774909/pexels-photo-774909.jpeg?auto=compress&cs=tinysrgb&w=200';

  /// Resolves a photo URL for a given display name.
  /// Returns the current user's photo if the name matches,
  /// otherwise returns null (let the UI render an initials avatar instead).
  static String? getPhotoByName(String name) {
    // Check if name matches current user
    final onboarding = OnboardingDataService();
    final currentName = onboarding.name;
    if (currentName != null &&
        name.toLowerCase() == currentName.toLowerCase()) {
      return onboarding.profilePhotoObjectUrl;
    }
    if (name == 'You') {
      return onboarding.profilePhotoObjectUrl;
    }
    // Unknown name — return null so caller renders an initials avatar
    return null;
  }

  /// Returns true if [name] matches the current onboarding user name or 'You'.
  static bool isCurrentUser(String name) {
    final onboarding = OnboardingDataService();
    final currentName = onboarding.name;
    if (name == 'You') return true;
    if (currentName != null &&
        name.toLowerCase() == currentName.toLowerCase()) {
      return true;
    }
    return false;
  }

  /// Returns the local asset path for the current user's default avatar
  /// based on parentType (mum / dad). Used when no profile photo is set.
  static String get currentUserAvatarAsset {
    final parentType = OnboardingDataService().parentType;
    return parentType == 'dad'
        ? 'assets/images/avatars/John.png'
        : 'assets/images/avatars/Emma.png';
  }

  /// Returns the correct default avatar based on the current user's parentType.
  static String _defaultAvatarForCurrentUser() {
    final onboarding = OnboardingDataService();
    final parentType = onboarding.parentType;
    if (parentType == 'dad') return defaultDadAvatar;
    return defaultMumAvatar;
  }

  /// Returns a gender-appropriate default avatar for a given parentType hint.
  static String getDefaultAvatar({String? parentType}) {
    if (parentType == 'dad') return defaultDadAvatar;
    return defaultMumAvatar;
  }

  /// Resolves a photo URL by member ID.
  /// Only the current user ('current_user') is resolved to a real photo.
  /// All other IDs return the default avatar — real photos come from Firestore.
  static String? getPhotoByMemberId(String memberId) {
    if (memberId == 'current_user') {
      return OnboardingDataService().profilePhotoObjectUrl ??
          _defaultAvatarForCurrentUser();
    }
    // Real member photos are fetched from Firestore — not faked here
    return null;
  }
}
