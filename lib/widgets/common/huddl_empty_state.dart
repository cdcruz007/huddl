// COMPATIBILITY SHIM — do not add new call sites.
// Use HuddlEmptyState from lib/widgets/huddl_character.dart directly for all new code.
//
// Re-exporting HuddlEmptyState, HuddlMood, and HuddlIllustration from
// huddl_character.dart ensures any screen importing from this file
// automatically uses the correct mood-based, animated implementation.

export '../huddl_character.dart' show HuddlEmptyState, HuddlMood;

// HuddlIllustration — kept as a static-path reference class for onboarding
// screens that use direct Image.asset() (not HuddlEmptyState parameters).
// Do NOT pass HuddlIllustration.* values as illustration: params to any widget.
abstract class HuddlIllustration {
  static const chat        = 'assets/illustrations/chatting.png';
  static const community   = 'assets/illustrations/community_wave.png';
  static const meetup      = 'assets/illustrations/group_celebration.png';
  static const events      = 'assets/illustrations/calendar.png';
  static const feed        = 'assets/illustrations/waving_phone.png';
  static const marketplace = 'assets/illustrations/announcement.png';
  static const marketplaceEmpty = 'assets/illustrations/search_found.png';
  static const groupsEmpty = 'assets/illustrations/search_found.png';
  static const saved       = 'assets/illustrations/search_found.png';
  static const auth        = 'assets/illustrations/security.png';
  static const upgrade     = 'assets/illustrations/growth.png';
}
