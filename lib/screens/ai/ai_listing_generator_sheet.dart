import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/ai_listing_service.dart';
import '../../services/rehome_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AI LISTING GENERATOR — Bottom sheet for AI-powered listing creation
// Photo to listing in 15 seconds
// ═══════════════════════════════════════════════════════════════════════════════

class AiListingGeneratorSheet extends StatefulWidget {
  const AiListingGeneratorSheet({super.key});

  @override
  State<AiListingGeneratorSheet> createState() => _AiListingGeneratorSheetState();
}

class _AiListingGeneratorSheetState extends State<AiListingGeneratorSheet> {
  final AiListingService _aiService = AiListingService();
  final TextEditingController _hintController = TextEditingController();

  AiListingDraft? _draft;
  PriceComparison? _priceComparison;
  bool _isAnalysing = false;
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descController = TextEditingController();
    _priceController = TextEditingController();
  }

  @override
  void dispose() {
    _hintController.dispose();
    _titleController.dispose();
    _descController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _simulatePhotoAnalysis() async {
    final hint = _hintController.text.isNotEmpty
        ? _hintController.text
        : 'baby pushchair bugaboo';

    setState(() => _isAnalysing = true);

    try {
      final draft = await _aiService.analyseAndGenerate(
        photoDescription: hint,
        userHint: hint,
      );
      final comparison = _aiService.getPriceComparison(
        draft.suggestedCategory,
        draft.suggestedPrice,
      );

      if (mounted) {
        setState(() {
          _draft = draft;
          _priceComparison = comparison;
          _isAnalysing = false;
          _titleController.text = draft.suggestedTitle;
          _descController.text = draft.suggestedDescription;
          _priceController.text = draft.suggestedPrice.toStringAsFixed(0);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalysing = false);
      }
    }
  }

  void _publishListing() {
    if (_draft == null) return;
    _aiService.quickCreateListing(_draft!);
    Navigator.pop(context, true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Listed! "${_draft!.suggestedTitle}" is now live on Market',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        backgroundColor: HuddlColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.hc.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: context.hc.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: HuddlColors.aiGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.auto_awesome, color: context.hc.surface, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Smart Listing',
                            style: GoogleFonts.poppins(
                              fontSize: 20, fontWeight: FontWeight.w700,
                              color: context.hc.textPrimary,
                            ),
                          ),
                          Text(
                            'Photo to listing in 15 seconds',
                            style: GoogleFonts.poppins(
                              fontSize: 12, color: context.hc.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: context.hc.textTertiary),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.hc.divider),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (_draft == null) ...[
                      _buildUploadSection(),
                    ] else ...[
                      _buildDraftPreview(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUploadSection() {
    return Column(
      children: [
        // Photo upload area
        GestureDetector(
          onTap: () => _simulatePhotoAnalysis(),
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: HuddlColors.blueBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: HuddlColors.aiBlue.withValues(alpha: 0.3),
                width: 2,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
            ),
            child: _isAnalysing
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: HuddlColors.aiBlue),
                        const SizedBox(height: 16),
                        Text(
                          'Looking at your photo...',
                          style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w500,
                            color: HuddlColors.aiBlue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Identifying product, pricing, and category',
                          style: GoogleFonts.poppins(
                            fontSize: 12, color: context.hc.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: HuddlColors.aiBlue.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add_a_photo, size: 36, color: HuddlColors.aiBlue),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tap to take a photo',
                          style: GoogleFonts.poppins(
                            fontSize: 16, fontWeight: FontWeight.w600,
                            color: context.hc.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'We\'ll fill in the details for you',
                          style: GoogleFonts.poppins(
                            fontSize: 12, color: context.hc.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        // Hint text field
        Text(
          'Or describe what you\'re selling',
          style: GoogleFonts.poppins(
            fontSize: 13, fontWeight: FontWeight.w500,
            color: context.hc.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _hintController,
          style: GoogleFonts.poppins(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'e.g. "Bugaboo Fox 3 pushchair" or "baby clothes 0-3m"',
            hintStyle: GoogleFonts.poppins(fontSize: 13, color: context.hc.textTertiary),
            filled: true,
            fillColor: context.hc.scaffold,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              onPressed: _simulatePhotoAnalysis,
              icon: const Icon(Icons.auto_awesome, color: HuddlColors.aiBlue),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Quick items
        Text(
          'Popular items to list',
          style: GoogleFonts.poppins(
            fontSize: 13, fontWeight: FontWeight.w500,
            color: context.hc.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _quickItemChip('Bugaboo pushchair', Icons.child_friendly),
            _quickItemChip('Baby clothes bundle', Icons.checkroom),
            _quickItemChip('Stokke high chair', Icons.chair),
            _quickItemChip('Toys & games', Icons.extension),
            _quickItemChip('Car seat', Icons.directions_car),
            _quickItemChip('Books', Icons.auto_stories),
          ],
        ),
      ],
    );
  }

  Widget _quickItemChip(String label, IconData icon) {
    return GestureDetector(
      onTap: () {
        _hintController.text = label;
        _simulatePhotoAnalysis();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.hc.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: HuddlColors.aiBlue),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.poppins(
              fontSize: 12, color: context.hc.textPrimary,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftPreview() {
    if (_draft == null) return const SizedBox();
    final draft = _draft!;
    final comp = _priceComparison;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Confidence badge
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: HuddlColors.successBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, size: 18, color: HuddlColors.success),
                const SizedBox(width: 6),
                Text(
                  'Details filled in automatically',
                  style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: HuddlColors.success,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Safety warning
        if (draft.safetyNote != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HuddlColors.errorLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: HuddlColors.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(draft.safetyNote!,
                    style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.error)),
                ),
              ],
            ),
          ),

        // Title
        _buildEditableField('Title', _titleController, Icons.title),
        const SizedBox(height: 12),

        // Description
        _buildEditableField('Description', _descController, Icons.description, maxLines: 4),
        const SizedBox(height: 16),

        // Price section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.hc.scaffold,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Smart Pricing', style: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w600, color: context.hc.textPrimary,
              )),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Suggested price',
                          style: GoogleFonts.poppins(fontSize: 11, color: context.hc.textSecondary)),
                        Row(
                          children: [
                            Text(
                              '\u00A3${draft.suggestedPrice.toStringAsFixed(0)}',
                              style: GoogleFonts.poppins(
                                fontSize: 28, fontWeight: FontWeight.w700,
                                color: HuddlColors.success,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: HuddlColors.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${draft.savingsPercent}% off retail',
                                style: GoogleFonts.poppins(
                                  fontSize: 11, fontWeight: FontWeight.w600,
                                  color: HuddlColors.success,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Retail price',
                        style: GoogleFonts.poppins(fontSize: 10, color: context.hc.textTertiary)),
                      Text(
                        '\u00A3${draft.retailPrice.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w500,
                          color: context.hc.textTertiary,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (comp != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.hc.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        comp.priceVerdict == 'great_deal' ? Icons.thumb_up : Icons.info_outline,
                        size: 16,
                        color: comp.priceVerdict == 'great_deal'
                            ? HuddlColors.success
                            : HuddlColors.teal,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          comp.priceVerdict == 'great_deal'
                              ? 'Great deal! Below average for ${draft.suggestedCategory.label}'
                              : comp.priceVerdict == 'above_avg'
                                  ? 'Slightly above average. Consider lowering for faster sale.'
                                  : 'Fair price for ${draft.suggestedCategory.label} in your area',
                          style: GoogleFonts.poppins(fontSize: 11, color: context.hc.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Category & Condition
        Row(
          children: [
            Expanded(child: _buildInfoChip('Category', draft.suggestedCategory.label, draft.suggestedCategory.icon)),
            const SizedBox(width: 8),
            Expanded(child: _buildInfoChip('Age Stage', draft.suggestedAgeStage.shortLabel, draft.suggestedAgeStage.icon)),
            const SizedBox(width: 8),
            Expanded(child: _buildInfoChip('Condition', draft.suggestedCondition.label, Icons.verified)),
          ],
        ),
        const SizedBox(height: 16),

        // Tags
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: draft.tags.map((tag) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: context.hc.scaffold,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('#$tag', style: GoogleFonts.poppins(
              fontSize: 11, color: context.hc.textSecondary,
            )),
          )).toList(),
        ),
        const SizedBox(height: 24),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _draft = null;
                    _priceComparison = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.hc.divider),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text('Start Over', style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: context.hc.textSecondary,
                    )),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: _publishListing,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: HuddlColors.aiGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.publish, color: context.hc.surface, size: 20),
                        const SizedBox(width: 8),
                        Text('Publish Listing', style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w600,
                          color: context.hc.surface,
                        )),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildEditableField(String label, TextEditingController controller, IconData icon, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(
          fontSize: 12, fontWeight: FontWeight.w500, color: context.hc.textSecondary,
        )),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: HuddlColors.aiBlue),
            filled: true,
            fillColor: context.hc.scaffold,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.hc.scaffold,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: HuddlColors.aiBlue),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.poppins(
            fontSize: 10, fontWeight: FontWeight.w600, color: context.hc.textPrimary,
          ), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
          Text(label, style: GoogleFonts.poppins(
            fontSize: 9, color: context.hc.textTertiary,
          )),
        ],
      ),
    );
  }
}
