import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';

/// A production-safe wrapper around [Image.network] that provides:
/// - Error handling with a branded placeholder icon
/// - Loading indicator while the image fetches
/// - Consistent fallback for broken/missing URLs
///
/// Use this widget everywhere in the app instead of raw [Image.network].
class SafeNetworkImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData placeholderIcon;
  final double placeholderIconSize;
  final Color? placeholderColor;

  const SafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderIcon = Icons.image_outlined,
    this.placeholderIconSize = 32,
    this.placeholderColor,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return _placeholder(context);
    }

    Widget image = Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _loading(context);
      },
      errorBuilder: (context, error, stackTrace) {
        return _placeholder(context);
      },
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }

    return image;
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: placeholderColor ??
            const Color(0xFFF7F7F7),
        borderRadius: borderRadius,
      ),
      child: Center(
        child: Icon(
          placeholderIcon,
          size: placeholderIconSize,
          color: HuddlColors.textTertiary,
        ),
      ),
    );
  }

  Widget _loading(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: borderRadius,
      ),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: HuddlColors.textTertiary,
          ),
        ),
      ),
    );
  }
}
