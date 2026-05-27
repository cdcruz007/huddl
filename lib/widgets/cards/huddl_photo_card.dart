import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../theme/huddl_animations.dart';

// =============================================================================
// HUDDL PHOTO CARD — Airbnb-inspired photography-first card system
// =============================================================================
//
// THREE LAYOUTS:
//
// 1. HuddlSinglePhotoCard — full-bleed hero image, minimal text below
//    → Use for meetups, events, featured groups
//
// 2. HuddlMosaicPhotoCard — 2×2 grid photo collage (Airbnb experiences style)
//    → Use for groups with multiple photos, experience cards
//
// 3. HuddlHorizontalCard — left photo + right text (compact list view)
//    → Use in search results, compact feeds
//
// DESIGN PRINCIPLES (derived from Airbnb analysis):
//   • Photography fills the card — text is minimal, below the fold
//   • No card borders — shadow provides depth instead
//   • Corner radius: 14dp (softer than current huddl 16dp)
//   • Save/heart is always top-right, semi-transparent dark bg
//   • Badge (Popular / Guest favorite) top-left — dark pill
//   • Price/key-stat is BOLD, rest is regular weight
//   • Generous padding: 0 around photo, 12px around text
//
// =============================================================================

// ── 1. Single hero photo card ─────────────────────────────────────────────────

class HuddlSinglePhotoCard extends StatefulWidget {
  const HuddlSinglePhotoCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    this.badge,
    this.stat,
    this.statIcon,
    this.isSaved = false,
    this.onSave,
    this.onTap,
    this.aspectRatio = 1.2, // wider than tall for meetup cards
    this.showSaveButton = true,
  });

  final String imageUrl;
  final String title;
  final String subtitle;
  final String? badge;
  final String? stat;
  final IconData? statIcon;
  final bool isSaved;
  final VoidCallback? onSave;
  final VoidCallback? onTap;
  final double aspectRatio;
  final bool showSaveButton;

  @override
  State<HuddlSinglePhotoCard> createState() => _HuddlSinglePhotoCardState();
}

class _HuddlSinglePhotoCardState extends State<HuddlSinglePhotoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scaleAnim;
  bool _localSaved = false;

  @override
  void initState() {
    super.initState();
    _localSaved = widget.isSaved;
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.975).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        HuddlAnimations.lightTap();
        widget.onTap?.call();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Photo container ──────────────────────────────────────────────
            AspectRatio(
              aspectRatio: widget.aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Photo
                    _HuddlPhotoImage(url: widget.imageUrl),

                    // Subtle gradient overlay at bottom for text legibility
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.18),
                            ],
                            stops: const [0.55, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // Badge — top left
                    if (widget.badge != null)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _HuddlBadge(label: widget.badge!),
                      ),

                    // Save button — top right
                    if (widget.showSaveButton)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _HeartButton(
                          isSaved: _localSaved,
                          onTap: () {
                            setState(() => _localSaved = !_localSaved);
                            HuddlAnimations.mediumTap();
                            widget.onSave?.call();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── Text below photo ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? HuddlColors.darkTextPrimary
                                : HuddlColors.textDark,
                            height: 1.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: isDark
                                ? HuddlColors.darkTextSecondary
                                : HuddlColors.textSecondary,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Stat (rating / attendee count)
                  if (widget.stat != null) ...[
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.statIcon ?? Icons.star,
                          size: 13,
                          color: isDark
                              ? HuddlColors.darkTextPrimary
                              : HuddlColors.textDark,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          widget.stat!,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? HuddlColors.darkTextPrimary
                                : HuddlColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 2. Mosaic 2×2 photo card (Airbnb experiences style) ──────────────────────

class HuddlMosaicPhotoCard extends StatefulWidget {
  const HuddlMosaicPhotoCard({
    super.key,
    required this.images, // 1–4 images; <4 fills remaining with placeholder
    required this.title,
    required this.subtitle,
    this.badge,
    this.stat,
    this.isSaved = false,
    this.onSave,
    this.onTap,
    this.showSaveButton = true,
  });

  final List<String> images;
  final String title;
  final String subtitle;
  final String? badge;
  final String? stat;
  final bool isSaved;
  final VoidCallback? onSave;
  final VoidCallback? onTap;
  final bool showSaveButton;

  @override
  State<HuddlMosaicPhotoCard> createState() => _HuddlMosaicPhotoCardState();
}

class _HuddlMosaicPhotoCardState extends State<HuddlMosaicPhotoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scaleAnim;
  bool _localSaved = false;

  @override
  void initState() {
    super.initState();
    _localSaved = widget.isSaved;
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.975).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final imgs = List<String>.from(widget.images);
    while (imgs.length < 4) {
      imgs.add('');
    }

    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        HuddlAnimations.lightTap();
        widget.onTap?.call();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Mosaic grid ──────────────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 1.1,
                child: Stack(
                  children: [
                    // 2×2 grid with 2px gap
                    Column(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(child: _HuddlPhotoImage(url: imgs[0])),
                              const SizedBox(width: 2),
                              Expanded(child: _HuddlPhotoImage(url: imgs[1])),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(child: _HuddlPhotoImage(url: imgs[2])),
                              const SizedBox(width: 2),
                              Expanded(child: _HuddlPhotoImage(url: imgs[3])),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Badge — top left
                    if (widget.badge != null)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _HuddlBadge(label: widget.badge!),
                      ),

                    // Save — top right
                    if (widget.showSaveButton)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _HeartButton(
                          isSaved: _localSaved,
                          onTap: () {
                            setState(() => _localSaved = !_localSaved);
                            HuddlAnimations.mediumTap();
                            widget.onSave?.call();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── Text ─────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? HuddlColors.darkTextPrimary
                                : HuddlColors.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: isDark
                                ? HuddlColors.darkTextSecondary
                                : HuddlColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (widget.stat != null) ...[
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, size: 13,
                            color: isDark
                                ? HuddlColors.darkTextPrimary
                                : HuddlColors.textDark),
                        const SizedBox(width: 2),
                        Text(widget.stat!,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? HuddlColors.darkTextPrimary
                                  : HuddlColors.textDark,
                            )),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 3. Horizontal compact card ────────────────────────────────────────────────

class HuddlHorizontalCard extends StatelessWidget {
  const HuddlHorizontalCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.badge,
    this.onTap,
  });

  final String imageUrl;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        HuddlAnimations.lightTap();
        onTap?.call();
      },
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 80,
              height: 80,
              child: _HuddlPhotoImage(url: imageUrl),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? HuddlColors.darkTextPrimary
                          : HuddlColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: isDark
                          ? HuddlColors.darkTextSecondary
                          : HuddlColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _HuddlPhotoImage extends StatelessWidget {
  const _HuddlPhotoImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (url.isEmpty) {
      return Container(
        color: isDark ? HuddlColors.darkSurfaceVariant : const Color(0xFFF7F7F7),
        child: Icon(Icons.image_outlined, size: 24,
            color: isDark ? HuddlColors.darkTextTertiary : HuddlColors.textTertiary),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(
          color: isDark ? HuddlColors.darkSurfaceVariant : HuddlColors.gray200,
        );
      },
      errorBuilder: (_, __, ___) => Container(
        color: isDark ? HuddlColors.darkSurfaceVariant : const Color(0xFFF7F7F7),
        child: Icon(Icons.broken_image_outlined, size: 24,
            color: isDark ? HuddlColors.darkTextTertiary : HuddlColors.textTertiary),
      ),
    );
  }
}

// Dark pill badge — e.g. "Popular", "New", "Going"
class _HuddlBadge extends StatelessWidget {
  const _HuddlBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: HuddlColors.textDark,
        ),
      ),
    );
  }
}

// Animated heart save button with pop effect
class _HeartButton extends StatefulWidget {
  const _HeartButton({required this.isSaved, required this.onTap});
  final bool isSaved;
  final VoidCallback onTap;

  @override
  State<_HeartButton> createState() => _HeartButtonState();
}

class _HeartButtonState extends State<_HeartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(_HeartButton old) {
    super.didUpdateWidget(old);
    if (widget.isSaved != old.isSaved && widget.isSaved) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          shape: BoxShape.circle,
        ),
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Icon(
            widget.isSaved ? Icons.favorite : Icons.favorite_border,
            size: 18,
            color: widget.isSaved ? HuddlColors.error : Colors.white,
          ),
        ),
      ),
    );
  }
}
