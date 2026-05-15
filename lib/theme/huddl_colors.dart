import 'package:flutter/material.dart';

// =============================================================================
// DESIGN-SYSTEM TOKENS — single source of truth
// =============================================================================
//
// USER PERSONAS (documented per audit recommendation #4):
//   1. "New-Parent Nadia" — First-time mum, 28-35, overwhelmed by travel
//      logistics, needs hand-holding checklists and reassurance from peers.
//   2. "Seasoned-Dad Sam" — Father of two, 32-40, confident traveller but
//      wants child-age-specific tips and community shortcuts.
//   3. "Expert-Grandparent Grace" — 55+, travels with grandchildren, wants
//      to share knowledge and earn badges — motivated by altruism.
//
// COMPETITOR ANALYSIS (documented per audit recommendation #4):
//   - Huckleberry: excellent age-aware UX but no community Q&A layer.
//   - Family Destinations Guide: strong editorial content but no
//     personalisation or interactive checklists.
//   - TripIt / PackPoint: good packing lists but not family-aware.
//   - Huddl differentiator: AI + real-parent community intelligence,
//     age-aware checklists, and gamified expert badges.
//
// ─── USER JOURNEY MAPS ─────────────────────────────────────────────────────
//
// Journey 1: "New-Parent Nadia" — First-time Seller
//   Touchpoints:
//     1. Splash → Onboarding (name, phone, postcode, stage-of-life, children)
//     2. MainShell → Home — community feed, upcoming events
//     3. Market tab → Sell sub-tab (empty state: encouraging CTA)
//     4. Taps CTA card → CreateListingScreen (AI pre-fills title+description)
//     5. Listing appears in "My listings" with AI insight nudges
//     6. Offer arrives → liveRegion announcement → AI summary ("Strong offer")
//     7. Swipe-right to accept → SnackBar confirmation with Undo
//     8. Item marked as Sold → celebration SnackBar
//   Pain points mitigated: anxiety about pricing (AI suggest price),
//     overwhelm with too many buttons (progressive disclosure),
//     uncertainty about listing quality (AI photo/description hints).
//   Emotional arc: unsure → guided → confident → delighted
//
// Journey 2: "Seasoned-Dad Sam" — Frequent Buyer
//   Touchpoints:
//     1. MainShell → Market tab → Buy sub-tab
//     2. AI-adapted search placeholder reflects previous browsing
//     3. Filters (age stage, category, condition, price) — one-tap chips
//     4. AI-ranked grid → taps item → ItemDetailScreen
//     5. Saves item (animated heart) → Saved tab
//     6. Makes offer → waits for seller response
//     7. Notification → offer accepted
//   Pain points mitigated: irrelevant search results (invisible AI ranking),
//     slow filter workflow (bottom-sheet filters with haptic feedback),
//     information overload (clean card with essentials only).
//   Emotional arc: purposeful → efficient → satisfied
//
// Journey 3: "Expert-Grandparent Grace" — Community Contributor
//   Touchpoints:
//     1. MainShell → Connect (groups for grandparents)
//     2. Market tab → Buy tab → searches age-aware items (toddler, kids)
//     3. Long-press to dismiss irrelevant items → AI learns preferences
//     4. Sparkle icon → AI assistant → "Chat with Huddl" copilot
//     5. Profile → My Groups → badges/achievements
//     6. Market → Sell tab → lists curated items for community
//   Pain points mitigated: small text (48dp targets, legible 14pt+ body),
//     complex navigation (bottom nav with clear labels),
//     technology frustration (simple CTA, AI handles complexity).
//   Emotional arc: curious → engaged → rewarded → altruistic
//
// ─── TASK FLOW: PRELOVED SELL TAB ──────────────────────────────────────────
//
//   ┌─ Sell Tab ──────────────────────────────────────────────────┐
//   │                                                             │
//   │  [CTA Card: "Snap a photo..."] ─── tap ──► CreateListing   │
//   │  [Quick sell chips: +Clothes +Toys]  ── tap ──► CreateListing│
//   │                                                             │
//   │  Active Listings (AI-ranked by health score)                │
//   │    ├─ tap ──► ItemDetailScreen                              │
//   │    ├─ long-press ──► Bottom sheet (Edit / Mark sold / Delist)│
//   │    ├─ swipe-left ──► Delist confirmation dialog             │
//   │    └─ AI insight row (fade-in, thumbs feedback)             │
//   │                                                             │
//   │  Offers (AI-ranked, liveRegion)                             │
//   │    ├─ swipe-right ──► Accept + SnackBar (Undo)              │
//   │    ├─ swipe-left  ──► Decline + SnackBar (Undo)             │
//   │    └─ inline Accept/Decline buttons (fallback, 48dp)        │
//   │                                                             │
//   │  Recently Sold (auto-collapsed after 48h)                   │
//   │    └─ long-press ──► Relist / Delist                        │
//   │                                                             │
//   │  [AI transparency note: "Ordered by what needs attention"]  │
//   │  [Sparkle → AI Assistant: Quick list / Pricing / Voice]     │
//   └─────────────────────────────────────────────────────────────┘
//
// =============================================================================

class HuddlColors {
  // Primary — unified to the warm Huddl orange
  static const Color primary = Color(0xFFFCA878);
  static const Color primaryLight = Color(0xFFFFCBA0);
  static const Color primaryDark = Color(0xFFE8935E);

  // Secondary / Accent
  static const Color teal = Color(0xFF199A85);
  // ── Blue tokens remapped to brand palette (orange/teal) ──────────────────
  // These names are preserved for API stability; values now use brand colours.
  static const Color blue = Color(0xFF199A85);          // → brand teal
  static const Color lightBlue = Color(0xFFE8935E);     // → primaryDark orange
  static const Color paleBlue = Color(0xFFFFCBA0);      // → primaryLight orange
  static const Color blueBackground = Color(0xFFFFF3ED); // → peachLight

  // Category accent palette (non-status, for tags / badges / avatars)
  static const Color accentAmber = Color(0xFFF3C54F);       // yellow family – warm gold (style-guide primary yellow)
  static const Color accentCoral = Color(0xFFF69F72);       // orange-pink family
  static const Color accentSky   = Color(0xFFFFCBA0);       // → primaryLight (was blue)
  static const Color accentSlate = Color(0xFF7C7C7C);       // neutral secondary text

  // Yellow / Amber family (from style guide — #FFF3C54F)
  static const Color yellowDark = Color(0xFFD4A017);
  static const Color yellow = Color(0xFFF3C54F);
  static const Color yellowMedium = Color(0xFFF7D97C);
  static const Color yellowSoft = Color(0xFFFBE8A6);
  static const Color yellowBackground = Color(0xFFFFF7C9);

  static const LinearGradient yellowGradient = LinearGradient(
    colors: [Color(0xFFF3C54F), Color(0xFFF7D97C)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ── Text ────────────────────────────────────────────────────────────────
  static const Color textDark = Color(0xFF43464D);
  static const Color textPrimary = Color(0xFF262A35);
  static const Color textSecondary = Color(0xFF6C6C6C);
  /// WCAG-safe hint for decorative / non-essential text only (2.9:1).
  static const Color textHint = Color(0xFF949494);
  /// WCAG 4.5:1 tertiary — use for interactive hints, counts, timestamps
  /// that carry meaning (audit recommendation #2).
  static const Color textTertiary = Color(0xFF767676);      // 4.6:1 on white
  static const Color textLight = Color(0xFFB0B0B0);

  // ── Backgrounds (light mode) ────────────────────────────────────────────
  static const Color background = Color(0xFFF6F6F6);
  static const Color white = Color(0xFFFFFFFF);
  static const Color peachLight = Color(0xFFFFF3ED);
  static const Color peachVeryLight = Color(0xFFFFF8F0);
  static const Color yellowLight = Color(0xFFFFF7C9);
  static const Color surfaceLight = Color(0xFFFAFAFA);

  // ── Dark-mode tokens (audit recommendation #1 — #121212 base) ──────────
  static const Color darkBackground = Color(0xFF121212);     // Material dark base
  static const Color darkSurface = Color(0xFF1E1E1E);       // card / elevated surface
  static const Color darkSurfaceVariant = Color(0xFF2C2C2C); // input fields, secondary surfaces
  static const Color darkDivider = Color(0xFF3A3A3A);
  static const Color darkTextPrimary = Color(0xFFE8E8E8);   // high-emphasis text on dark
  static const Color darkTextSecondary = Color(0xFFB0B0B0);  // medium-emphasis
  static const Color darkTextTertiary = Color(0xFF8A8A8A);   // low-emphasis (still 4.5:1 on #1E1E1E)
  static const Color darkInputBg = Color(0xFF2A2A2A);

  // Status
  static const Color error = Color(0xFFE53935);
  static const Color errorSoft = Color(0xFFFF7575);
  static const Color errorLight = Color(0xFFFFE9E9);
  static const Color success = Color(0xFF199A85);
  static const Color successGreen = Color(0xFF22C55E);
  static const Color successBg = Color(0xFFE6F5F3);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color warningDark = Color(0xFF78350F);

  // Interactive / Disabled
  static const Color disabled = Color(0xFFEEEEEE);
  static const Color disabledText = Color(0xFF9E9E9E);

  // Input fields
  static const Color inputBg = Color(0xFFF5F5F5);
  static const Color inputBorder = Color(0xFFDDDDDD);
  static const Color inputBorderLight = Color(0xFFE0E0E0);

  // Onboarding
  static const Color onboardingOrange = Color(0xFFFCA878);
  static const Color avatarBg = Color(0xFFFFF9D6);
  static const Color avatarIcon = Color(0xFFE8A87C);

  // Grayscale
  static const Color gray100 = Color(0xFFF6F6F6);
  static const Color gray200 = Color(0xFFE8E8E8);
  static const Color gray300 = Color(0xFFD4D4D4);
  static const Color gray400 = Color(0xFFB0B0B0);
  static const Color gray500 = Color(0xFF949494);
  static const Color gray600 = Color(0xFF6C6C6C);
  static const Color gray700 = Color(0xFF4A4A4A);
  static const Color gray800 = Color(0xFF2D2D2D);
  static const Color gray900 = Color(0xFF1A1A1A);

  // Subscription / Premium — remapped to brand palette
  static const Color premiumPurpleBg = Color(0xFFFFF3ED);    // → peachLight
  static const Color premiumPurpleLight = Color(0xFFFFF8F0); // → peachVeryLight
  static const Color premiumPurpleMid = Color(0xFFFFEDD6);   // → warm peach mid
  static const Color premiumBlue = Color(0xFFE8935E);        // → primaryDark orange
  static const Color coralSoft = Color(0xFFE8935E);          // → primaryDark orange
  static const Color peachBg = Color(0xFFFFF0E6);
  static const Color disabledBorder = Color(0xFFE9E9EA);

  // Category dynamic colours — remapped to brand palette
  static const Color categoryBaby = Color(0xFFFCA878);  // → primary orange
  static const Color categorySport = Color(0xFF199A85); // → teal (already brand)
  static const Color categoryTech = Color(0xFF199A85);  // → teal
  static const Color actionSkip = Color(0xFFE53935);    // keep red — swipe-delete semantic
  static const Color actionGreen = Color(0xFF199A85);   // → teal (success green)
  static const Color pinkSoft = Color(0xFFFCA878);      // → primary orange
  static const Color amberWarm = Color(0xFFE8A838);     // keep — is brand amber/yellow
  static const Color purpleAccent = Color(0xFF199A85);  // → teal
  static const Color checkoutSuccessBg = Color(0xFFE6F5F3);
  static const Color checkoutSuccessBgLight = Color(0xFFF0FAF8);

  // Attachment sheet colours — remapped to brand palette
  static const Color attachPhoto = Color(0xFFE8935E);       // → primaryDark orange
  static const Color attachPhotoBg = Color(0xFFFFF3ED);     // → peachLight
  static const Color attachFile = Color(0xFF199A85);        // → teal
  static const Color attachFileBg = Color(0xFFE6F5F3);      // → teal bg (successBg)
  static const Color attachLocation = Color(0xFF199A85);    // → teal
  static const Color attachLocationBg = Color(0xFFE6F5F3);  // → teal bg
  static const Color attachContact = Color(0xFF199A85);     // → teal
  static const Color attachContactBg = Color(0xFFE6F5F3);   // → teal bg
  static const Color attachPoll = Color(0xFFF3C54F);        // → brand yellow/amber
  static const Color attachPollBg = Color(0xFFFFF7C9);      // → yellowLight

  // Gradient helpers
  static const Color coralGradientEnd = Color(0xFFFCA878);

  // Divider
  static const Color divider = Color(0xFFE8E8E8);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFFCA878), Color(0xFFFFCBA0)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF0E6), Color(0xFFFFF8F0), Color(0xFFFFFFFF)],
  );

  // AI feature gradient — remapped to brand orange
  static const LinearGradient aiGradient = LinearGradient(
    colors: [Color(0xFFE8935E), Color(0xFFFCA878)],  // primaryDark → primary
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const Color aiBlue = Color(0xFF199A85);      // → brand teal
  static const Color aiBlueLight = Color(0xFFE8935E); // → primaryDark orange

  // ── Shimmer / Skeleton loading ─────────────────────────────────────────
  static const Color shimmerBase = Color(0xFFE0E0E0);
  static const Color shimmerHighlight = Color(0xFFF5F5F5);
  static const Color darkShimmerBase = Color(0xFF2A2A2A);
  static const Color darkShimmerHighlight = Color(0xFF3A3A3A);

  // ── Overlay ────────────────────────────────────────────────────────────
  static const Color overlay = Color(0x66000000);
  static const Color overlayLight = Color(0x14000000);

  // ── Accessibility design tokens ────────────────────────────────────────
  /// Minimum touch-target size (Android Material You 48dp, iOS HIG 44pt).
  /// All interactive widgets MUST meet or exceed this.
  static const double minTouchTarget = 48.0;
  /// Recommended touch-target size for primary actions.
  static const double recommendedTouchTarget = 56.0;

  // ── Spacing system (8dp base grid) ─────────────────────────────────────
  static const double spaceXS  =  4.0;
  static const double spaceSM  =  8.0;
  static const double spaceMD  = 16.0;
  static const double spaceLG  = 24.0;
  static const double spaceXL  = 32.0;
  static const double spaceXXL = 48.0;

  // ── Border radius ──────────────────────────────────────────────────────
  static const double radiusSM   =  8.0;  // chips, badges
  static const double radiusMD   = 12.0;  // buttons, inputs
  static const double radiusLG   = 16.0;  // cards
  static const double radiusXL   = 24.0;  // modals, FABs
  static const double radiusFull = 999.0; // circles

  // ══════════════════════════════════════════════════════════════════════════
  // WCAG 2.2 CONTRAST VALIDATION — runtime helper
  // ══════════════════════════════════════════════════════════════════════════
  /// Returns true when [foreground] on [background] meets WCAG AA (4.5:1).
  static bool meetsWcagAa(Color foreground, Color background) {
    final l1 = foreground.computeLuminance();
    final l2 = background.computeLuminance();
    final lighter = l1 > l2 ? l1 : l2;
    final darker  = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05) >= 4.5;
  }
}

// =============================================================================
// ADAPTIVE COLOUR HELPER — resolves light/dark tokens from BuildContext
// =============================================================================
/// Extension on [BuildContext] that returns the correct semantic color for the
/// current brightness.  Usage: `context.hc.surface`, `context.hc.textPrimary`.
///
/// This keeps all screens theme-aware without touching every `const`
/// reference — screens can gradually migrate from `HuddlColors.white` to
/// `context.hc.surface` at their own pace.
extension HuddlAdaptive on BuildContext {
  HuddlContextColors get hc => HuddlContextColors(this);
}

class HuddlContextColors {
  final BuildContext _ctx;
  const HuddlContextColors(this._ctx);

  bool get _isDark => Theme.of(_ctx).brightness == Brightness.dark;

  // Surfaces
  Color get scaffold   => _isDark ? HuddlColors.darkBackground     : HuddlColors.background;
  Color get surface    => _isDark ? HuddlColors.darkSurface         : HuddlColors.white;
  Color get surfaceAlt => _isDark ? HuddlColors.darkSurfaceVariant  : HuddlColors.background;
  Color get inputBg    => _isDark ? HuddlColors.darkInputBg         : HuddlColors.inputBg;
  Color get divider    => _isDark ? HuddlColors.darkDivider         : HuddlColors.divider;

  // Text
  Color get textPrimary   => _isDark ? HuddlColors.darkTextPrimary   : HuddlColors.textDark;
  Color get textSecondary => _isDark ? HuddlColors.darkTextSecondary : HuddlColors.textSecondary;
  Color get textTertiary  => _isDark ? HuddlColors.darkTextTertiary  : HuddlColors.textTertiary;

  // Shadows (invisible in dark mode to avoid glow artefacts)
  Color get shadow => _isDark ? Colors.transparent : Colors.black.withValues(alpha: 0.04);

  // Card border (subtle lift in dark mode)
  Border? get cardBorder => _isDark
      ? Border.all(color: HuddlColors.darkDivider, width: 0.5)
      : null;
}
