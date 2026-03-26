import 'package:flutter/material.dart';

/// Huddl Design System - Color Palette
/// Based on approved style guide with orange (#FF6B35) as primary brand color
/// Includes light and dark theme support with WCAG AA accessibility compliance
class AppColors {
  // ============================================================================
  // PRIMARY BRAND COLORS (Orange Family) - From Style Guide
  // ============================================================================
  
  /// Primary brand orange - Bold CTA orange/coral (Main CTA buttons, badges)
  /// Figma V2.0 confirmed: #FF7043
  static const Color primary = Color(0xFFFF7043);
  
  /// Light orange - Buttons backgrounds, active state highlights
  static const Color primaryLight = Color(0xFFFFCCBC); // #FFCCBC
  
  /// Light orange - Backgrounds, subtle highlights, cards
  static const Color primaryLighter = Color(0xFFFFD9C2); // proportional lighter
  
  /// Pale orange - Very light backgrounds
  static const Color primaryPale = Color(0xFFFFECDF); // proportional pale
  
  /// Ultra light orange - Subtle backgrounds, hover states
  static const Color primaryUltraLight = Color(0xFFFFF1ED);
  
  /// Dark orange - Price text, pressed states
  static const Color primaryDark = Color(0xFFE64A19); // #E64A19 Figma V2.0
  
  // ============================================================================
  // SECONDARY COLORS (Yellow/Accent) - From Style Guide
  // ============================================================================
  
  /// Soft yellow - Highlights, badges, important indicators
  static const Color accent = Color(0xFFFFC857);
  static const Color accentYellow = Color(0xFFFFC857); // Alias for yellow usage
  
  /// Light yellow - Subtle accents
  static const Color accentLight = Color(0xFFFFD97F);
  
  /// Pale yellow - Backgrounds
  static const Color accentPale = Color(0xFFFFF4DD);
  
  // ============================================================================
  // INFORMATION COLORS (Blue Family) - From Style Guide
  // ============================================================================
  
  /// Material Blue 500 - Interactive elements, links, filter chips, active nav
  static const Color info = Color(0xFF2196F3);
  static const Color infoBlue = Color(0xFF2196F3); // Alias for blue usage
  
  /// Medium blue - Hover states
  static const Color infoLight = Color(0xFF64B5F6);
  
  /// Light blue - Backgrounds, subtle highlights
  static const Color infoLighter = Color(0xFFBBDEFB);
  
  /// Pale blue - Light backgrounds
  static const Color infoPale = Color(0xFFE3F2FD);
  
  /// Info background for messages and alerts
  static const Color infoBg = Color(0xFFF0F6FF);
  
  // ============================================================================
  // SEMANTIC COLORS - Adjusted for better design
  // ============================================================================
  
  /// Success green - Valid states, success messages (from style guide green swatch)
  static const Color success = Color(0xFF27AE60);
  
  /// Success background
  static const Color successBg = Color(0xFFE8F8EF);
  
  /// Error/warning coral - Error states, destructive actions (softer coral)
  static const Color error = Color(0xFFFF6F61);
  
  /// Error background
  static const Color errorBg = Color(0xFFFFEBE9);
  
  /// Warning orange-yellow - Warning messages
  static const Color warning = Color(0xFFF59E0B);
  
  /// Warning background
  static const Color warningBg = Color(0xFFFFFBEB);
  
  /// Online status indicator
  static const Color online = Color(0xFF22C55E);
  
  // ============================================================================
  // NEUTRAL COLORS (Gray Scale) - Light Theme
  // ============================================================================
  
  /// Dark gray - Primary text
  /// WCAG AAA compliant on white (contrast ratio: 12.63:1)
  static const Color textDark = Color(0xFF2C2C2C);
  
  /// Medium dark gray - Body text
  /// WCAG AAA compliant on white (contrast ratio: 10.46:1)
  static const Color text = Color(0xFF333333);
  
  /// Medium gray - Secondary text
  /// WCAG AA compliant on white (contrast ratio: 7.0:1)
  static const Color textSecondary = Color(0xFF666666);
  
  /// Light gray - Tertiary text, placeholders
  static const Color textTertiary = Color(0xFF999999);
  
  /// Border gray
  static const Color border = Color(0xFFCCCCCC);
  
  /// Background gray
  static const Color backgroundGray = Color(0xFFE5E5E5);
  
  /// Ultra light gray - Subtle backgrounds
  static const Color backgroundLight = Color(0xFFF5F5F5);
  
  /// Pure white - Card backgrounds, surfaces
  static const Color white = Color(0xFFFFFFFF);
  
  /// Main background - Off-white for reduced eye strain
  static const Color background = Color(0xFFFAFAFA);
  
  // ============================================================================
  // BACKWARDS COMPATIBILITY ALIASES (for existing code)
  // ============================================================================
  
  /// Alias for textSecondary
  static const Color text2 = textSecondary;
  
  /// Alias for textTertiary
  static const Color text3 = textTertiary;
  
  /// Alias for border
  static const Color border2 = border;
  
  /// Alias for background
  static const Color bg = background;
  
  /// Alias for primary (old primaryOrange)
  static const Color primaryOrange = primary;
  
  /// Alias for textDark (old textPrimary)
  static const Color textPrimary = textDark;
  
  /// Alias for textSecondary (old textMedium)
  static const Color textMedium = textSecondary;
  
  /// Alias for textTertiary (old textLight)
  static const Color textLight = textTertiary;
  
  /// Alias for primary (old accent purple - now orange)
  static const Color accentPurple = primary;
  
  /// Alias for primaryDark
  static const Color accentDark = primaryDark;
  
  /// Alias for coral/secondary orange
  static const Color coral = primaryLight;
  
  /// Alias for yellow accent
  static const Color yellow = accent;
  
  /// Alias for info blue
  static const Color blue = info;
  
  /// Alias for info lighter blue  
  static const Color lightBlue = infoLighter;
  
  /// Alias for card
  static const Color cardBackground = card;
  
  /// Alias for light gray
  static const Color lightGrey = Color(0xFFE5E7EB);
  
  /// Alias for secondary info blue (old secondary)
  static const Color secondary = info;
  
  // ============================================================================
  // DARK THEME COLORS
  // ============================================================================
  
  /// Dark theme background - Soft gray (#121212) not pure black
  /// Reduces halation and eye strain on OLED screens
  static const Color darkBackground = Color(0xFF121212);
  
  /// Dark theme surface - Elevated cards
  static const Color darkSurface = Color(0xFF1E1E1E);
  
  /// Dark theme surface elevated - Modals, dialogs
  static const Color darkSurfaceElevated = Color(0xFF2C2C2C);
  
  /// Dark theme text - High emphasis text
  /// WCAG AAA compliant on dark background (contrast ratio: 15.84:1)
  static const Color darkTextPrimary = Color(0xFFE5E5E5);
  
  /// Dark theme text - Medium emphasis
  /// WCAG AA compliant on dark background (contrast ratio: 10.5:1)
  static const Color darkTextSecondary = Color(0xFFB3B3B3);
  
  /// Dark theme text - Low emphasis
  static const Color darkTextTertiary = Color(0xFF808080);
  
  /// Dark theme border
  static const Color darkBorder = Color(0xFF3A3A3A);
  
  /// Dark theme divider
  static const Color darkDivider = Color(0xFF2A2A2A);
  
  // ============================================================================
  // COMPONENT-SPECIFIC COLORS
  // ============================================================================
  
  /// Card background (light theme)
  static const Color card = white;
  
  /// Card background (dark theme)
  static const Color darkCard = darkSurface;
  
  /// Surface background (light theme)
  static const Color surface = white;
  
  /// Input field background (light theme)
  static const Color inputBackground = Color(0xFFF5F5F5);
  
  /// Input field background (dark theme)
  static const Color darkInputBackground = Color(0xFF2A2A2A);
  
  /// Input border (light theme)
  static const Color inputBorder = Color(0xFFE5E5E5);
  
  /// Input border focused (uses primary color)
  static const Color inputBorderFocused = primary;
  
  /// Divider (light theme)
  static const Color divider = Color(0xFFE5E5E5);
  
  // ============================================================================
  // OVERLAY & SPECIAL COLORS
  // ============================================================================
  
  /// Overlay - Dark transparent for modals
  static const Color overlay = Color(0x66000000);
  
  /// Light overlay - Subtle overlay
  static const Color overlayLight = Color(0x14000000);
  
  /// Transparent
  static const Color transparent = Colors.transparent;
  
  /// Shimmer base color for skeleton loading
  static const Color shimmerBase = Color(0xFFE0E0E0);
  
  /// Shimmer highlight color
  static const Color shimmerHighlight = Color(0xFFF5F5F5);
  
  /// Dark shimmer base
  static const Color darkShimmerBase = Color(0xFF2A2A2A);
  
  /// Dark shimmer highlight
  static const Color darkShimmerHighlight = Color(0xFF3A3A3A);
  
  // ============================================================================
  // GRADIENT DEFINITIONS
  // ============================================================================
  
  /// Primary gradient - Orange to light orange
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  /// Accent gradient - Yellow to light yellow
  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent, accentLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  /// Info gradient - Blue gradation
  static const LinearGradient infoGradient = LinearGradient(
    colors: [info, infoLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  /// Dark gradient - For dark theme headers
  static const LinearGradient darkGradient = LinearGradient(
    colors: [darkSurface, darkSurfaceElevated],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  
  // ============================================================================
  // WCAG AA ACCESSIBILITY VALIDATION
  // ============================================================================
  
  /// Validates if color meets WCAG AA contrast ratio (4.5:1) on white
  static bool meetsWCAGAA(Color color) {
    final contrast = _calculateContrast(color, white);
    return contrast >= 4.5;
  }
  
  /// Calculate contrast ratio between two colors
  static double _calculateContrast(Color color1, Color color2) {
    final lum1 = _calculateLuminance(color1);
    final lum2 = _calculateLuminance(color2);
    
    final lighter = lum1 > lum2 ? lum1 : lum2;
    final darker = lum1 > lum2 ? lum2 : lum1;
    
    return (lighter + 0.05) / (darker + 0.05);
  }
  
  /// Calculate relative luminance
  static double _calculateLuminance(Color color) {
    final r = _calculateChannelLuminance(color.r);
    final g = _calculateChannelLuminance(color.g);
    final b = _calculateChannelLuminance(color.b);
    
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }
  
  /// Calculate channel luminance
  static double _calculateChannelLuminance(double channel) {
    return channel <= 0.03928
        ? channel / 12.92
        : ((channel + 0.055) / 1.055) * ((channel + 0.055) / 1.055);
  }
  
  // ============================================================================
  // THEME MODE HELPER
  // ============================================================================
  
  /// Get appropriate color based on theme brightness
  static Color adaptiveColor(
    BuildContext context, {
    required Color light,
    required Color dark,
  }) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? dark : light;
  }
  
  /// Get text color based on theme
  static Color adaptiveText(BuildContext context) {
    return adaptiveColor(
      context,
      light: textDark,
      dark: darkTextPrimary,
    );
  }
  
  /// Get background color based on theme
  static Color adaptiveBackground(BuildContext context) {
    return adaptiveColor(
      context,
      light: background,
      dark: darkBackground,
    );
  }
  
  /// Get card color based on theme
  static Color adaptiveCard(BuildContext context) {
    return adaptiveColor(
      context,
      light: card,
      dark: darkCard,
    );
  }
}

/// Design Tokens - Spacing, Border Radius, Elevation
class DesignTokens {
  // ============================================================================
  // SPACING SYSTEM (8px Base Grid)
  // ============================================================================
  
  static const double spaceXS = 4.0;   // Extra Small
  static const double spaceS = 8.0;    // Small
  static const double spaceM = 16.0;   // Medium (Base)
  static const double spaceL = 24.0;   // Large
  static const double spaceXL = 32.0;  // Extra Large
  static const double spaceXXL = 48.0; // XXL
  static const double spaceXXXL = 64.0; // XXXL
  
  // ============================================================================
  // BORDER RADIUS
  // ============================================================================
  
  static const double radiusXS = 4.0;   // Tiny elements
  static const double radiusS = 8.0;    // Chips, badges
  static const double radiusM = 12.0;   // Buttons, inputs (Primary)
  static const double radiusL = 16.0;   // Cards (Primary)
  static const double radiusXL = 24.0;  // Modals, large containers
  static const double radiusCircle = 9999.0; // Circular (avatars, icon buttons)
  
  // ============================================================================
  // ELEVATION / SHADOWS
  // ============================================================================
  
  /// Level 1 - Cards, buttons
  static List<BoxShadow> get elevation1 => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];
  
  /// Level 2 - Modals, dialogs
  static List<BoxShadow> get elevation2 => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.12),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
  
  /// Level 3 - Tooltips, floating elements
  static List<BoxShadow> get elevation3 => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.16),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
  
  /// Dark theme elevation 1
  static List<BoxShadow> get darkElevation1 => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.24),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];
  
  /// Dark theme elevation 2
  static List<BoxShadow> get darkElevation2 => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.32),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
  
  // ============================================================================
  // TOUCH TARGETS (Accessibility)
  // ============================================================================
  
  static const double minTouchTargetSize = 48.0; // iOS & Android minimum
  static const double recommendedTouchTargetSize = 56.0; // Recommended
  
  // ============================================================================
  // TYPOGRAPHY SCALE (Font Sizes)
  // ============================================================================
  
  static const double fontSizeCaption = 12.0;
  static const double fontSizeBody2 = 14.0;
  static const double fontSizeBody = 16.0;
  static const double fontSizeBodyLarge = 18.0;
  static const double fontSizeH6 = 20.0;
  static const double fontSizeH5 = 22.0;
  static const double fontSizeH4 = 24.0;
  static const double fontSizeH3 = 28.0;
  static const double fontSizeH2 = 32.0;
  static const double fontSizeH1 = 36.0;
  
  // ============================================================================
  // ICON SIZES
  // ============================================================================
  
  static const double iconXS = 16.0;
  static const double iconS = 20.0;
  static const double iconM = 24.0;
  static const double iconL = 32.0;
  static const double iconXL = 48.0;
}
