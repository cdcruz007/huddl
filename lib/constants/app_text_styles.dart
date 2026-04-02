import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';

/// Huddl Design System - Typography
/// Based on approved style guide with system default fonts (SF Pro/Roboto)
/// Includes responsive scaling and dark theme support
class AppTextStyles {
  // ============================================================================
  // HEADINGS - Display & Title Hierarchy
  // ============================================================================
  
  /// H1 - Large Heading (Page titles, hero sections)
  /// 36px, Bold (700), High emphasis
  static const TextStyle h1 = TextStyle(
    fontSize: 36.0,
    fontWeight: FontWeight.w700, // Bold
    color: HuddlColors.textDark,
    height: 1.2,
    letterSpacing: -0.5,
  );
  
  /// H2 - Section Heading (Major sections)
  /// 32px, Bold (700), High emphasis
  static const TextStyle h2 = TextStyle(
    fontSize: 32.0,
    fontWeight: FontWeight.w700, // Bold
    color: HuddlColors.textDark,
    height: 1.25,
    letterSpacing: -0.5,
  );
  
  /// H3 - Subsection Heading (Card titles, group headers)
  /// 24px, SemiBold (600), High emphasis
  static const TextStyle h3 = TextStyle(
    fontSize: 24.0,
    fontWeight: FontWeight.w600, // SemiBold
    color: HuddlColors.textDark,
    height: 1.3,
    letterSpacing: 0,
  );
  
  /// H4 - Small Heading (Dialog titles, list headers)
  /// 20px, SemiBold (600), High emphasis
  static const TextStyle h4 = TextStyle(
    fontSize: 20.0,
    fontWeight: FontWeight.w600, // SemiBold
    color: HuddlColors.textDark,
    height: 1.4,
    letterSpacing: 0,
  );
  
  /// H5 - Tiny Heading (Component titles)
  /// 18px, SemiBold (600), Medium emphasis
  static const TextStyle h5 = TextStyle(
    fontSize: 18.0,
    fontWeight: FontWeight.w600, // SemiBold
    color: HuddlColors.textDark,
    height: 1.4,
    letterSpacing: 0,
  );
  
  /// H6 - Label Heading (Form sections, overlines)
  /// 16px, SemiBold (600), Medium emphasis
  static const TextStyle h6 = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w600, // SemiBold
    color: HuddlColors.textDark,
    height: 1.5,
    letterSpacing: 0.15,
  );
  
  // ============================================================================
  // BODY TEXT - Content Hierarchy
  // ============================================================================
  
  /// Body Large - Emphasized body text (Introductions, key information)
  /// 18px, Regular (400), Medium emphasis
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 18.0,
    fontWeight: FontWeight.w400, // Regular
    color: HuddlColors.textDark,
    height: 1.5,
    letterSpacing: 0,
  );
  
  /// Body - Primary body text (Default paragraph text)
  /// 16px, Regular (400), Medium emphasis
  static const TextStyle body = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w400, // Regular
    color: HuddlColors.textDark,
    height: 1.5,
    letterSpacing: 0,
  );
  
  /// Body1 - Alias for body (backwards compatibility)
  static const TextStyle body1 = body;
  
  /// Body Small - Secondary body text (Descriptions, metadata)
  /// 14px, Regular (400), Low emphasis
  static const TextStyle bodySmall = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w400, // Regular
    color: HuddlColors.textSecondary,
    height: 1.5,
    letterSpacing: 0,
  );
  
  /// Body2 - Alias for bodySmall (backwards compatibility)
  static const TextStyle body2 = bodySmall;
  
  // ============================================================================
  // CAPTION & LABELS
  // ============================================================================
  
  /// Caption - Small text (Timestamps, footnotes, helper text)
  /// 12px, Regular (400), Low emphasis
  static const TextStyle caption = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w400, // Regular
    color: HuddlColors.textHint,
    height: 1.4,
    letterSpacing: 0.15,
  );
  
  /// Overline - Uppercase small text (Category labels, tags)
  /// 12px, Medium (500), All caps, Letter spacing
  static const TextStyle overline = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w500, // Medium
    color: HuddlColors.textHint,
    height: 1.3,
    letterSpacing: 1.5,
  );
  
  // ============================================================================
  // BUTTON & INTERACTIVE TEXT
  // ============================================================================
  
  /// Button Large - Large button text
  /// 18px, SemiBold (600), High contrast
  static const TextStyle buttonLarge = TextStyle(
    fontSize: 18.0,
    fontWeight: FontWeight.w600, // SemiBold
    color: HuddlColors.white,
    height: 1.2,
    letterSpacing: 0.5,
  );
  
  /// Button - Default button text
  /// 16px, SemiBold (600), High contrast
  static const TextStyle button = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w600, // SemiBold
    color: HuddlColors.white,
    height: 1.2,
    letterSpacing: 0.5,
  );
  
  /// Button Small - Small button text
  /// 14px, SemiBold (600), High contrast
  static const TextStyle buttonSmall = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w600, // SemiBold
    color: HuddlColors.white,
    height: 1.2,
    letterSpacing: 0.5,
  );
  
  /// Link - Clickable link text
  /// 16px, Medium (500), Info color
  static const TextStyle link = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w500, // Medium
    color: HuddlColors.blue,
    height: 1.5,
    letterSpacing: 0,
    decoration: TextDecoration.underline,
  );
  
  /// Link Small - Small clickable link text
  /// 14px, Medium (500), Info color
  static const TextStyle linkSmall = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w500, // Medium
    color: HuddlColors.blue,
    height: 1.5,
    letterSpacing: 0,
    decoration: TextDecoration.underline,
  );
  
  // ============================================================================
  // INPUT FIELD TEXT
  // ============================================================================
  
  /// Input Label - Form field labels
  /// 14px, Medium (500), High emphasis
  static const TextStyle inputLabel = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w500, // Medium
    color: HuddlColors.textDark,
    height: 1.4,
    letterSpacing: 0.15,
  );
  
  /// Input Text - Text inside input fields
  /// 16px, Regular (400), High emphasis
  static const TextStyle inputText = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w400, // Regular
    color: HuddlColors.textDark,
    height: 1.5,
    letterSpacing: 0,
  );
  
  /// Input Hint - Placeholder text in input fields
  /// 16px, Regular (400), Low emphasis
  static const TextStyle inputHint = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w400, // Regular
    color: HuddlColors.textHint,
    height: 1.5,
    letterSpacing: 0,
  );
  
  /// Input Helper - Helper text below input fields
  /// 12px, Regular (400), Low emphasis
  static const TextStyle inputHelper = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w400, // Regular
    color: HuddlColors.textSecondary,
    height: 1.4,
    letterSpacing: 0.15,
  );
  
  /// Input Error - Error text for invalid inputs
  /// 12px, Regular (400), Error color
  static const TextStyle inputError = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w400, // Regular
    color: HuddlColors.error,
    height: 1.4,
    letterSpacing: 0.15,
  );
  
  // ============================================================================
  // SPECIAL PURPOSE TEXT
  // ============================================================================
  
  /// Subtitle - Subtitles, secondary headings
  /// 16px, Medium (500), Medium emphasis
  static const TextStyle subtitle = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w500, // Medium
    color: HuddlColors.textSecondary,
    height: 1.5,
    letterSpacing: 0.15,
  );
  
  /// Emphasis - Emphasized inline text
  /// 16px, SemiBold (600), High emphasis
  static const TextStyle emphasis = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w600, // SemiBold
    color: HuddlColors.textDark,
    height: 1.5,
    letterSpacing: 0,
  );
  
  /// Badge - Text inside badges and chips
  /// 12px, Medium (500), High contrast
  static const TextStyle badge = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w500, // Medium
    color: HuddlColors.white,
    height: 1.2,
    letterSpacing: 0.5,
  );
  
  /// Price - Price display text
  /// 20px, Bold (700), High emphasis
  static const TextStyle price = TextStyle(
    fontSize: 20.0,
    fontWeight: FontWeight.w700, // Bold
    color: HuddlColors.textDark,
    height: 1.2,
    letterSpacing: 0,
  );
  
  /// Price Small - Small price display
  /// 16px, SemiBold (600), High emphasis
  static const TextStyle priceSmall = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w600, // SemiBold
    color: HuddlColors.textDark,
    height: 1.2,
    letterSpacing: 0,
  );
  
  // ============================================================================
  // DARK THEME VARIANTS
  // ============================================================================
  
  /// Dark theme H1
  static const TextStyle darkH1 = TextStyle(
    fontSize: 36.0,
    fontWeight: FontWeight.w700,
    color: HuddlColors.white,
    height: 1.2,
    letterSpacing: -0.5,
  );
  
  /// Dark theme H2
  static const TextStyle darkH2 = TextStyle(
    fontSize: 32.0,
    fontWeight: FontWeight.w700,
    color: HuddlColors.white,
    height: 1.25,
    letterSpacing: -0.5,
  );
  
  /// Dark theme H3
  static const TextStyle darkH3 = TextStyle(
    fontSize: 24.0,
    fontWeight: FontWeight.w600,
    color: HuddlColors.white,
    height: 1.3,
    letterSpacing: 0,
  );
  
  /// Dark theme body
  static const TextStyle darkBody = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w400,
    color: HuddlColors.white,
    height: 1.5,
    letterSpacing: 0,
  );
  
  /// Dark theme body small
  static const TextStyle darkBodySmall = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w400,
    color: HuddlColors.gray400,
    height: 1.5,
    letterSpacing: 0,
  );
  
  /// Dark theme caption
  static const TextStyle darkCaption = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w400,
    color: HuddlColors.gray500,
    height: 1.4,
    letterSpacing: 0.15,
  );
  
  // ============================================================================
  // ADAPTIVE TEXT STYLES (Auto-adjust to theme)
  // ============================================================================
  
  /// Get adaptive H1 based on theme
  static TextStyle adaptiveH1(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? darkH1 : h1;
  }
  
  /// Get adaptive H2 based on theme
  static TextStyle adaptiveH2(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? darkH2 : h2;
  }
  
  /// Get adaptive H3 based on theme
  static TextStyle adaptiveH3(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? darkH3 : h3;
  }
  
  /// Get adaptive body based on theme
  static TextStyle adaptiveBody(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? darkBody : body;
  }
  
  /// Get adaptive body small based on theme
  static TextStyle adaptiveBodySmall(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? darkBodySmall : bodySmall;
  }
  
  /// Get adaptive caption based on theme
  static TextStyle adaptiveCaption(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? darkCaption : caption;
  }
  
  // ============================================================================
  // BACKWARDS COMPATIBILITY ALIASES
  // ============================================================================
  
  static const TextStyle heading1 = h1;
  static const TextStyle heading2 = h2;
  static const TextStyle heading3 = h3;
  static const TextStyle bodyText = body;
  static const TextStyle captionText = caption;
  static const TextStyle bodyMedium = bodySmall; // Alias for body2/bodySmall
}

/// Typography Helper Extensions
extension TextStyleExtensions on TextStyle {
  /// Create a copy with primary color
  TextStyle get primary => copyWith(color: HuddlColors.primary);
  
  /// Create a copy with info color
  TextStyle get info => copyWith(color: HuddlColors.blue);
  
  /// Create a copy with success color
  TextStyle get success => copyWith(color: HuddlColors.success);
  
  /// Create a copy with error color
  TextStyle get error => copyWith(color: HuddlColors.error);
  
  /// Create a copy with warning color
  TextStyle get warning => copyWith(color: HuddlColors.warning);
  
  /// Create a copy with white color
  TextStyle get white => copyWith(color: HuddlColors.white);
  
  /// Create a copy with bold weight
  TextStyle get bold => copyWith(fontWeight: FontWeight.w700);
  
  /// Create a copy with semibold weight
  TextStyle get semibold => copyWith(fontWeight: FontWeight.w600);
  
  /// Create a copy with medium weight
  TextStyle get medium => copyWith(fontWeight: FontWeight.w500);
  
  /// Create a copy with italic style
  TextStyle get italic => copyWith(fontStyle: FontStyle.italic);
  
  /// Create a copy with underline
  TextStyle get underline => copyWith(decoration: TextDecoration.underline);
}
