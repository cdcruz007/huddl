import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';

/// Demo photo gallery URLs for the image picker.
/// In a real app these would come from the device camera roll.
const List<String> _kGalleryPhotos = [
  'https://images.pexels.com/photos/1680172/pexels-photo-1680172.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/3807517/pexels-photo-3807517.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/1648776/pexels-photo-1648776.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/2253275/pexels-photo-2253275.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/1689731/pexels-photo-1689731.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/4473891/pexels-photo-4473891.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/4473870/pexels-photo-4473870.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/1684187/pexels-photo-1684187.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/3933881/pexels-photo-3933881.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/3807529/pexels-photo-3807529.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/1166990/pexels-photo-1166990.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/3763585/pexels-photo-3763585.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/2820884/pexels-photo-2820884.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/1758144/pexels-photo-1758144.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/3807547/pexels-photo-3807547.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/3662770/pexels-photo-3662770.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/3933250/pexels-photo-3933250.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/4473892/pexels-photo-4473892.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/3807634/pexels-photo-3807634.jpeg?auto=compress&cs=tinysrgb&w=400',
  'https://images.pexels.com/photos/1684188/pexels-photo-1684188.jpeg?auto=compress&cs=tinysrgb&w=400',
];

/// A full-screen image gallery picker that displays a grid of photos.
/// The user taps a photo to select it, then taps "Done" to return
/// the selected image URLs.
///
/// Design: "< Gallery" back arrow header with "DONE" button (orange/coral).
/// 3-column grid of square thumbnails with a check overlay on selected items.
class ImageGalleryPicker extends StatefulWidget {
  /// Whether multiple images can be selected.
  final bool allowMultiple;

  const ImageGalleryPicker({super.key, this.allowMultiple = false});

  @override
  State<ImageGalleryPicker> createState() => _ImageGalleryPickerState();
}

class _ImageGalleryPickerState extends State<ImageGalleryPicker> {
  final Set<int> _selectedIndices = {};

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        if (!widget.allowMultiple) {
          _selectedIndices.clear();
        }
        _selectedIndices.add(index);
      }
    });
  }

  void _done() {
    final urls = _selectedIndices.map((i) => _kGalleryPhotos[i]).toList();
    Navigator.pop(context, urls);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.white,
      appBar: AppBar(
        backgroundColor: HuddlColors.white,
        elevation: 0,
        surfaceTintColor: HuddlColors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: HuddlColors.textDark),
          onPressed: () => Navigator.pop(context, null),
        ),
        title: Text(
          'Gallery',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: HuddlColors.textDark,
          ),
        ),
        actions: [
          if (_selectedIndices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: _done,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: HuddlColors.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    'DONE',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: HuddlColors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: HuddlColors.divider),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(2),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: _kGalleryPhotos.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedIndices.contains(index);
          return GestureDetector(
            onTap: () => _toggleSelection(index),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  _kGalleryPhotos[index],
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: HuddlColors.background,
                    child: const Icon(Icons.broken_image,
                        color: HuddlColors.textHint),
                  ),
                ),
                // Selection overlay
                if (isSelected)
                  Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: HuddlColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check,
                            size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                // Selection order number for multi-select
                if (isSelected && widget.allowMultiple)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: HuddlColors.primary,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${_selectedIndices.toList().indexOf(index) + 1}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
