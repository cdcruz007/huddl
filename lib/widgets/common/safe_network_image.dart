import 'package:flutter/material.dart';
import '../../theme/huddl_icons.dart';
import 'huddl_network_image.dart';

// COMPATIBILITY SHIM — all new code should use HuddlNetworkImage directly.
// SafeNetworkImage delegates to HuddlNetworkImage for consistent shimmer
// loading. The CircularProgressIndicator loading state has been removed.
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
    this.placeholderIcon = HuddlIcons.image,
    this.placeholderIconSize = 32,
    this.placeholderColor,
  });

  @override
  Widget build(BuildContext context) {
    return HuddlNetworkImage(
      url: imageUrl ?? '',
      width: width,
      height: height,
      fit: fit,
      borderRadius: borderRadius,
      fallbackIcon: placeholderIcon,
      fallbackIconSize: placeholderIconSize,
      fallbackColor: placeholderColor,
    );
  }
}
