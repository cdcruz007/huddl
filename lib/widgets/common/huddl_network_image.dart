import 'dart:convert';
import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';

// =============================================================================
// HUDDL NETWORK IMAGE — universal photo handler for every card in the app
//
// Handles: http/https URLs, data:URI base64, asset paths, empty strings
// Loading:  animated shimmer (1200ms, easeInOutSine, dark-mode aware)
// Error:    optional fallback widget, defaults to grey + icon
// Empty:    same as error — never blank
//
// Usage:
//   HuddlNetworkImage(url: item.imageUrl, width: 64, height: 64)
//   HuddlNetworkImage(url: group.imageUrl, fallbackIcon: Icons.people)
//   HuddlNetworkImage(url: meetup.imageUrl, aspectRatio: 16/9)
// =============================================================================

class HuddlNetworkImage extends StatelessWidget {
  const HuddlNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.aspectRatio,   // if set, wraps in AspectRatio — ignores height
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallbackIcon = Icons.image_outlined,
    this.fallbackIconSize = 28.0,
    this.fallbackColor,  // null = warm grey
    this.fallbackWidget, // fully custom fallback — overrides icon
  });

  final String url;
  final double? width;
  final double? height;
  final double? aspectRatio;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData fallbackIcon;
  final double fallbackIconSize;
  final Color? fallbackColor;
  final Widget? fallbackWidget;

  // ── Shimmer loading placeholder ─────────────────────────────────────────
  Widget _shimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _HuddlShimmer(
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      isDark: isDark,
      borderRadius: borderRadius?.topLeft.x ?? 0,
    );
  }

  // ── Error / empty fallback ──────────────────────────────────────────────
  Widget _fallback(BuildContext context) {
    if (fallbackWidget != null) return fallbackWidget!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      color: fallbackColor
          ?? (isDark ? HuddlColors.darkSurfaceVariant : const Color(0xFFF7F7F7)),
      child: Center(
        child: Icon(
          fallbackIcon,
          size: fallbackIconSize,
          color: isDark ? HuddlColors.darkTextTertiary : HuddlColors.textTertiary,
        ),
      ),
    );
  }

  // ── Image resolver ──────────────────────────────────────────────────────
  Widget _buildImage(BuildContext context) {
    if (url.isEmpty) return _fallback(context);

    // data:URI — base64 encoded (user photo uploads)
    if (url.startsWith('data:')) {
      try {
        final comma = url.indexOf(',');
        if (comma >= 0) {
          final bytes = base64Decode(url.substring(comma + 1));
          return Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => _fallback(context),
          );
        }
      } catch (_) {}
      return _fallback(context);
    }

    // Asset path
    if (url.startsWith('assets/')) {
      return Image.asset(
        url,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _fallback(context),
      );
    }

    // HTTP/HTTPS network image — shimmer while loading
    if (url.startsWith('http')) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (_, child, progress) =>
          progress == null ? child : _shimmer(context),
        errorBuilder: (_, __, ___) => _fallback(context),
      );
    }

    // Unknown format
    return _fallback(context);
  }

  @override
  Widget build(BuildContext context) {
    Widget image = _buildImage(context);

    if (aspectRatio != null) {
      image = AspectRatio(aspectRatio: aspectRatio!, child: image);
    }

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }

    return image;
  }
}

// ── Shimmer animation ─────────────────────────────────────────────────────────
// 1200ms repeat, easeInOutSine, dark-mode aware — identical spec to
// _ShimmerBox in marketplace_screen.dart and _DetailShimmer in item_detail_screen.dart.
// Extracted here as the single canonical shimmer implementation.

class _HuddlShimmer extends StatefulWidget {
  final double width;
  final double height;
  final bool isDark;
  final double borderRadius;

  const _HuddlShimmer({
    required this.width,
    required this.height,
    required this.isDark,
    this.borderRadius = 0,
  });

  @override
  State<_HuddlShimmer> createState() => _HuddlShimmerState();
}

class _HuddlShimmerState extends State<_HuddlShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFE8E8E8);
    final highlight = widget.isDark
        ? const Color(0xFF3D3D3D)
        : const Color(0xFFF5F5F5);

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value + 1, 0),
            colors: [base, highlight, base],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// HUDDL SHIMMER — public wrapper for standalone shimmer use in detail screens
//
// Use this when you need a shimmer placeholder outside of HuddlNetworkImage,
// e.g. inside a loadingBuilder or as a SliverAppBar background placeholder.
//
// Usage:
//   const HuddlShimmer(width: double.infinity, height: double.infinity)
//   HuddlShimmer(width: 300, height: 200, borderRadius: 12)
// =============================================================================

class HuddlShimmer extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;

  const HuddlShimmer({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _HuddlShimmer(
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      isDark: isDark,
      borderRadius: borderRadius,
    );
  }
}
