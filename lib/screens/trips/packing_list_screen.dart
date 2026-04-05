import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/travel_service.dart';
import '../main_shell.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PACK MY BAG — AI-generated personalised packing list
// ═══════════════════════════════════════════════════════════════════════════════

class PackingListScreen extends StatefulWidget {
  final TravelDestination destination;
  const PackingListScreen({super.key, required this.destination});

  @override
  State<PackingListScreen> createState() => _PackingListScreenState();
}

class _PackingListScreenState extends State<PackingListScreen> {
  final TravelService _travelService = TravelService();
  late List<PackingItem> _items;
  int _tripDays = 7;
  bool _isGenerating = true;

  @override
  void initState() {
    super.initState();
    _generateList();
  }

  void _generateList() {
    setState(() => _isGenerating = true);
    Future.delayed(const Duration(milliseconds: 500), () {
      _items = _travelService.generatePackingList(
        widget.destination.id, _tripDays, [14, 36], // Simulated child ages: 14 months, 3 years
      );
      if (mounted) setState(() => _isGenerating = false);
    });
  }

  Map<String, List<PackingItem>> get _groupedItems {
    final grouped = <String, List<PackingItem>>{};
    for (final item in _items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }
    return grouped;
  }

  int get _packedCount => _items.where((i) => i.isPacked).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.white,
      appBar: AppBar(
        backgroundColor: HuddlColors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 20), onPressed: () => Navigator.pop(context)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pack My Bag', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            Text(widget.destination.name, style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: HuddlColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_awesome, size: 14, color: HuddlColors.primary),
              const SizedBox(width: 4),
              Text('AI Generated', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
            ]),
          ),
        ],
      ),
      body: _isGenerating
          ? Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const CircularProgressIndicator(color: HuddlColors.primary),
                const SizedBox(height: 16),
                Text('Generating your personalised packing list...', style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textSecondary)),
                const SizedBox(height: 4),
                Text('Based on ${widget.destination.name}, $_tripDays days, 2 children', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textHint)),
              ]),
            )
          : Column(
              children: [
                // ── Trip duration selector ──────────────────────
                _buildDurationSelector(),
                // ── Progress bar ────────────────────────────────
                _buildProgressBar(),
                // ── Marketplace callout ─────────────────────────
                _buildMarketplaceCallout(),
                // ── Packing list ────────────────────────────────
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: _groupedItems.entries.map((entry) => _buildCategory(entry.key, entry.value)).toList()
                      ..add(const SizedBox(height: 80)),
                  ),
                ),
              ],
            ),
    );
  }

  // ── Duration selector ───────────────────────────────────────────────────

  Widget _buildDurationSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          Text('Trip duration:', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: HuddlColors.textDark)),
          const SizedBox(width: 12),
          ...([3, 5, 7, 10, 14].map((d) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () { _tripDays = d; _generateList(); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  gradient: _tripDays == d ? HuddlColors.primaryGradient : null,
                  color: _tripDays == d ? null : HuddlColors.background,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text('${d}d', style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w500,
                  color: _tripDays == d ? HuddlColors.white : HuddlColors.textSecondary,
                )),
              ),
            ),
          ))),
        ],
      ),
    );
  }

  // ── Progress bar ────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    final total = _items.length;
    final packed = _packedCount;
    final progress = total > 0 ? packed / total : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        children: [
          Row(children: [
            Text('$packed / $total items packed', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: HuddlColors.textDark)),
            const Spacer(),
            Text('${(progress * 100).round()}%', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: HuddlColors.background,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress == 1.0 ? HuddlColors.successGreen : HuddlColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Marketplace callout ─────────────────────────────────────────────────

  Widget _buildMarketplaceCallout() {
    return GestureDetector(
      onTap: () {
        // Navigate back to home and switch to Preloved tab (index 3)
        Navigator.popUntil(context, (route) => route.isFirst);
        MainShell.shellKey.currentState?.switchTab(3);
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HuddlColors.teal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HuddlColors.teal.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.storefront, color: HuddlColors.teal, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('3 parents in your area are lending travel cots', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.teal)),
            Text('Browse the Preloved marketplace for travel gear', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary)),
          ])),
          Icon(Icons.arrow_forward_ios, size: 14, color: HuddlColors.teal),
        ],
      ),
    ),
    );
  }

  // ── Category group ──────────────────────────────────────────────────────

  Widget _buildCategory(String category, List<PackingItem> items) {
    final icon = _categoryIcon(category);
    final color = _categoryColor(category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Text(category, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
          const Spacer(),
          Text('${items.where((i) => i.isPacked).length}/${items.length}', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textHint)),
        ]),
        const SizedBox(height: 6),
        ...items.map((item) => _buildPackingItem(item)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildPackingItem(PackingItem item) {
    return GestureDetector(
      onTap: () => setState(() => item.isPacked = !item.isPacked),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: item.isPacked ? HuddlColors.successBg : HuddlColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: item.isPacked ? HuddlColors.teal.withValues(alpha: 0.3) : HuddlColors.divider),
        ),
        child: Row(
          children: [
            Icon(
              item.isPacked ? Icons.check_circle : (item.essential ? Icons.radio_button_unchecked : Icons.circle_outlined),
              size: 20,
              color: item.isPacked ? HuddlColors.teal : (item.essential ? HuddlColors.primary : HuddlColors.textHint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${item.item}${item.quantity > 1 ? ' x${item.quantity}' : ''}',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: item.essential ? FontWeight.w500 : FontWeight.w400,
                    color: item.isPacked ? HuddlColors.textHint : HuddlColors.textDark,
                    decoration: item.isPacked ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (item.note.isNotEmpty)
                  Text(item.note, style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint, fontStyle: FontStyle.italic)),
              ]),
            ),
            if (item.essential && !item.isPacked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: HuddlColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text('Essential', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
              ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Essentials': return Icons.star;
      case 'Medicine': return Icons.medical_services;
      case 'Sun & Beach': return Icons.wb_sunny;
      case 'Clothing': return Icons.checkroom;
      case 'Travel Gear': return Icons.luggage;
      case 'Food & Feeding': return Icons.restaurant;
      case 'Entertainment': return Icons.toys;
      case 'Documents': return Icons.article;
      default: return Icons.check_box;
    }
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Essentials': return HuddlColors.primary;
      case 'Medicine': return HuddlColors.error;
      case 'Sun & Beach': return HuddlColors.accentAmber;
      case 'Clothing': return HuddlColors.blue;
      case 'Travel Gear': return HuddlColors.teal;
      case 'Food & Feeding': return HuddlColors.successGreen;
      case 'Entertainment': return HuddlColors.accentCoral;
      case 'Documents': return HuddlColors.gray600;
      default: return HuddlColors.primary;
    }
  }
}
