// ============================================================================
// HUDDL -- CREATE PARTNER LISTING SCREEN
// ============================================================================
//
// Full-featured listing creation form for Huddl Partner subscribers.
// Unlike the parent-added listing flow, Partner listings:
//   — Set isPartnerListing = true (priority placement)
//   — Set ownerUid to current user (enables reply to endorsements)
//   — Set verificationTier = HuddlVerified
//   — Accept a booking URL field
//   — Use AI Listing Writer if available
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/common/huddl_button.dart';

import '../../theme/huddl_colors.dart';
import '../../services/local_services_service.dart';
import '../../services/subscription_service.dart';

class CreatePartnerListingScreen extends StatefulWidget {
  const CreatePartnerListingScreen({super.key});

  @override
  State<CreatePartnerListingScreen> createState() =>
      _CreatePartnerListingScreenState();
}

class _CreatePartnerListingScreenState
    extends State<CreatePartnerListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _namCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _bookingCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();

  ServiceCategory _category = ServiceCategory.other;
  bool _submitting = false;

  final _categories = ServiceCategory.values
      .where((c) => c != ServiceCategory.other)
      .toList()
    ..add(ServiceCategory.other);

  @override
  void dispose() {
    _namCtrl.dispose();
    _taglineCtrl.dispose();
    _descCtrl.dispose();
    _phoneCtrl.dispose();
    _websiteCtrl.dispose();
    _bookingCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!SubscriptionService().isPartner) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Partner subscription required to create Partner listings.'),
      ));
      return;
    }

    setState(() => _submitting = true);

    final tags = _tagsCtrl.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final svc = LocalServicesService();
    

    final id = await svc.createListing(
      name: _namCtrl.text.trim(),
      tagline: _taglineCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      category: _category,
      tags: tags,
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      website:
          _websiteCtrl.text.trim().isEmpty ? null : _websiteCtrl.text.trim(),
      externalBookingUrl:
          _bookingCtrl.text.trim().isEmpty ? null : _bookingCtrl.text.trim(),
      isPartnerListing: true,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (id != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Listing created! It will appear in the directory shortly.'),
          backgroundColor: HuddlColors.success,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to create listing. Please try again.'),
        backgroundColor: HuddlColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F7F7),
        elevation: 0,
        leading: BackButton(color: HuddlColors.nearBlack),
        title: Text(
          'Create Partner Listing',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: HuddlColors.nearBlack,
          ),
        ),
        actions: [
          if (_submitting)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _submit,
              child: Text(
                'Publish',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.primary,
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Partner badge notice ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: HuddlColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: HuddlColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified,
                      color: HuddlColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Partner listings get priority placement and show a '
                      'verified badge in the directory.',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: HuddlColors.primary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Business name ─────────────────────────────────────────
            _Field(
              controller: _namCtrl,
              label: 'Business Name *',
              hint: 'e.g. Sandra at Clean2Perfection',
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 14),

            // ── Tagline ───────────────────────────────────────────────
            _Field(
              controller: _taglineCtrl,
              label: 'Tagline *',
              hint: 'e.g. Insured, reliable, family specialist',
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 14),

            // ── Category ──────────────────────────────────────────────
            _SectionLabel('Category *'),
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: HuddlColors.divider),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ServiceCategory>(
                  value: _category,
                  isExpanded: true,
                  items: _categories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(
                            c.displayName,
                            style: GoogleFonts.poppins(fontSize: 14),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _category = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Description ───────────────────────────────────────────
            _Field(
              controller: _descCtrl,
              label: 'Description *',
              hint:
                  'Tell parents about your service — qualifications, experience, availability...',
              maxLines: 4,
              validator: (v) =>
                  v == null || v.trim().length < 20
                      ? 'Please write at least 20 characters'
                      : null,
            ),
            const SizedBox(height: 14),

            // ── Tags ──────────────────────────────────────────────────
            _Field(
              controller: _tagsCtrl,
              label: 'Tags (comma-separated)',
              hint: 'e.g. insured, DBS checked, flexible hours',
            ),
            const SizedBox(height: 14),

            // ── Contact ───────────────────────────────────────────────
            _Field(
              controller: _phoneCtrl,
              label: 'Phone Number',
              hint: '07700 000000',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _websiteCtrl,
              label: 'Website',
              hint: 'https://yourbusiness.co.uk',
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 14),

            // ── Booking URL (Partner exclusive) ───────────────────────
            _Field(
              controller: _bookingCtrl,
              label: 'Booking / Appointment URL',
              hint: 'https://calendly.com/yourbusiness',
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 6),
            Text(
              'Parents will see a "Book Now" button linking to this URL.',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: HuddlColors.textTertiary,
              ),
            ),

            const SizedBox(height: 32),

            // ── Submit ────────────────────────────────────────────────
            HuddlButton(
              label: _submitting ? 'Publishing...' : 'Publish Listing',
              onPressed: _submitting ? null : _submit,
              isLoading: _submitting,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: HuddlColors.textTertiary,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
          style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.nearBlack),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(
                fontSize: 13, color: HuddlColors.textHint),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: HuddlColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: HuddlColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: HuddlColors.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: HuddlColors.error),
            ),
          ),
        ),
      ],
    );
  }
}
