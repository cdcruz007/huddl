import 'package:flutter/material.dart';

// =============================================================================
// HUDDL DESIGN-SYSTEM COLOUR TOKENS  —  Single source of truth
// =============================================================================
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │  USAGE RULES  (enforced — read before you add a colour)                │
// ├─────────────────────────────────────────────────────────────────────────┤
// │                                                                         │
// │  1. BRAND ORANGE — primary / primaryLight only                          │
// │     • Target ≲ 5 % of visible elements per screen.                     │
// │     • Belongs on: primary CTA buttons, active tab indicator,            │
// │       selected-chip border/fill, key progress fills.                    │
// │     • NOT for: every icon, every border, tags by default, dividers.    │
// │                                                                         │
// │  2. TAGS & CHIPS default to neutral surfaces (neutral50 bg,             │
// │     neutral600 text). Brand orange marks *selected* state only.         │
// │                                                                         │
// │  3. BRAND TEAL (brandTeal) is a secondary accent — use sparingly        │
// │     for success states, secondary action buttons, and trust signals.    │
// │     Do not use interchangeably with orange.                             │
// │                                                                         │
// │  4. SEMANTIC colours (success/warning/error/info) are for STATUS only   │
// │     — never for decoration. Swap decorative usage for brand tokens.     │
// │                                                                         │
// │  5. TEXT always uses neutral900, neutral600, or neutral300 (hint).      │
// │     No raw hex for text. No HuddlColors.primary for body text.          │
// │                                                                         │
// │  6. OVERLAYS use the pre-defined overlay* tokens only. No raw           │
// │     Color(0xAA000000) literals anywhere outside this file.              │
// │                                                                         │
// │  7. DARK MODE: use context.hc.* adaptive helpers. Never hardcode        │
// │     a dark-mode value in screen files.                                  │
// │                                                                         │
// │  8. NEW COLOURS: if a colour cannot map to an existing token, add it    │
// │     here with a full comment (role, Figma source, WCAG contrast),       │
// │     then use the token — never a raw literal in a screen file.          │
// │                                                                         │
// └─────────────────────────────────────────────────────────────────────────┘
//
// =============================================================================
// TOKEN INVENTORY  (~22 canonical colours after consolidation)
// =============================================================================
//
// ── Brand (orange family) ──────────────────────────────────────────────────
//   primary / primaryLight / primaryPale / primaryDark / peachSurface
//
// ── Brand (teal) ──────────────────────────────────────────────────────────
//   brandTeal / tealBg / tealIconBg
//
// ── Neutral ramp (6 steps) ────────────────────────────────────────────────
//   neutral0 / neutral50 / neutral100 / neutral300 / neutral600 / neutral900
//
// ── Info blue (genuine blue — AI, informational) ─────────────────────────
//   infoBlue / infoBlueMid / infoBluePale
//
// ── Semantic status ───────────────────────────────────────────────────────
//   success / successBg / warning / warningBg / error / errorLight
//
// ── Dark-mode surfaces ────────────────────────────────────────────────────
//   darkBackground / darkSurface / darkSurfaceVariant / darkDivider
//   darkTextPrimary / darkTextSecondary / darkTextTertiary / darkInputBg
//
// ── Overlays ──────────────────────────────────────────────────────────────
//   overlay / overlayLight / overlayMedium / overlayHeavy
//
// =============================================================================

class HuddlColors {
  // ── Brand orange — exact Figma values, NEVER change these ─────────────
  /// Primary CTA orange. Use for primary buttons, active nav, selected chips.
  /// Target ≲ 5 % of visible surface per screen.
  static const Color primary      = Color(0xFFFF965C);  // Figma: "Dark orange"
  static const Color primaryLight = Color(0xFFFFAD7F);  // Figma: "Medium orange"
  static const Color primaryPale  = Color(0xFFFFC7A8);  // Figma: "Light orange"
  static const Color primaryDark  = Color(0xFFFF965C);  // same as primary

  /// Deeper orange for two-ring Connect mark — Ring B (ring_deep) stroke.
  /// Role: secondary ring stroke in the Connect section header and nav icon.
  /// Source: huddl_connect_rings.json layer ring_deep (#F2743A). Decorative only.
  static const Color connectRingDeep = Color(0xFFF2743A);

  /// Peach-tinted surface — backgrounds, cards, hero sections.
  /// Merges: blueBackground(old), peachLight, orangeBg, premiumPurpleLight(old).
  static const Color peachSurface  = Color(0xFFFFF3ED);

  /// Warm peach — slightly deeper surface variant.
  /// Merges: FFF5F0, FFF8F0, FFEDE0 families.
  static const Color peachWarm     = Color(0xFFFFF5F0);

  /// Peach premium — subscription / paywall highlights.
  static const Color peachPremiumBg  = Color(0xFFFFE8DB);  // was: premiumPurpleBg
  static const Color peachPremiumMid = Color(0xFFFFD4B8);  // was: premiumPurpleMid

  // ── Brand teal ────────────────────────────────────────────────────────
  /// Secondary accent. Use for success, secondary actions, trust signals.
  /// Was incorrectly named: blue, purpleAccent, successGreen.
  static const Color brandTeal    = Color(0xFF199A85);  // was: blue / purpleAccent / teal
  static const Color tealBg       = Color(0xFFE6F5F3);  // teal category surface / successBg
  static const Color tealIconBg   = Color(0xFFB8EAE2);  // teal icon circle bg

  // ── Neutral ramp — 6 canonical steps ─────────────────────────────────
  // Maps all 12 near-identical greys to the nearest step.
  // See consolidation map in commit for full hex→token mapping.
  static const Color neutral0   = Color(0xFFFFFFFF);  // pure white
  /// Light fills, card backgrounds, input fills.
  /// Absorbs: #F7F7F7 (dominant, 143×), #F5F5F5, #F6F6F6, #F8F8F8, #F0F0F0.
  static const Color neutral50  = Color(0xFFF7F7F7);
  /// Borders, dividers, disabled elements, shimmer base.
  /// Absorbs: #EEEEEE, #E8E8E8, #E5E5E5, #E0E0E0, #DDDDDD, #D5D5D5, #D0D0D0, #BBBBBB, #BDBDBD.
  static const Color neutral100 = Color(0xFFEEEEEE);
  /// Hint text, timestamps, placeholder icons, deselected icons.
  /// Absorbs: #B0B0B0, #9E9E9E, #949494.
  static const Color neutral300 = Color(0xFFB0B0B0);
  /// Secondary body text, subtitles, helper text.
  /// Absorbs: #6C6C6C, #666666, #757575, #767676.
  static const Color neutral600 = Color(0xFF6C6C6C);
  /// Primary text, near-black. Absorbs: #1C1C1E, #1A1A1A, #1D1D1B, #2A2A2A (dark contexts).
  static const Color neutral900 = Color(0xFF1A1A1A);

  // ── Info blue — genuine informational / AI blue ───────────────────────
  /// Reserved: informational badges, AI feature surfaces, "New" labels.
  /// Do NOT use for primary CTAs (orange only).
  static const Color infoBlue     = Color(0xFF347FEF);  // Figma "Dark blue"
  static const Color infoBlueMid  = Color(0xFF5B9CFF);  // Figma "Medium blue"
  static const Color infoBluePale = Color(0xFFEDF4FF);  // Figma pale blue bg

  // ── Semantic: success ─────────────────────────────────────────────────
  static const Color success   = Color(0xFF199A85);  // = brandTeal; for status labels only
  static const Color successBg = Color(0xFFE6F5F3);  // = tealBg

  // ── Semantic: warning ─────────────────────────────────────────────────
  static const Color warning    = Color(0xFFF59E0B);
  static const Color warningBg  = Color(0xFFFEF3C7);
  static const Color warningDark = Color(0xFF78350F);

  // ── Semantic: error ───────────────────────────────────────────────────
  static const Color error      = Color(0xFFFF5151);  // Figma: "Error"
  static const Color errorSoft  = Color(0xFFFF7575);
  static const Color errorLight = Color(0xFFFFE8E8);  // Figma: "Error light"

  // ── Text — always use these; never raw hex ────────────────────────────
  /// High-emphasis text — near-black.
  static const Color textDark      = Color(0xFF43464D);  // body text on white
  static const Color textPrimary   = Color(0xFF262A35);  // darkest body
  static const Color nearBlack     = Color(0xFF1C1C1E);  // nav active, logo wordmark
  static const Color textSecondary = Color(0xFF6C6C6C);  // = neutral600
  static const Color textHint      = Color(0xFF949494);  // decorative hint only (2.9:1)
  static const Color textTertiary  = Color(0xFF767676);  // 4.6:1 — interactive hints
  static const Color textLight     = Color(0xFFB0B0B0);  // = neutral300 — deselected

  // ── Surfaces ──────────────────────────────────────────────────────────
  static const Color white        = Color(0xFFFFFFFF);
  static const Color warmWhite    = Color(0xFFFFFAF7);  // scaffold bg — warmer than pure white
  static const Color background   = Color(0xFFF7F7F7);  // page bg (was #F6F6F6, absorbs into neutral50)
  static const Color surfaceLight = Color(0xFFFAFAFA);

  // ── Dark-mode surfaces ────────────────────────────────────────────────
  static const Color darkBackground      = Color(0xFF121212);
  static const Color darkSurface         = Color(0xFF1E1E1E);
  static const Color darkSurfaceVariant  = Color(0xFF2C2C2C);
  static const Color darkDivider         = Color(0xFF3A3A3A);
  static const Color darkTextPrimary     = Color(0xFFE8E8E8);
  static const Color darkTextSecondary   = Color(0xFFB0B0B0);
  static const Color darkTextTertiary    = Color(0xFF8A8A8A);
  static const Color darkInputBg         = Color(0xFF2A2A2A);

  /// Dark-mode badge backgrounds — adapted from light-mode equivalents.
  /// Never use yellowSoft, infoBluePale, or peachLight on dark surfaces.
  static const Color darkBadgeAmber     = Color(0xFF3D2E00); // "Free" badge bg
  static const Color darkBadgeAmberText = Color(0xFFF3C54F); // "Free" badge text
  static const Color darkBadgeBlue      = Color(0xFF0D2340); // "New" / info badge bg
  static const Color darkBadgeBlueText  = Color(0xFF90B8F8); // "New" / info badge text
  static const Color darkBadgeSurface   = Color(0xFF2C2C2C); // neutral badge bg

  // ── Interactive / Disabled ────────────────────────────────────────────
  static const Color disabled      = Color(0xFFEEEEEE);  // = neutral100
  static const Color disabledText  = Color(0xFF9E9E9E);  // ≈ neutral300 (slightly lighter)
  static const Color disabledBorder = Color(0xFFE9E9EA);

  // ── Input fields ──────────────────────────────────────────────────────
  static const Color inputBg          = Color(0xFFF7F7F7);  // = neutral50 (was #F5F5F5)
  static const Color inputBorder      = Color(0xFFDDDDDD);  // ≈ neutral100
  static const Color inputBorderLight = Color(0xFFE0E0E0);  // ≈ neutral100

  // ── Divider ───────────────────────────────────────────────────────────
  static const Color divider      = Color(0xFFD5D5D5);  // ≈ neutral100
  static const Color warmDivider  = Color(0xFFEEDDD4);  // warm-tinted divider

  // ── Overlays — use these; no raw Color(0xAA000000) literals ──────────
  static const Color overlay       = Color(0x66000000);  // 40 % black
  static const Color overlayLight  = Color(0x14000000);  // 8 % black
  static const Color overlayMedium = Color(0x33000000);  // 20 % black — image scrim
  static const Color overlayHeavy  = Color(0x88000000);  // 53 % black — card scrim

  // ── Shimmer / Skeleton ────────────────────────────────────────────────
  static const Color shimmerBase      = Color(0xFFE0E0E0);
  static const Color shimmerHighlight = Color(0xFFF5F5F5);
  static const Color darkShimmerBase      = Color(0xFF2A2A2A);
  static const Color darkShimmerHighlight = Color(0xFF3A3A3A);

  // ── Category icon containers ──────────────────────────────────────────
  static const Color orangeBg      = Color(0xFFFFF3ED);  // = peachSurface
  static const Color orangeIconBg  = Color(0xFFFFE0CC);
  static const Color yellowBg      = Color(0xFFFFF7C9);
  static const Color yellowIconBg  = Color(0xFFFFF0A8);
  static const Color blueBg        = Color(0xFFEDF4FF);  // = infoBluePale
  static const Color blueIconBg    = Color(0xFFCCDDFF);

  // ── Yellow / Amber family ─────────────────────────────────────────────
  static const Color accentAmber     = Color(0xFFF3C54F);
  static const Color yellow          = Color(0xFFF3C54F);  // = accentAmber
  static const Color yellowMedium    = Color(0xFFF7D97C);
  static const Color yellowSoft      = Color(0xFFFBE8A6);
  static const Color yellowBackground = Color(0xFFFFF7C9);  // = yellowBg
  static const Color yellowLight     = Color(0xFFFFF7C9);   // alias
  static const Color amberWarm       = Color(0xFFFFCE51);
  static const Color yellowDark      = Color(0xFFD4A017);

  // ── Onboarding ────────────────────────────────────────────────────────
  static const Color onboardingOrange = Color(0xFFFF965C);  // = primary
  static const Color avatarBg         = Color(0xFFFFF9D6);
  static const Color avatarIcon       = Color(0xFFFF965C);  // = primary

  // ── Grayscale named steps (kept for legacy callers — prefer neutral* above) ─
  static const Color gray100 = Color(0xFFF7F7F7);  // = neutral50 (was F6F6F6)
  static const Color gray200 = Color(0xFFEEEEEE);  // = neutral100
  static const Color gray300 = Color(0xFFD4D4D4);  // ≈ neutral100
  static const Color gray400 = Color(0xFFB0B0B0);  // = neutral300
  static const Color gray500 = Color(0xFF949494);  // ≈ neutral300 (slightly lighter)
  static const Color gray600 = Color(0xFF6C6C6C);  // = neutral600
  static const Color gray700 = Color(0xFF4A4A4A);
  static const Color gray800 = Color(0xFF2D2D2D);
  static const Color gray900 = Color(0xFF1A1A1A);  // = neutral900

  // ── Subscription / Premium ────────────────────────────────────────────
  static const Color premiumPurpleBg    = Color(0xFFFFE8DB);  // = peachPremiumBg (kept for compat)
  static const Color premiumPurpleLight = Color(0xFFFFF3ED);  // = peachSurface (kept for compat)
  static const Color premiumPurpleMid   = Color(0xFFFFD4B8);  // = peachPremiumMid (kept for compat)
  static const Color premiumBlue        = Color(0xFF347FEF);  // = infoBlue
  static const Color coralSoft          = Color(0xFFFFAD7F);  // = primaryLight

  // ── Category dynamic colours (legacy names kept for compat) ──────────
  static const Color categoryBaby  = Color(0xFFFF965C);  // = primary
  static const Color categorySport = Color(0xFF199A85);  // = brandTeal
  static const Color categoryTech  = Color(0xFF199A85);  // = brandTeal
  static const Color actionSkip    = Color(0xFFFF5151);  // = error
  static const Color actionGreen   = Color(0xFF199A85);  // = brandTeal

  // ── Misleading-name aliases: keep for compile-safety; prefer new names ─
  // OLD NAME        →  NEW TOKEN
  // lightBlue       →  primaryDark (same hex as primary)
  // paleBlue        →  primaryLight + some uses = orangePale
  // blueBackground  →  peachSurface
  // purpleAccent    →  brandTeal
  // pinkSoft        →  primaryLight
  // [blue removed — was a dead alias for brandTeal; no external call-sites]
  static const Color lightBlue       = Color(0xFFE8935E);  // → use primaryDark/orangeDeep
  static const Color paleBlue        = Color(0xFFFFCBA0);  // → use orangePale
  static const Color blueBackground  = Color(0xFFFFF3ED);  // → use peachSurface
  static const Color accentSky       = Color(0xFFFFCBA0);  // → use orangePale
  static const Color purpleAccent    = Color(0xFF199A85);  // → use brandTeal
  static const Color pinkSoft        = Color(0xFFFFAD7F);  // → use primaryLight
  static const Color accentSlate     = Color(0xFF7C7C7C);  // → use neutral600
  static const Color accentCoral     = Color(0xFFF69F72);  // orange-pink family

  // Additional specific tokens (for screens that need an exact shade)
  static const Color orangeDeep   = Color(0xFFE8935E);  // deep orange CTA variant
  static const Color orangePale   = Color(0xFFFFCBA0);  // pale orange badge fill
  static const Color peachBg      = Color(0xFFFFF0E6);  // slightly warmer peach surface
  static const Color peachSoft    = Color(0xFFFFE8D9);  // orange tint surface
  static const Color checkoutSuccessBg      = Color(0xFFE6F5F3);  // = tealBg
  static const Color checkoutSuccessBgLight = Color(0xFFF0FAF8);

  // ── Attachment sheet colours ──────────────────────────────────────────
  static const Color attachPhoto      = Color(0xFFFF965C);  // = primary
  static const Color attachPhotoBg    = Color(0xFFFFE8DB);  // = peachPremiumBg
  static const Color attachFile       = Color(0xFF199A85);  // = brandTeal
  static const Color attachFileBg     = Color(0xFFE6F5F3);  // = tealBg
  static const Color attachLocation   = Color(0xFF199A85);  // = brandTeal
  static const Color attachLocationBg = Color(0xFFE6F5F3);  // = tealBg
  static const Color attachContact    = Color(0xFF199A85);  // = brandTeal
  static const Color attachContactBg  = Color(0xFFE6F5F3);  // = tealBg
  static const Color attachPoll       = Color(0xFFFFCE51);  // = amberWarm
  static const Color attachPollBg     = Color(0xFFFFF6C9);

  // ── AI feature colours ────────────────────────────────────────────────
  static const Color aiBlue      = Color(0xFF347FEF);  // = infoBlue
  static const Color aiBlueLight = Color(0xFFEDF4FF);  // = infoBluePale
  static const LinearGradient aiGradient = LinearGradient(
    colors: [Color(0xFFFF965C), Color(0xFFFFAD7F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Previously duplicated alias tokens ───────────────────────────────
  static const Color teal         = Color(0xFF199A85);  // = brandTeal (legacy)
  static const Color successGreen = Color(0xFF199A85);  // = brandTeal (legacy)
  static const Color blueDark     = Color(0xFF347FEF);  // = infoBlue  (legacy)
  static const Color blueUI       = Color(0xFF5B9CFF);  // = infoBlueMid (legacy)
  static const Color blueUIPale   = Color(0xFFEDF4FF);  // = infoBluePale (legacy)

  // ── Chat bubble specifics ─────────────────────────────────────────────
  /// Warm parchment — received bubble in light mode. Slightly warmer than neutral50.
  static const Color receivedBubbleLight = Color(0xFFF5F2EE);
  /// Warm dark — received bubble in dark mode.
  static const Color receivedBubbleDark  = Color(0xFF2E2A26);

  // ── Partner / external brand colours (intentional, non-consolidatable) ─
  // These are third-party brand colours used ONLY in the insights/partner
  // screen for logos. They MUST NOT be consolidated — they are not Huddl brand.
  static const Color partnerNhs      = Color(0xFF005EB8);  // NHS brand blue
  static const Color partnerNct      = Color(0xFF7B3F9E);  // NCT brand purple
  static const Color partnerBounty   = Color(0xFFE84393);  // Bounty brand pink
  static const Color partnerNetmums  = Color(0xFF00A896);  // Netmums brand teal
  static const Color partnerDadsnet  = Color(0xFF1A73E8);  // DadsNet brand blue
  static const Color partnerGov      = Color(0xFF1D1D1B);  // Gov.uk near-black

  // ── Avatar initials palette (deterministic per-user identity colours) ──
  // Used ONLY in group initials avatars. These are intentionally varied to
  // distinguish users at a glance — not consolidated by design.
  static const List<Color> avatarPalette = [
    Color(0xFFE57373), Color(0xFFFF8A65), Color(0xFFFFB74D), Color(0xFFFFD54F),
    Color(0xFFA5D6A7), Color(0xFF4DB6AC), Color(0xFF4FC3F7), Color(0xFF7986CB),
    Color(0xFFBA68C8), Color(0xFFF06292), Color(0xFF90A4AE), Color(0xFF80CBC4),
    Color(0xFFCE93D8), Color(0xFF80DEEA), Color(0xFFFFCC02), Color(0xFF66BB6A),
  ];

  /// Warm purple — used only as an identity signal in chat sender palettes.
  /// Not a brand colour; not for UI decoration.
  static const Color chatWarmPurple = Color(0xFF9B72CF);

  // ── Avatar identity palette (smaller set for chat) ─────────────────────
  static const List<Color> chatAvatarPalette = [
    Color(0xFFFF965C),  // primary orange
    Color(0xFF199A85),  // teal
    Color(0xFFE8724A),  // deep orange
    Color(0xFF5B9CFF),  // info blue — identity signal only
    Color(0xFF9B72CF),  // warm purple = chatWarmPurple
    Color(0xFFD4845A),  // terracotta
  ];

  // ── Spacing system (8dp base grid) ──────────────────────────────────────
  static const double spaceXS  =  4.0;
  static const double spaceSM  =  8.0;
  static const double spaceMD  = 16.0;
  static const double spaceLG  = 24.0;
  static const double spaceXL  = 32.0;
  static const double spaceXXL = 48.0;

  // ── Border radius ──────────────────────────────────────────────────────
  static const double radiusSM   =  8.0;
  static const double radiusMD   = 12.0;
  static const double radiusLG   = 16.0;
  static const double radiusXL   = 24.0;
  static const double radiusFull = 999.0;

  // ── Accessibility design tokens ────────────────────────────────────────
  static const double minTouchTarget         = 48.0;
  static const double recommendedTouchTarget = 56.0;

  // ── Gradients ─────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFFF965C), Color(0xFFFFAD7F)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient yellowGradient = LinearGradient(
    colors: [Color(0xFFF3C54F), Color(0xFFF7D97C)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const Color coralGradientEnd = Color(0xFFFFAD7F);

  // ── WCAG helper ───────────────────────────────────────────────────────
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
extension HuddlAdaptive on BuildContext {
  HuddlContextColors get hc => HuddlContextColors(this);
}

class HuddlContextColors {
  final BuildContext _ctx;
  const HuddlContextColors(this._ctx);

  bool get _isDark => Theme.of(_ctx).brightness == Brightness.dark;

  // Surfaces
  Color get scaffold   => _isDark ? HuddlColors.darkBackground    : Colors.white;
  Color get surface    => _isDark ? HuddlColors.darkSurface        : Colors.white;
  Color get surfaceAlt => _isDark ? HuddlColors.darkSurfaceVariant : const Color(0xFFF7F7F7);
  Color get inputBg    => _isDark ? HuddlColors.darkInputBg        : const Color(0xFFF7F7F7);
  Color get inputFill  => _isDark ? HuddlColors.darkInputBg        : const Color(0xFFF7F7F7);
  Color get divider    => _isDark ? HuddlColors.darkDivider        : const Color(0xFFE5E5E5);
  Color get confirmed  => _isDark ? HuddlColors.darkTextPrimary    : const Color(0xFF1C1C1E);

  // Text
  Color get textPrimary   => _isDark ? HuddlColors.darkTextPrimary   : HuddlColors.textDark;
  Color get textSecondary => _isDark ? HuddlColors.darkTextSecondary : HuddlColors.textSecondary;
  Color get textTertiary  => _isDark ? HuddlColors.darkTextTertiary  : HuddlColors.textTertiary;

  // Shadows (invisible in dark mode)
  Color get shadow => _isDark ? Colors.transparent : Colors.black.withValues(alpha: 0.04);

  // Card border
  Border? get cardBorder => _isDark
      ? Border.all(color: HuddlColors.darkDivider, width: 0.5)
      : null;
}
