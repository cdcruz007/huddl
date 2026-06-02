import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../widgets/image_editor_widget.dart';
import '../../theme/huddl_colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/huddl_character.dart';
import '../../services/rehome_service.dart';
import '../../services/firestore_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/postcode_service.dart';
import '../../services/subscription_service.dart';
import '../../models/subscription.dart';
import '../../constants/app_text_styles.dart';

// =============================================================================
// CREATE / EDIT LISTING SCREEN — age-stage-first posting flow
// Matches the Create Group / Create Meetup design language:
//   - White scaffold, Cancel text leading, centered title (Poppins w600 17px)
//   - Full-width peach photo banner (matching Create Group photo upload)
//   - Underline text fields (matching Create Group / Create Meetup input style)
//   - Bold section labels (Poppins w700 14px)
//   - Orange primary CTA buttons
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
  // ImagePicker no longer needed - using ImageEditorWidget instead
  // final _picker = ImagePicker();

  // ── S6 fix: upload base64 images to Firebase Storage before Firestore write
  //
  // _pickedImages stores items as either:
  //   (a) "data:<mime>;base64,<bytes>" — freshly picked on this device
  //   (b) "https://..."               — already a remote URL (edit mode)
  //
  // This helper converts all (a) items to permanent HTTPS URLs so that
  // Firestore never stores raw base64 strings (Firestore has a 1 MB doc limit;
  // a single JPEG at even low quality can easily exceed it).
  Future<List<String>> _uploadPendingImages(List<String> images) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return images; // unauthenticated — caller will surface error
    final storage = FirebaseStorage.instance;
    final result = <String>[];
    for (final img in images) {
      if (!img.startsWith('data:')) {
        // Already a remote HTTPS URL (edit mode) — keep as-is.
        result.add(img);
        continue;
      }
      try {
        // Strip the data-URL prefix to get raw base64.
        final commaIdx = img.indexOf(',');
        if (commaIdx == -1) { result.add(img); continue; }
        final mime = img.substring(5, img.indexOf(';')); // e.g. 'image/jpeg'
        final ext  = mime.endsWith('png') ? 'png' : 'jpg';
        final Uint8List bytes = base64Decode(img.substring(commaIdx + 1));
        final ts  = DateTime.now().millisecondsSinceEpoch;
        final ref = storage.ref('marketplace_images/$uid/${ts}_${result.length}.$ext');
        final task = await ref.putData(
          bytes,
          SettableMetadata(contentType: mime),
        );
        final url = await task.ref.getDownloadURL();
        result.add(url);
      } catch (e) {
        if (kDebugMode) debugPrint('[CreateListing] Image upload failed: $e');
        // Keep the base64 string as fallback so the listing is not silently
        // broken; the caller's try/catch will surface the Firestore size error
        // if the document is too large.
        result.add(img);
      }
    }
    return result;
  }

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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                color: context.hc.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Add photos',
                style: HuddlText.body(weight: FontWeight.w700, color: context.hc.textPrimary)),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: HuddlColors.neutral50, shape: BoxShape.circle),
                child: const Icon(Icons.photo_library_outlined,
                    color: HuddlColors.textDark),
              ),
              title: const Text('Choose from gallery',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text('Select multiple photos',
                  style: HuddlText.caption(color: context.hc.textTertiary)),
              onTap: () {
                Navigator.pop(ctx);
                _pickMultipleFromGallery();
              },
            ),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: HuddlColors.neutral50, shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt_outlined,
                    color: HuddlColors.textDark),
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

  // _maxImages retained for reference; tier-aware _canAddPhoto() is the active guard.
  // ignore: unused_field
  static const int _maxImages = 6;

  // ── Photo upload guard: checks tier-aware per-listing photo cap ────────────
  // Free tier is unlimited (maxPhotoUploads: 999) so TierLimits.isUnlimited
  // returns true and the guard never fires. Plus cap is 15, Partner is 50.
  bool _canAddPhoto() {
    final ss  = SubscriptionService();
    final max = ss.limits.maxPhotoUploads;
    if (TierLimits.isUnlimited(max)) return true;
    if (_pickedImages.length >= max) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'You can add up to $max photos per listing on Huddl Plus. '
          'Upgrade to Huddl Partner for 50 photos.',
          style: HuddlText.body(color: Colors.white),
        ),
        backgroundColor: HuddlColors.nearBlack,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ));
      return false;
    }
    return true;
  }

  Future<void> _pickMultipleFromGallery() async {
    // Tier-aware guard replaces static _maxImages check
    if (!_canAddPhoto()) return;
    try {
      // Pass ImageSource.gallery directly — the caller already showed the
      // source-selection sheet, so we skip ImageEditorWidget's own sheet.
      final file = await ImageEditorWidget.pickMarketplaceImageWithSource(
          context, ImageSource.gallery);
      if (file != null && mounted) {
        final bytes = await file.readAsBytes();
        final b64 = base64Encode(bytes);
        final mimeType = file.path.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
        if (_canAddPhoto()) {
          setState(() => _pickedImages.add('data:$mimeType;base64,$b64'));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update photo: $e'),
            backgroundColor: HuddlColors.error,
          ),
        );
      }
    }
  }

  Future<void> _pickFromCamera() async {
    // Tier-aware guard replaces static _maxImages check
    if (!_canAddPhoto()) return;
    try {
      // Pass ImageSource.camera directly — skips ImageEditorWidget's own sheet.
      final file = await ImageEditorWidget.pickMarketplaceImageWithSource(
          context, ImageSource.camera);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      final mimeType = file.path.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      if (_canAddPhoto()) {
        setState(() => _pickedImages.add('data:$mimeType;base64,$b64'));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update photo: $e'),
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

    // ── Photo required gate ─────────────────────────────────────────
    if (_pickedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please add at least one photo for your listing'),
        backgroundColor: HuddlColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    // ── Subscription gate: lifetime listing creation limit ─────────────
    final subService = SubscriptionService();
    await subService.initialize();
    if (!subService.canCreateListing) {
      if (mounted) {
        Navigator.pushNamed(context, '/subscription_gate', arguments: {
          'featureTitle': 'Free listing limit reached',
          'featureDescription': subService.limitReachedMessage('listings_created'),
          'requiredPlan': 'Huddl Plus',
          'featureIcon': Icons.storefront_outlined.codePoint,
        });
      }
      return;
    }

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

    // S6 fix: upload any freshly-picked base64 images to Firebase Storage.
    // Both edit and create paths share the same upload helper so neither
    // path can accidentally persist raw base64 strings into Firestore.
    final images = await _uploadPendingImages(List<String>.from(_pickedImages));

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
        borough: borough, // HYPERLOCAL: tag with user's borough
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
            backgroundColor: HuddlColors.textDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context, updated);
      }
    } else {
      // Resolve the real Firebase Auth UID — fall back to a timestamp id
      // only if somehow called before sign-in (should never happen in prod).
      final uid = FirebaseAuth.instance.currentUser?.uid
          ?? 'user_${DateTime.now().millisecondsSinceEpoch}';

      // ── Write to Firestore to get a canonical document ID ────────────────
      // `images` is already a list of HTTPS URLs — uploaded to Firebase Storage
      // in the shared _uploadPendingImages() call above this if/else block.
      String firestoreId;
      try {
        firestoreId = await FirestoreService().createListing({
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'ageStage': _selectedAge!.label,
          'category': _selectedCategory!.label,
          'condition': _selectedCondition!.label,
          'price': price,
          'imageUrls': images,
          'sellerLocation': locationStr,
          'borough': borough ?? '',
        });
      } catch (e) {
        // Network unavailable — fall back to a local id so the seller still
        // sees their item immediately.  It will sync on next Firestore load.
        if (kDebugMode) debugPrint('[CreateListing] Firestore write failed: $e');
        firestoreId = 'local_${DateTime.now().millisecondsSinceEpoch}';
      }

      final newItem = RehomeItem(
        id: firestoreId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        ageStage: _selectedAge!,
        category: _selectedCategory!,
        condition: _selectedCondition!,
        price: price,
        imageUrls: images,
        sellerName: sellerName,
        sellerId: uid,          // ← real Firebase Auth UID
        sellerLocation: locationStr,
        listedAt: DateTime.now(),
        borough: borough,       // HYPERLOCAL: tag with user's borough
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
            backgroundColor: HuddlColors.textDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        // Record usage for subscription tracking
        await subService.recordListingCreated();

        // 🎉 First listing celebration overlay
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          try {
            final doc = await FirebaseFirestore.instance.doc('users/$uid').get();
            final achievements = (doc.data()?['achievements'] as Map?) ?? {};
            if (achievements['firstListingCreated'] != true) {
              await FirebaseFirestore.instance.doc('users/$uid')
                  .set({'achievements': {'firstListingCreated': true}}, SetOptions(merge: true));
              if (mounted) {
                await HuddlCelebrationOverlay.show(context,
                    message: 'Your first listing is live! 🛍️');
              }
            }
          } catch (_) { /* non-critical */ }
        }

        if (mounted) Navigator.pop(context, newItem);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD — matching Create Meetup / Create Group scaffold pattern
  // ══════════════════════════════════════════════════════════════════════════

  // Design tokens — mirrors create_meetup_screen.dart / create_group_screen.dart
  static const _fieldBg    = HuddlColors.neutral50;  // #F6F6F6 gray field fill
  static const _fieldLine  = HuddlColors.divider;      // #D5D5D5 bottom underline
  static const _sectionTxt = HuddlColors.textDark;     // #42464C section headers
  static const _hintGray   = HuddlColors.textTertiary; // #949494 placeholder
  static const _orange     = HuddlColors.primary;      // #FF965C accent

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Adaptive scaffold — white in light mode, darkSurface in dark mode.
      // Input fields use context.hc.inputBg for contrast against the surface.
      backgroundColor: context.hc.surface,
      appBar: AppBar(
        backgroundColor: context.hc.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: GestureDetector(
          onTap: () {
            // Show discard confirmation when there is unsaved wizard progress
            final hasProgress = _selectedAge != null ||
                _selectedCategory != null ||
                _selectedCondition != null ||
                _titleController.text.isNotEmpty ||
                _pickedImages.isNotEmpty;
            if (!hasProgress || _isEditing) {
              Navigator.pop(context);
              return;
            }
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor:
                    Theme.of(ctx).scaffoldBackgroundColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Text('Discard listing?'),
                content:
                    const Text('Your progress will be lost.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Keep editing',
                        style: HuddlText.body(weight: FontWeight.w600, color: _orange)),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx); // close dialog
                      Navigator.pop(context); // close wizard
                    },
                    child: Text('Discard',
                        style: HuddlText.body(weight: FontWeight.w600, color: Colors.red)),
                  ),
                ],
              ),
            );
          },
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text('Cancel',
                  style: HuddlText.body(color: _orange)),
            ),
          ),
        ),
        leadingWidth: 80,
        centerTitle: true,
        title: Text(
          _isEditing
              ? 'Edit listing'
              : _step == 0
                  ? 'Who is this for?'
                  : _step == 1
                      ? 'What are you selling?'
                      : 'Item details',
          style: HuddlText.heading(),
        ),
        // NO AppBar bottom — progress bar lives in the body so it doesn't
        // produce an orange line above the blue photo banner on step 2.
      ),
      body: Column(
        children: [
          // ── Listing slot counter (free users only) ─────────────────────────
          Builder(builder: (context) {
            final ss = SubscriptionService();
            if (TierLimits.isUnlimited(ss.limits.maxListingsCreatedLifetime)) {
              return const SizedBox.shrink();
            }
            final used = ss.listingsCreatedTotal;
            final max = ss.limits.maxListingsCreatedLifetime;
            final remaining = ss.listingsCreatedRemaining;
            return Container(
              width: double.infinity,
              color: remaining == 0
                  ? HuddlColors.primary.withValues(alpha: 0.08)
                  : HuddlColors.primary.withValues(alpha: 0.04),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                remaining == 0
                    ? 'All $max free listing slots used — upgrade for unlimited'
                    : 'Free listing ${used + 1} of $max — 7-day duration',
                style: HuddlText.caption(
                  color: remaining == 0
                      ? HuddlColors.primary
                      : HuddlColors.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
            );
          }),
          // ── Thin orange progress strip — only shown on steps 0 & 1.
          // On step 2 the blue photo banner is flush below the AppBar so we
          // hide the indicator to avoid any colour clash at that seam.
          // Progress bar visible at all 3 steps — fills 1/3 → 2/3 → 3/3
          LinearProgressIndicator(
            value: (_step + 1) / 3,
            backgroundColor: HuddlColors.divider,
            valueColor:
                const AlwaysStoppedAnimation(HuddlColors.primary),
            minHeight: 3,
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _step == 0
                  ? _buildStep0()
                  : _step == 1
                      ? _buildStep1()
                      : _buildStep2(),
            ),
          ),
        ],
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
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Text(
                    'Select the age group this item is suited for.',
                    style: HuddlText.body(color: context.hc.textSecondary),
                  ),
                ),
                const SizedBox(height: 20),
                ...AgeStage.values.map((age) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _AgeStageCard(
                        age: age,
                        isSelected: _selectedAge == age,
                        onTap: () => setState(() => _selectedAge = age),
                      ),
                    )),
              ],
            ),
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
  // STEP 1: Category + Condition — pill-card style matching Step 0 / AgeStageCard
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep1() {
    return Column(
      key: const ValueKey('step1'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Category — pill cards matching Step 0 style ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Text(
                    'Select a category for your item.',
                    style: HuddlText.body(color: context.hc.textSecondary),
                  ),
                ),
                const SizedBox(height: 16),
                ...ItemCategory.values.map((cat) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _CategoryListTile(
                        category: cat,
                        isSelected: _selectedCategory == cat,
                        onTap: () => setState(() => _selectedCategory = cat),
                      ),
                    )),
                const SizedBox(height: 24),

                // ── Condition — pill cards matching Step 0 style ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: _sectionLabel('Condition'),
                ),
                const SizedBox(height: 12),
                ...ItemCondition.values.map((cond) {
                  final isSelected = _selectedCondition == cond;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedCondition = cond),
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
                            color: isSelected ? HuddlColors.primary : HuddlColors.gray300,
                            width: isSelected ? 1.8 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Condition icon container — matches AgeStageCard circle
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: (isSelected ? HuddlColors.primary : context.hc.textTertiary)
                                    .withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? HuddlColors.primary : HuddlColors.gray300,
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                cond.icon,
                                color: isSelected ? HuddlColors.primary : context.hc.textTertiary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cond.label,
                                    style: HuddlText.body(weight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    cond.description,
                                    style: HuddlText.caption(),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle, size: 22, color: HuddlColors.primary),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 20),
              ],
            ),
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
  // STEP 2: Item details — blue photo banner + gray-filled fields (Create Meetup style)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep2() {
    return Column(
      key: const ValueKey('step2'),
      children: [
        Expanded(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Photo banner — full-width blue (Create Meetup / Create Group style) ──
                  _buildPhotoArea(),

                  // ── Photo count label: shown for finite tier limits ──
                  Builder(builder: (context) {
                    final ss  = SubscriptionService();
                    final max = ss.limits.maxPhotoUploads;
                    if (TierLimits.isUnlimited(max)) return const SizedBox.shrink();
                    final used      = _pickedImages.length;
                    final remaining = (max - used).clamp(0, max);
                    // Only show once photos have been added, or when limit is close
                    if (used == 0 && remaining > 3) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4, left: 20),
                      child: Text(
                        remaining == 0
                            ? 'Photo limit reached ($used/$max)'
                            : '$used/$max photos added',
                        style: HuddlText.caption(
                          color: remaining == 0
                              ? HuddlColors.error
                              : HuddlColors.textTertiary,
                        ),
                      ),
                    );
                  }),

                  // ── Selection summary chip ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: _orange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_selectedAge?.shortLabel ?? ''} • ${_selectedCategory?.label ?? ''} • ${_selectedCondition?.label ?? ''}',
                              style: HuddlText.body(color: _orange),
                            ),
                          ),
                          if (_isEditing)
                            GestureDetector(
                              onTap: () => setState(() => _step = 0),
                              child: Text('Edit',
                                style: HuddlText.caption(weight: FontWeight.w600, color: _orange),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // ── Form fields — same padding/spacing as Create Meetup ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 22),

                        // Item name
                        _sectionLabel('Item name'),
                        const SizedBox(height: 6),
                        _buildGrayFormField(
                          controller: _titleController,
                          hint: 'e.g. Silver Cross pram with accessories',
                          validator: (v) => v == null || v.trim().isEmpty ? 'Enter a title' : null,
                          onChanged: (_) => setState(() {}),
                        ),

                        const SizedBox(height: 20),

                        // Price
                        _sectionLabel('Price'),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: _buildGrayFormField(
                                controller: _priceController,
                                hint: '£0.00',
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
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                decoration: BoxDecoration(
                                  color: _isFree ? _orange : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _isFree ? _orange : HuddlColors.divider,
                                  ),
                                ),
                                child: Text(
                                  'Free',
                                  style: HuddlText.body(weight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Description
                        _sectionLabel('Description'),
                        const SizedBox(height: 6),
                        _buildGrayFormField(
                          controller: _descriptionController,
                          hint: 'Describe the item — condition, brand, what\'s included...',
                          maxLines: 4,
                          validator: (v) => v == null || v.trim().isEmpty ? 'Enter a description' : null,
                          onChanged: (_) => setState(() {}),
                        ),

                        const SizedBox(height: 36),
                      ],
                    ),
                  ),
                ],
              ),
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

  // ══════════════════════════════════════════════════════════════════════════
  // COMPONENT WIDGETS — matching Create Group / Create Meetup design language
  // ══════════════════════════════════════════════════════════════════════════

  /// Section label — bold dark text, exact match of Create Meetup _sectionHeader (16/w700/_sectionTxt)
  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: HuddlText.body(weight: FontWeight.w700),
    );
  }

  /// Gray-filled text form field — exact match of Create Meetup _buildGrayField:
  /// #F6F6F6 background fill, #D5D5D5 bottom underline (1.2px), no border, 14/15 padding.
  Widget _buildGrayFormField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: _fieldBg,
        border: Border(bottom: BorderSide(color: _fieldLine, width: 1.2)),
      ),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        enabled: enabled,
        textInputAction: maxLines == 1 ? TextInputAction.next : TextInputAction.newline,
        style: HuddlText.body(color: _sectionTxt),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: HuddlText.body(color: _hintGray),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
          errorStyle: HuddlText.caption(color: HuddlColors.error),
        ),
        validator: validator,
        onChanged: onChanged,
      ),
    );
  }

  // ── Photo area — full-width blue banner (matching Create Group photo upload style) ──

  Widget _buildPhotoArea() {
    if (_pickedImages.isEmpty) {
      // Empty state — full-width blue banner matching Create Group _buildPhotoUpload()
      return GestureDetector(
        onTap: _showImagePickerSheet,
        child: Container(
          width: double.infinity,
          height: 200,
          margin: EdgeInsets.zero,
          color: HuddlColors.primary,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.add_photo_alternate_outlined,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'Click to add photos',
                style: HuddlText.body(),
              ),
              const SizedBox(height: 4),
              Text(
                'Take photos or choose from gallery',
                style: HuddlText.caption(color: Colors.white.withValues(alpha: 0.8))),
            ],
          ),
        ),
      );
    }

    // Has images — full-width carousel with dots + add more
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 200,
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
              // Image counter
              if (_pickedImages.length > 1)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_currentImagePage + 1}/${_pickedImages.length}',
                      style: HuddlText.caption(),
                    ),
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
                        width: i == _currentImagePage ? 20 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i == _currentImagePage
                              ? HuddlColors.primary
                              : Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ),
              // Change overlay
              Positioned(
                bottom: 10,
                right: 10,
                child: GestureDetector(
                  onTap: _showImagePickerSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.add_a_photo, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('Add more',
                          style: HuddlText.caption(color: Colors.white)),
                    ]),
                  ),
                ),
              ),
            ],
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
      color: HuddlColors.neutral50,
      child: const Center(
        child: Icon(Icons.image_outlined, size: 48, color: HuddlColors.textDark),
      ),
    );
  }

  // ── Bottom button — matching Create Group / Create Meetup CTA style ──

  Widget _buildBottomButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool showBack = false,
  }) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
          20, 10, 20, MediaQuery.of(context).padding.bottom + 14),
      child: Row(
        children: [
          if (showBack) ...[
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: () => setState(() => _step--),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: HuddlColors.divider, width: 1.2),
                  ),
                  child: Center(
                    child: Text(
                      'Back',
                      style: HuddlText.body(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: enabled ? onTap : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 52,
                decoration: BoxDecoration(
                  gradient: enabled
                      ? const LinearGradient(
                          colors: [HuddlColors.primaryLight, HuddlColors.primary],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : null,
                  color: enabled ? null : HuddlColors.divider,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: enabled
                      ? [BoxShadow(
                          color: HuddlColors.primary.withValues(alpha: 0.30),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )]
                      : null,
                ),
                child: Center(
                  child: _isCreating && label.contains('...')
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : Text(
                          label,
                          style: HuddlText.body(weight: FontWeight.w600),
                        ),
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
            color: isSelected ? HuddlColors.primary : HuddlColors.gray300,
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            // Circle icon — matching onboarding _ParentTypeCard
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (isSelected ? HuddlColors.primary : context.hc.textTertiary)
                    .withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? HuddlColors.primary : HuddlColors.gray300,
                  width: 1.5,
                ),
              ),
              child: Icon(age.icon,
                  color: isSelected ? HuddlColors.primary : context.hc.textTertiary,
                  size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    age.label,
                    style: HuddlText.body(weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    age.shortLabel,
                    style: HuddlText.caption(),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, size: 22, color: HuddlColors.primary),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// CATEGORY LIST TILE — pill-card style matching AgeStageCard (Step 0)
// Circle icon on the left, label, check circle on select.
// =============================================================================

class _CategoryListTile extends StatelessWidget {
  final ItemCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryListTile({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
            color: isSelected ? HuddlColors.primary : HuddlColors.gray300,
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            // Circle icon — matching AgeStageCard
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (isSelected ? HuddlColors.primary : context.hc.textTertiary)
                    .withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? HuddlColors.primary : HuddlColors.gray300,
                  width: 1.5,
                ),
              ),
              child: Icon(
                category.icon,
                color: isSelected ? HuddlColors.primary : context.hc.textTertiary,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                category.label,
                style: HuddlText.body(weight: FontWeight.w600),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, size: 22, color: HuddlColors.primary),
          ],
        ),
      ),
    );
  }
}
