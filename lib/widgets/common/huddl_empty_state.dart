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
  static const chat             = 'assets/illustrations/chat_high_five.webp';
  static const community        = 'assets/illustrations/community_wave.webp';
  static const meetup           = 'assets/illustrations/celebrating_phone.webp';
  static const events           = 'assets/illustrations/calendar.webp';
  static const feed             = 'assets/illustrations/waving_phone.webp';
  static const marketplace      = 'assets/illustrations/mobile_store.webp';
  static const marketplaceEmpty = 'assets/illustrations/search_found.webp';
  static const groupsEmpty      = 'assets/illustrations/community_wave.webp';
  static const saved            = 'assets/illustrations/waving_thumbs.webp';
  static const auth             = 'assets/illustrations/security.webp';
  static const upgrade          = 'assets/illustrations/growth_yellow.webp';
}
