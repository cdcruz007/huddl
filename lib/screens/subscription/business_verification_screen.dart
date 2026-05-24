// ============================================================================
// HUDDL -- BUSINESS VERIFICATION SCREEN
// ============================================================================
//
// Three-step PageView flow:
//   Step 0 — Choose verification method (VAT / Companies House / Sole Trader)
//   Step 1 — Enter details and verify
//   Step 2 — Success confirmation
//
// On success, calls SubscriptionService.setBusinessVerified(verified: true)
// and pops back to the caller (profile or onboarding).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/business_verification_service.dart';
import '../../services/subscription_service.dart';

class BusinessVerificationScreen extends StatefulWidget {
  const BusinessVerificationScreen({super.key});

  @override
  State<BusinessVerificationScreen> createState() =>
      _BusinessVerificationScreenState();
}

class _BusinessVerificationScreenState
    extends State<BusinessVerificationScreen> {
  final PageController _pageCtrl = PageController();

  BusinessVerificationMethod? _selectedMethod;
  VerificationResult? _result;
  bool _loading = false;
  bool _agreedToTCs = false;

  final _vatCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _utrCtrl = TextEditingController();
  final _tradingNameCtrl = TextEditingController();

  @override
  void dispose() {
    _pageCtrl.dispose();
    _vatCtrl.dispose();
    _companyCtrl.dispose();
    _utrCtrl.dispose();
    _tradingNameCtrl.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    _pageCtrl.animateToPage(
      step,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _verify() async {
    if (_selectedMethod == null) return;
    setState(() => _loading = true);

    final svc = BusinessVerificationService.instance;
    VerificationResult result;

    switch (_selectedMethod!) {
      case BusinessVerificationMethod.vat:
        result = await svc.verifyVatNumber(_vatCtrl.text);
        break;
      case BusinessVerificationMethod.companies:
        result = await svc.verifyCompanyNumber(_companyCtrl.text);
        break;
      case BusinessVerificationMethod.soleTrader:
        result = svc.declareSoleTrader(
          utr: _utrCtrl.text,
          tradingName: _tradingNameCtrl.text,
          agreedToTCs: _agreedToTCs,
        );
        break;
    }

    setState(() {
      _loading = false;
      _result = result;
    });

    if (result.success) {
      await SubscriptionService().setBusinessVerified(verified: true);
      _goToStep(2);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Verification failed.'),
            backgroundColor: HuddlColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.background,
        elevation: 0,
        leading: BackButton(color: HuddlColors.nearBlack),
        title: Text(
          'Business Verification',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: HuddlColors.nearBlack,
          ),
        ),
      ),
      body: PageView(
        controller: _pageCtrl,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _StepChooseMethod(),
          _StepEnterDetails(),
          _StepSuccess(),
        ],
      ),
    );
  }

  // ── Step 0: Choose method ─────────────────────────────────────────────────

  Widget _StepChooseMethod() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How would you like to verify your business?',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: HuddlColors.nearBlack,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Verification is required to activate your Huddl Partner profile. '
            'Your information is kept secure and only used for verification.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: HuddlColors.textTertiary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          _MethodCard(
            icon: Icons.receipt_long_outlined,
            title: 'VAT Registration',
            subtitle: 'Verify using your HMRC VAT number (GB + 9 digits)',
            selected: _selectedMethod == BusinessVerificationMethod.vat,
            onTap: () => setState(
                () => _selectedMethod = BusinessVerificationMethod.vat),
          ),
          const SizedBox(height: 12),
          _MethodCard(
            icon: Icons.business_outlined,
            title: 'Companies House',
            subtitle:
                'Verify using your registered company number (8 characters)',
            selected:
                _selectedMethod == BusinessVerificationMethod.companies,
            onTap: () => setState(
                () => _selectedMethod = BusinessVerificationMethod.companies),
          ),
          const SizedBox(height: 12),
          _MethodCard(
            icon: Icons.person_outline,
            title: 'Sole Trader / Freelancer',
            subtitle: 'Declare your UTR number — subject to admin review',
            selected:
                _selectedMethod == BusinessVerificationMethod.soleTrader,
            onTap: () => setState(
                () => _selectedMethod = BusinessVerificationMethod.soleTrader),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: HuddlColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed:
                  _selectedMethod != null ? () => _goToStep(1) : null,
              child: Text(
                'Continue',
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

  // ── Step 1: Enter details ─────────────────────────────────────────────────

  Widget _StepEnterDetails() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _stepTitle(),
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: HuddlColors.nearBlack,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _stepSubtitle(),
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: HuddlColors.textTertiary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          if (_selectedMethod == BusinessVerificationMethod.vat) ...[
            _InputField(
              controller: _vatCtrl,
              label: 'VAT Number',
              hint: 'GB123456789',
              keyboardType: TextInputType.number,
            ),
          ] else if (_selectedMethod ==
              BusinessVerificationMethod.companies) ...[
            _InputField(
              controller: _companyCtrl,
              label: 'Company Number',
              hint: '12345678',
              keyboardType: TextInputType.text,
            ),
          ] else if (_selectedMethod ==
              BusinessVerificationMethod.soleTrader) ...[
            _InputField(
              controller: _tradingNameCtrl,
              label: 'Trading Name / Business Name',
              hint: 'e.g. Jane Smith Childcare',
            ),
            const SizedBox(height: 16),
            _InputField(
              controller: _utrCtrl,
              label: 'Unique Taxpayer Reference (UTR)',
              hint: '1234567890',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () =>
                  setState(() => _agreedToTCs = !_agreedToTCs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _agreedToTCs
                          ? HuddlColors.primary
                          : Colors.transparent,
                      border: Border.all(
                        color: _agreedToTCs
                            ? HuddlColors.primary
                            : HuddlColors.divider,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: _agreedToTCs
                        ? const Icon(Icons.check,
                            size: 14, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'I confirm I am self-employed, registered with HMRC, '
                      'and the UTR I have provided is correct. I agree to '
                      'the Huddl Partner Terms & Conditions.',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: HuddlColors.textDark,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: HuddlColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _loading ? null : _verify,
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Verify Now',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _goToStep(0),
            child: Text(
              'Change verification method',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: HuddlColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Success ───────────────────────────────────────────────────────

  Widget _StepSuccess() {
    final isPending = _result?.pendingReview ?? false;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: HuddlColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPending ? Icons.hourglass_top_outlined : Icons.verified,
              size: 40,
              color: isPending ? HuddlColors.accentAmber : HuddlColors.success,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            isPending ? 'Declaration Submitted' : 'Business Verified!',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: HuddlColors.nearBlack,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          if (_result?.businessName != null)
            Text(
              _result!.businessName!,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: HuddlColors.primary,
              ),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 12),
          Text(
            isPending
                ? 'Your sole trader declaration is under review. '
                    'Your Partner profile will be activated within 24 hours '
                    'once our team has verified your details.'
                : 'Your business has been verified. Your Huddl Partner profile '
                    'is now active — you can start creating listings, viewing '
                    'analytics, and promoting your business in the community.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: HuddlColors.textTertiary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: HuddlColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Done',
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _stepTitle() {
    switch (_selectedMethod) {
      case BusinessVerificationMethod.vat:
        return 'Enter your VAT number';
      case BusinessVerificationMethod.companies:
        return 'Enter your Companies House number';
      case BusinessVerificationMethod.soleTrader:
        return 'Sole trader declaration';
      default:
        return 'Enter your details';
    }
  }

  String _stepSubtitle() {
    switch (_selectedMethod) {
      case BusinessVerificationMethod.vat:
        return 'Your 9-digit VAT number is on your VAT registration certificate '
            '(form VAT4) or your HMRC online account.';
      case BusinessVerificationMethod.companies:
        return 'Your 8-character company number is shown on your Certificate of '
            'Incorporation and on the Companies House register.';
      case BusinessVerificationMethod.soleTrader:
        return 'Your 10-digit UTR is on any Self Assessment correspondence from '
            'HMRC, or in your HMRC online account.';
      default:
        return '';
    }
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _MethodCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? HuddlColors.primary.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? HuddlColors.primary : HuddlColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? HuddlColors.primary.withValues(alpha: 0.12)
                    : HuddlColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: selected ? HuddlColors.primary : HuddlColors.textTertiary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? HuddlColors.primary
                          : HuddlColors.nearBlack,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: HuddlColors.textTertiary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: HuddlColors.primary, size: 22),
          ],
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType keyboardType;

  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: HuddlColors.textTertiary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.poppins(
            fontSize: 15,
            color: HuddlColors.nearBlack,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(
              fontSize: 15,
              color: HuddlColors.textHint,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              borderSide:
                  BorderSide(color: HuddlColors.primary, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
