import 'package:flutter/material.dart';
import '../../theme/huddl_icons.dart';
import '../../services/business_verification_service.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/common/underlined_text_field.dart';
import '../../widgets/common/huddl_button.dart';
import '../../constants/app_text_styles.dart';

// =============================================================================
// BUSINESS VERIFICATION SCREEN
//
// Post-subscription unlock flow for Partner subscribers.
// Step 0 → entity type selection
// Step 1 → details form (IndexedStack keyed on _entityType)
// Step 2 → success state with SVG celebration
// =============================================================================

class BusinessVerificationScreen extends StatefulWidget {
  const BusinessVerificationScreen({super.key});

  @override
  State<BusinessVerificationScreen> createState() =>
      _BusinessVerificationScreenState();
}

class _BusinessVerificationScreenState
    extends State<BusinessVerificationScreen> {
  final PageController _pageCtrl = PageController();
  int _step = 0; // 0=entity select, 1=details form, 2=success

  BusinessEntityType? _entityType;
  bool _isLoading = false;
  String? _errorMessage;
  String? _verifiedName;

  // Form controllers
  final _companyNameCtrl   = TextEditingController();
  final _companyNumberCtrl = TextEditingController();
  final _vatNumberCtrl     = TextEditingController();
  final _legalNameCtrl     = TextEditingController();
  final _tradingNameCtrl   = TextEditingController();
  final _utrCtrl           = TextEditingController();
  bool _declarationConfirmed = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _companyNameCtrl.dispose();
    _companyNumberCtrl.dispose();
    _vatNumberCtrl.dispose();
    _legalNameCtrl.dispose();
    _tradingNameCtrl.dispose();
    _utrCtrl.dispose();
    super.dispose();
  }

  // ── Verification actions ──────────────────────────────────────────────────

  Future<void> _verifyLtd() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    final result = await BusinessVerificationService().verifyLimitedCompany(
      companyNumber: _companyNumberCtrl.text,
      companyName: _companyNameCtrl.text,
    );
    if (!mounted) return;
    setState(() { _isLoading = false; });
    if (result.success) {
      setState(() => _verifiedName = result.verifiedName);
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      setState(() => _errorMessage = result.error);
    }
  }

  Future<void> _verifyVat() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    final result = await BusinessVerificationService()
        .verifyVatNumber(_vatNumberCtrl.text);
    if (!mounted) return;
    setState(() { _isLoading = false; });
    if (result.success) {
      setState(() => _verifiedName = result.verifiedName);
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      setState(() => _errorMessage = result.error);
    }
  }

  Future<void> _submitSoleTrader() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    final result = await BusinessVerificationService().submitSoleTraderDeclaration(
      legalName: _legalNameCtrl.text,
      tradingName: _tradingNameCtrl.text,
      utrNumber: _utrCtrl.text,
    );
    if (!mounted) return;
    setState(() { _isLoading = false; });
    if (result.success) {
      setState(() => _verifiedName = result.verifiedName);
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      setState(() => _errorMessage = result.error);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Scaffold(
      backgroundColor: hc.scaffold,
      appBar: AppBar(
        backgroundColor: hc.surface,
        elevation: 0,
        leading: _step == 0
            ? IconButton(
                icon: const Icon(HuddlIcons.close),
                onPressed: () => Navigator.pop(context),
              )
            : (_step < 2
                ? IconButton(
                    icon: const Icon(HuddlIcons.arrowBack),
                    onPressed: () {
                      _pageCtrl.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut);
                    },
                  )
                : const SizedBox.shrink()),
        title: Text(
          'Business verification',
          style: HuddlText.heading(),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (i) => setState(() => _step = i),
        itemCount: 3,
        itemBuilder: (context, index) {
          switch (index) {
            case 0:
              return _buildStep0(context);
            case 1:
              return _buildStep1(context);
            case 2:
              return _buildStep2(context);
            default:
              return const SizedBox.shrink();
          }
        },
      ),
    );
  }

  // ── Step 0 — Entity type selection ────────────────────────────────────────

  Widget _buildStep0(BuildContext context) {
    final hc = context.hc;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verify your business',
            style: HuddlText.display(),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose how your business is registered with HMRC',
            style: HuddlText.body(color: hc.textSecondary),
          ),
          const SizedBox(height: 28),
          _StageCard(
            icon: HuddlIcons.business,
            title: 'Limited company',
            subtitle: 'Verified instantly via Companies House',
            selected: _entityType == BusinessEntityType.limitedCompany,
            onTap: () => setState(
                () => _entityType = BusinessEntityType.limitedCompany),
          ),
          const SizedBox(height: 12),
          _StageCard(
            icon: HuddlIcons.receipt,
            title: 'VAT-registered business',
            subtitle: 'Verified instantly via HMRC',
            selected: _entityType == BusinessEntityType.vatRegistered,
            onTap: () => setState(
                () => _entityType = BusinessEntityType.vatRegistered),
          ),
          const SizedBox(height: 12),
          _StageCard(
            icon: HuddlIcons.user,
            title: 'Sole trader',
            subtitle: 'Self-declaration with UTR reference',
            selected: _entityType == BusinessEntityType.soleTrader,
            onTap: () =>
                setState(() => _entityType = BusinessEntityType.soleTrader),
          ),
          const SizedBox(height: 32),
          HuddlButton(
            label: 'Continue',
            onPressed: _entityType == null
                ? null
                : () => _pageCtrl.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
          ),
        ],
      ),
    );
  }

  // ── Step 1 — Details form ─────────────────────────────────────────────────

  Widget _buildStep1(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _entityType == BusinessEntityType.limitedCompany
                ? 'Limited company details'
                : _entityType == BusinessEntityType.vatRegistered
                    ? 'VAT registration details'
                    : 'Sole trader declaration',
            style: HuddlText.display(),
          ),
          const SizedBox(height: 24),
          // Entity-specific form via IndexedStack
          IndexedStack(
            index: _entityType == null
                ? 0
                : _entityType == BusinessEntityType.limitedCompany
                    ? 0
                    : _entityType == BusinessEntityType.vatRegistered
                        ? 1
                        : 2,
            children: [
              _buildLtdForm(context),
              _buildVatForm(context),
              _buildSoleTraderForm(context),
            ],
          ),
          // Error message
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: HuddlColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: HuddlColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(HuddlIcons.error,
                      size: 18, color: HuddlColors.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: HuddlText.body(color: HuddlColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          // Submit button — sole trader has separate button inside the form
          if (_entityType != BusinessEntityType.soleTrader)
            HuddlButton(
              label: 'Verify now',
              isLoading: _isLoading,
              onPressed: _isLoading
                  ? null
                  : () {
                      if (_entityType == BusinessEntityType.limitedCompany) {
                        _verifyLtd();
                      } else if (_entityType ==
                          BusinessEntityType.vatRegistered) {
                        _verifyVat();
                      }
                    },
            ),
        ],
      ),
    );
  }

  Widget _buildLtdForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UnderlinedTextField(
          label: 'Company name',
          controller: _companyNameCtrl,
        ),
        const SizedBox(height: 20),
        UnderlinedTextField(
          label: 'Companies House number',
          hintText: '8 digits, e.g. 12345678',
          controller: _companyNumberCtrl,
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }

  Widget _buildVatForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UnderlinedTextField(
          label: 'VAT number',
          hintText: 'e.g. GB123456789',
          controller: _vatNumberCtrl,
        ),
      ],
    );
  }

  Widget _buildSoleTraderForm(BuildContext context) {
    final hc = context.hc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UnderlinedTextField(
          label: 'Legal full name',
          controller: _legalNameCtrl,
        ),
        const SizedBox(height: 20),
        UnderlinedTextField(
          label: 'Trading name',
          controller: _tradingNameCtrl,
        ),
        const SizedBox(height: 20),
        UnderlinedTextField(
          label: 'UTR number',
          hintText: '10-digit HMRC reference',
          controller: _utrCtrl,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 20),
        // Statutory declaration card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: hc.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HuddlColors.divider),
          ),
          child: Text(
            'I confirm that I am registered as self-employed with HMRC, '
            'that the trading details I have provided are accurate, and that '
            'I accept full legal responsibility for all services and events '
            'I promote through Huddl. I understand that Huddl is a promotional '
            'platform only and accepts no liability for the services or events I list.',
            style: HuddlText.caption().copyWith(height: 1.5),
          ),
        ),
        CheckboxListTile(
          value: _declarationConfirmed,
          onChanged: (v) =>
              setState(() => _declarationConfirmed = v ?? false),
          title: Text(
            'I confirm the above declaration is true',
            style: HuddlText.body(),
          ),
          activeColor: HuddlColors.primary,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        HuddlButton(
          label: 'Submit declaration',
          isLoading: _isLoading,
          onPressed:
              (!_declarationConfirmed || _isLoading) ? null : _submitSoleTrader,
        ),
      ],
    );
  }

  // ── Step 2 — Success ──────────────────────────────────────────────────────

  Widget _buildStep2(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              HuddlIcons.verified,
              size: 80,
              color: HuddlColors.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Business verified',
              style: HuddlText.display(),
            ),
            const SizedBox(height: 8),
            if (_verifiedName != null)
              Text(
                _verifiedName!,
                style: HuddlText.body(weight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 8),
            Text(
              'Your HMRC-verified badge is now active on all your listings.',
              textAlign: TextAlign.center,
              style: HuddlText.body(),
            ),
            const SizedBox(height: 32),
            HuddlButton(
              label: 'Done',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// _StageCard — AnimatedContainer with orange border on select, BoxShadow
// (reproduced here, not imported from another file)
// =============================================================================

class _StageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _StageCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? HuddlColors.primary.withValues(alpha: 0.06)
              : hc.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? HuddlColors.primary
                : HuddlColors.divider,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: HuddlColors.primary.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? HuddlColors.primary.withValues(alpha: 0.12)
                    : hc.inputBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 22,
                color: selected ? HuddlColors.primary : hc.textSecondary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: HuddlText.body(weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: HuddlText.caption(),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(HuddlIcons.checkCircleFill,
                  color: HuddlColors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}
