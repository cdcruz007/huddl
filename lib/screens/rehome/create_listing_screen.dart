import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/huddl_colors.dart';
import '../../services/rehome_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/postcode_service.dart';

// =============================================================================
// CREATE / EDIT LISTING SCREEN — age-stage-first posting flow
// Matches the Create Group / Create Meetup design language:
//   - Circle-icon age cards (matching onboarding mum/dad style)
//   - Multi-photo carousel with camera/gallery picker (no file upload)
//   - Stacked input fields with clean separators
//   - Blue accent photo area
// =============================================================================

class CreateListingScreen extends StatefulWidget {
  /// When non-null the screen opens in **edit mode**.
  final RehomeItem? existingItem;

  const CreateListingScreen({super.key, this.existingItem});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _picker = ImagePicker();

  AgeStage? _selectedAge;
  ItemCategory? _selectedCategory;
  ItemCondition? _selectedCondition;
  bool _isFree = false;
  final List<String> _pickedImages = []; // supports multiple images
  bool _isCreating = false;
  int _currentImagePage = 0;

  bool get _isEditing => widget.existingItem != null;

  // Stepper: 0 = age, 1 = category, 2 = details
  int _step = 0;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final item = widget.existingItem!;
      _selectedAge = item.ageStage;
      _selectedCategory = item.category;
      _selectedCondition = item.condition;
      _titleController.text = item.title;
      _descriptionController.text = item.description;
      _isFree = item.isFree;
      if (!_isFree) _priceController.text = item.price.toStringAsFixed(item.price.truncateToDouble() == item.price ? 0 : 2);
      _pickedImages.addAll(item.imageUrls);
      _step = 2; // go straight to details in edit mode
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  bool get _canProceedStep0 => _selectedAge != null;
  bool get _canProceedStep1 => _selectedCategory != null && _selectedCondition != null;
  bool get _canSubmit =>
      _titleController.text.trim().isNotEmpty &&
      _descriptionController.text.trim().isNotEmpty &&
      (_isFree || _priceController.text.trim().isNotEmpty);

  // ── Image picker — camera/gallery only (matching Create Group style) ──

  Future<void> _showImagePickerSheet() async {
    if (kIsWeb) {
      await _pickMultipleFromGallery();
      return;
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: HuddlColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Add photos',
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: HuddlColors.textDark)),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                    color: HuddlColors.peachLight, shape: BoxShape.circle),
                child: const Icon(Icons.photo_library_outlined,
                    color: HuddlColors.primary),
              ),
              title: const Text('Choose from gallery',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: const Text('Select multiple photos',
                  style: TextStyle(fontSize: 12, color: HuddlColors.textHint)),
              onTap: () {
                Navigator.pop(ctx);
                _pickMultipleFromGallery();
              },
            ),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                    color: HuddlColors.peachLight, shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt_outlined,
                    color: HuddlColors.primary),
              ),
              title: const Text('Take a photo',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromCamera();
              },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickMultipleFromGallery() async {
    try {
      final files = await _picker.pickMultiImage(
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      for (final file in files) {
        final bytes = await file.readAsBytes();
        final b64 = base64Encode(bytes);
        final mimeType = file.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
        setState(() => _pickedImages.add('data:$mimeType;base64,$b64'));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not access photos: $e'),
            backgroundColor: HuddlColors.error,
          ),
        );
      }
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      final mimeType = file.name.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      setState(() => _pickedImages.add('data:$mimeType;base64,$b64'));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not access camera: $e'),
            backgroundColor: HuddlColors.error,
          ),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _pickedImages.removeAt(index);
      if (_currentImagePage >= _pickedImages.length && _pickedImages.isNotEmpty) {
        _currentImagePage = _pickedImages.length - 1;
      }
    });
  }

  // ── Submit / Update ──

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isCreating = true);

    final onboarding = OnboardingDataService();
    await onboarding.initialize();
    final sellerName = onboarding.name ?? 'You';
    final postcode = onboarding.postcode;
    final borough = PostcodeService().getBoroughFromPostcode(postcode ?? '');

    final price = _isFree
        ? 0.0
        : (double.tryParse(_priceController.text.trim()) ?? 0);

    final locationStr = (borough != null && borough != 'Unknown Borough')
        ? borough
        : 'Your area';

    final images = _pickedImages.isNotEmpty
        ? _pickedImages
        : ['https://images.pexels.com/photos/3661452/pexels-photo-3661452.jpeg?auto=compress&cs=tinysrgb&w=600'];

    if (_isEditing) {
      final updated = RehomeItem(
        id: widget.existingItem!.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        ageStage: _selectedAge!,
        category: _selectedCategory!,
        condition: _selectedCondition!,
        price: price,
        imageUrls: images,
        sellerName: widget.existingItem!.sellerName,
        sellerId: widget.existingItem!.sellerId,
        sellerLocation: widget.existingItem!.sellerLocation,
        listedAt: widget.existingItem!.listedAt,
        viewCount: widget.existingItem!.viewCount,
        offerCount: widget.existingItem!.offerCount,
      );
      RehomeService().updateListing(updated);
      setState(() => _isCreating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('${updated.title} updated successfully!')),
            ]),
            backgroundColor: HuddlColors.teal,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context, updated);
      }
    } else {
      final newItem = RehomeItem(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        ageStage: _selectedAge!,
        category: _selectedCategory!,
        condition: _selectedCondition!,
        price: price,
        imageUrls: images,
        sellerName: sellerName,
        sellerId: 'current_user',
        sellerLocation: locationStr,
        listedAt: DateTime.now(),
      );
      RehomeService().addListing(newItem);
      setState(() => _isCreating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('${newItem.title} listed successfully!')),
            ]),
            backgroundColor: HuddlColors.teal,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context, newItem);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: HuddlColors.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditing
              ? 'Edit listing'
              : _step == 0
                  ? 'Who is this for?'
                  : _step == 1
                      ? 'What are you selling?'
                      : 'Item details',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: HuddlColors.textDark,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / 3,
            backgroundColor: HuddlColors.divider,
            valueColor: const AlwaysStoppedAnimation(HuddlColors.primary),
            minHeight: 3,
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _step == 0
            ? _buildStep0()
            : _step == 1
                ? _buildStep1()
                : _buildStep2(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 0: Age / Stage selection — onboarding mum/dad circle-icon style
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep0() {
    return Column(
      key: const ValueKey('step0'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Select the age group this item is suited for.',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  color: HuddlColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              ...AgeStage.values.map((age) => _AgeStageCard(
                    age: age,
                    isSelected: _selectedAge == age,
                    onTap: () => setState(() => _selectedAge = age),
                  )),
            ],
          ),
        ),
        _buildBottomButton(
          label: 'Next',
          enabled: _canProceedStep0,
          onTap: () => setState(() => _step = 1),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 1: Category + Condition — clean list style from screenshot
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep1() {
    return Column(
      key: const ValueKey('step1'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Category — simple list with dividers (matching screenshot)
              Text(
                'Category',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.textDark,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: HuddlColors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: HuddlColors.divider),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < ItemCategory.values.length; i++) ...[
                      _CategoryListTile(
                        category: ItemCategory.values[i],
                        isSelected: _selectedCategory == ItemCategory.values[i],
                        onTap: () => setState(() => _selectedCategory = ItemCategory.values[i]),
                        isFirst: i == 0,
                        isLast: i == ItemCategory.values.length - 1,
                      ),
                      if (i < ItemCategory.values.length - 1)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Condition
              Text(
                'Condition',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.textDark,
                ),
              ),
              const SizedBox(height: 10),
              ...ItemCondition.values.map((cond) {
                final isSelected = _selectedCondition == cond;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCondition = cond),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? HuddlColors.primary.withValues(alpha: 0.08)
                          : HuddlColors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? HuddlColors.primary : HuddlColors.divider,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: isSelected ? HuddlColors.primary : HuddlColors.textHint,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          cond.label,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? HuddlColors.primary : HuddlColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        _buildBottomButton(
          label: 'Next',
          enabled: _canProceedStep1,
          onTap: () => setState(() => _step = 2),
          showBack: true,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 2: Details — blue photo area + stacked inputs (Create Group style)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep2() {
    return Column(
      key: const ValueKey('step2'),
      children: [
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Photo carousel / Add photos area ──
                _buildPhotoArea(),
                const SizedBox(height: 20),

                // Selection summary (show in non-edit or always)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: HuddlColors.peachVeryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: HuddlColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_selectedAge?.shortLabel ?? ''} \u2022 ${_selectedCategory?.label ?? ''} \u2022 ${_selectedCondition?.label ?? ''}',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: HuddlColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (_isEditing)
                        GestureDetector(
                          onTap: () => setState(() => _step = 0),
                          child: Text('Edit',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Item name
                _LabeledField(
                  label: 'Item name',
                  child: TextFormField(
                    controller: _titleController,
                    style: GoogleFonts.poppins(fontSize: 15, color: HuddlColors.textDark),
                    decoration: _inputDecoration('e.g. Silver Cross pram with accessories'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Enter a title' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 16),

                // Price
                _LabeledField(
                  label: 'Price',
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _priceController,
                          style: GoogleFonts.poppins(fontSize: 15, color: HuddlColors.textDark),
                          decoration: _inputDecoration('\u00A30.00'),
                          keyboardType: TextInputType.number,
                          enabled: !_isFree,
                          validator: (v) {
                            if (_isFree) return null;
                            if (v == null || v.trim().isEmpty) return 'Enter a price or select Free';
                            return null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isFree = !_isFree;
                            if (_isFree) _priceController.clear();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: _isFree ? HuddlColors.blue : HuddlColors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _isFree ? HuddlColors.blue : HuddlColors.divider,
                            ),
                          ),
                          child: Text(
                            'Free',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _isFree ? Colors.white : HuddlColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Description
                _LabeledField(
                  label: 'Description',
                  child: TextFormField(
                    controller: _descriptionController,
                    style: GoogleFonts.poppins(fontSize: 15, color: HuddlColors.textDark),
                    decoration: _inputDecoration(
                        'Describe the item \u2014 condition, brand, what\'s included...'),
                    maxLines: 4,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Enter a description' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
        _buildBottomButton(
          label: _isCreating
              ? (_isEditing ? 'Updating...' : 'Listing...')
              : (_isEditing ? 'Update listing' : 'List item'),
          enabled: _canSubmit && !_isCreating,
          onTap: _submit,
          showBack: !_isEditing,
        ),
      ],
    );
  }

  // ── Blue photo area with carousel dots — matching screenshot ──

  Widget _buildPhotoArea() {
    if (_pickedImages.isEmpty) {
      // Empty state — large blue add-photo area
      return GestureDetector(
        onTap: _showImagePickerSheet,
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            color: HuddlColors.blue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: HuddlColors.blue.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: HuddlColors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: HuddlColors.blue.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.add, size: 30, color: HuddlColors.blue),
              ),
              const SizedBox(height: 12),
              Text(
                'Add photos',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.blue,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Take photos or choose from gallery',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: HuddlColors.textHint,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Has images — carousel with dots + add more button
    return Column(
      children: [
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: HuddlColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: HuddlColors.divider, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              PageView.builder(
                itemCount: _pickedImages.length,
                onPageChanged: (i) => setState(() => _currentImagePage = i),
                itemBuilder: (_, i) => Stack(
                  children: [
                    SizedBox.expand(child: _buildPreviewImage(_pickedImages[i])),
                    // Delete badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => _removeImage(i),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Dot indicators
              if (_pickedImages.length > 1)
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pickedImages.length, (i) {
                      return Container(
                        width: i == _currentImagePage ? 18 : 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i == _currentImagePage
                              ? HuddlColors.blue
                              : Colors.white.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _showImagePickerSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: HuddlColors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_a_photo, size: 18, color: HuddlColors.blue),
                const SizedBox(width: 8),
                Text(
                  'Add more photos',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.blue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewImage(String url) {
    if (url.startsWith('data:')) {
      try {
        final dataUri = Uri.parse(url);
        final bytes = dataUri.data?.contentAsBytes();
        if (bytes != null) {
          return Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
        }
      } catch (_) {}
    }
    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _imagePlaceholder(),
      );
    }
    return _imagePlaceholder();
  }

  Widget _imagePlaceholder() {
    return Container(
      color: HuddlColors.peachLight,
      child: const Center(
        child: Icon(Icons.image_outlined, size: 48, color: HuddlColors.primary),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
      filled: true,
      fillColor: HuddlColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: HuddlColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: HuddlColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: HuddlColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: HuddlColors.error),
      ),
    );
  }

  Widget _buildBottomButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool showBack = false,
  }) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (showBack)
            Expanded(
              flex: 1,
              child: OutlinedButton(
                onPressed: () => setState(() => _step--),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: HuddlColors.divider),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  'Back',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: HuddlColors.textSecondary,
                  ),
                ),
              ),
            ),
          if (showBack) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: enabled ? onTap : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: HuddlColors.primary,
                disabledBackgroundColor: HuddlColors.primary.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// AGE STAGE CARD — matching onboarding mum/dad _ParentTypeCard style
// Circle icon on the left, label + subtitle, check circle on select.
// =============================================================================

class _AgeStageCard extends StatelessWidget {
  final AgeStage age;
  final bool isSelected;
  final VoidCallback onTap;

  const _AgeStageCard({
    required this.age,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = isSelected ? HuddlColors.primary : HuddlColors.textHint;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? HuddlColors.primary.withValues(alpha: 0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? HuddlColors.primary : HuddlColors.divider,
            width: isSelected ? 1.8 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Circle icon — matching onboarding _ParentTypeCard
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (isSelected ? HuddlColors.primary : HuddlColors.textHint)
                    .withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? HuddlColors.primary : HuddlColors.divider,
                  width: 1.5,
                ),
              ),
              child: Icon(age.icon,
                  color: isSelected ? HuddlColors.primary : HuddlColors.textHint,
                  size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    age.label,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? HuddlColors.primary : HuddlColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    age.shortLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: HuddlColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, size: 22, color: accentColor),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// CATEGORY LIST TILE — clean list style matching the screenshot
// =============================================================================

class _CategoryListTile extends StatelessWidget {
  final ItemCategory category;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;

  const _CategoryListTile({
    required this.category,
    required this.isSelected,
    required this.onTap,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? HuddlColors.primary.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.vertical(
            top: isFirst ? const Radius.circular(14) : Radius.zero,
            bottom: isLast ? const Radius.circular(14) : Radius.zero,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                category.label,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? HuddlColors.primary : HuddlColors.textDark,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, size: 20, color: HuddlColors.primary),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// LABELED FIELD
// =============================================================================

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: HuddlColors.textDark,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
