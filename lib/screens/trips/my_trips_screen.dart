import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/travel_community_service.dart';
import '../../services/travel_service.dart';
import '../../services/subscription_service.dart';
import 'ask_parents_screen.dart';
import 'travel_concierge_screen.dart';
import 'community_tips_screen.dart';

// =============================================================================
// MY TRIPS — Personal travel planner
// =============================================================================

class UserTrip {
  final String id;
  final String destination;
  final String? destinationId;
  final String? imageUrl;
  final DateTime? departureDate;
  final DateTime? returnDate;
  final List<String> childAges;
  final List<TripChecklist> checklists;
  final List<SavedAnswer> savedResearch;
  final String? notes;
  bool isActive;

  UserTrip({
    required this.id,
    required this.destination,
    this.destinationId,
    this.imageUrl,
    this.departureDate,
    this.returnDate,
    List<String>? childAges,
    List<TripChecklist>? checklists,
    List<SavedAnswer>? savedResearch,
    this.notes,
    this.isActive = true,
  })  : childAges = childAges ?? [],
        checklists = checklists ?? [],
        savedResearch = savedResearch ?? [];

  int get daysUntil => departureDate == null ? -1 : departureDate!.difference(DateTime.now()).inDays;

  String get dateRange {
    if (departureDate == null) return 'Dates not set';
    final dep = '${departureDate!.day}/${departureDate!.month}';
    if (returnDate == null) return dep;
    return '$dep - ${returnDate!.day}/${returnDate!.month}';
  }

  int get completedItems {
    int c = 0;
    for (final cl in checklists) { c += cl.items.where((i) => i.isChecked).length; }
    return c;
  }

  int get totalItems {
    int c = 0;
    for (final cl in checklists) { c += cl.items.length; }
    return c;
  }

  double get progress => totalItems == 0 ? 0 : completedItems / totalItems;
}

class TripChecklist {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final List<ChecklistItem> items;
  bool isExpanded;

  TripChecklist({
    required this.id, required this.title, required this.icon, required this.color,
    List<ChecklistItem>? items, this.isExpanded = false,
  }) : items = items ?? [];
}

class ChecklistItem {
  final String id;
  final String label;
  final String? detail;
  final bool isAiGenerated;
  bool isChecked;

  ChecklistItem({
    required this.id, required this.label, this.detail,
    this.isAiGenerated = false, this.isChecked = false,
  });
}

// ── Emoji + color maps for destinations (fallback for broken images) ──
const _destEmojis = {'Tenerife': '🌴', 'Mallorca': '🏖️', 'Algarve': '🌊', 'Costa del Sol': '☀️', 'Lake Garda': '⛵', 'Cornwall': '🏄', 'Cotswolds': '🌿', 'Crete': '🏛️'};
const _destColors = {'Tenerife': Color(0xFFFF975C), 'Mallorca': Color(0xFF3580F0), 'Algarve': Color(0xFF199A85), 'Costa del Sol': Color(0xFFF3C54F), 'Lake Garda': Color(0xFF5B9DFF), 'Cornwall': Color(0xFF22C55E), 'Cotswolds': Color(0xFF78B0FF), 'Crete': Color(0xFFF69F72)};

class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  final TravelCommunityService _commSvc = TravelCommunityService();
  final TravelService _travelSvc = TravelService();
  final SubscriptionService _subSvc = SubscriptionService();
  bool _loading = true;
  final List<UserTrip> _trips = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    await _travelSvc.initialize();
    await _commSvc.initialize();
    await _subSvc.initialize();
    _loadSample();
    if (mounted) setState(() => _loading = false);
  }

  void _loadSample() {
    final dests = _travelSvc.destinations;
    final ten = dests.firstWhere((d) => d.name == 'Tenerife', orElse: () => dests.first);
    final mal = dests.length > 1 ? dests.firstWhere((d) => d.name == 'Mallorca', orElse: () => dests[1]) : dests.first;

    _trips.addAll([
      UserTrip(
        id: 'trip_1', destination: 'Tenerife', destinationId: ten.id, imageUrl: ten.imageUrl,
        departureDate: DateTime.now().add(const Duration(days: 23)),
        returnDate: DateTime.now().add(const Duration(days: 30)),
        childAges: ['14 months'], isActive: true,
        savedResearch: _commSvc.savedAnswers.take(2).toList(),
        checklists: [
          TripChecklist(id: 'cl_docs', title: 'Documents & Essentials', icon: Icons.description, color: HuddlColors.error, items: [
            ChecklistItem(id: 'ci_1', label: 'Passports (yours + baby)', detail: 'Check expiry dates — must be valid 6 months beyond travel', isChecked: true),
            ChecklistItem(id: 'ci_2', label: 'Travel insurance', detail: 'Community tip: Staysure or AllClear cover pre-existing conditions', isAiGenerated: true),
            ChecklistItem(id: 'ci_3', label: 'EHIC/GHIC health card', detail: 'Free from NHS — covers EU medical treatment'),
            ChecklistItem(id: 'ci_4', label: 'Printed booking confirmations', isChecked: true),
            ChecklistItem(id: 'ci_5', label: 'Baby\'s birth certificate (if name differs from passport)'),
          ]),
          TripChecklist(id: 'cl_flight', title: 'Flight Prep', icon: Icons.flight, color: HuddlColors.blue, items: [
            ChecklistItem(id: 'ci_6', label: 'Request bassinet seat', detail: 'Parent tip: BA & easyJet offer bassinets for under-1s', isAiGenerated: true),
            ChecklistItem(id: 'ci_7', label: 'Gate-check pushchair', detail: 'Wear sling through security, gate-check the buggy'),
            ChecklistItem(id: 'ci_8', label: 'Calpol sachets in hand luggage', detail: 'Under 100ml — security-friendly'),
            ChecklistItem(id: 'ci_9', label: 'New small toy for distraction', detail: 'Something they haven\'t seen before buys 30 mins', isAiGenerated: true),
            ChecklistItem(id: 'ci_10', label: 'Feed on takeoff/landing', detail: 'Helps equalise ear pressure'),
            ChecklistItem(id: 'ci_11', label: 'Spare clothes for baby AND you', isAiGenerated: true),
          ]),
          TripChecklist(id: 'cl_baby', title: 'Baby Gear', icon: Icons.child_care, color: HuddlColors.teal, items: [
            ChecklistItem(id: 'ci_12', label: 'Lightweight travel pushchair', detail: 'BabyZen YoYo or Silver Cross Jet'),
            ChecklistItem(id: 'ci_13', label: 'Baby sling/carrier', detail: 'Essential for cobblestones and beach access', isAiGenerated: true),
            ChecklistItem(id: 'ci_14', label: 'Portable blackout blind', detail: 'Gro Anywhere Blind — game changer'),
            ChecklistItem(id: 'ci_15', label: 'Sun tent / beach shade', detail: 'Tenerife sun is strong — SPF50 shade essential'),
            ChecklistItem(id: 'ci_16', label: 'Travel cot (or check hotel provides)', detail: 'Most Spanish hotels provide free cots — call ahead', isAiGenerated: true),
          ]),
          TripChecklist(id: 'cl_health', title: 'Health & Safety', icon: Icons.medical_services, color: HuddlColors.primary, items: [
            ChecklistItem(id: 'ci_17', label: 'Baby sunscreen SPF50+', detail: 'Soltan Kids or LaRoche-Posay recommended'),
            ChecklistItem(id: 'ci_18', label: 'Calpol / Nurofen'),
            ChecklistItem(id: 'ci_19', label: 'Teething gel', detail: '14 months is prime teething age', isAiGenerated: true),
            ChecklistItem(id: 'ci_20', label: 'Rehydration sachets', detail: 'Dioralyte — essential for tummy bugs'),
            ChecklistItem(id: 'ci_21', label: 'Plasters & antiseptic wipes'),
            ChecklistItem(id: 'ci_22', label: 'Mosquito repellent (DEET-free)', detail: 'Incognito or Citronella-based'),
          ]),
        ],
      ),
      UserTrip(
        id: 'trip_2', destination: 'Mallorca', destinationId: mal.id, imageUrl: mal.imageUrl,
        departureDate: DateTime.now().add(const Duration(days: 67)),
        returnDate: DateTime.now().add(const Duration(days: 74)),
        childAges: ['14 months'], isActive: true,
        checklists: [
          TripChecklist(id: 'cl_docs2', title: 'Documents', icon: Icons.description, color: HuddlColors.error, items: [
            ChecklistItem(id: 'ci_30', label: 'Passports'),
            ChecklistItem(id: 'ci_31', label: 'Travel insurance'),
            ChecklistItem(id: 'ci_32', label: 'Hotel confirmation'),
          ]),
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white, elevation: 0, scrolledUnderElevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 20), onPressed: () => Navigator.pop(context)),
        title: Text('My Trips', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
        actions: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TravelConciergeScreen())),
            child: Container(
              width: 36, height: 36, margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(gradient: HuddlColors.aiGradient, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 18),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: HuddlColors.primary))
          : _trips.isEmpty ? _empty() : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ..._trips.where((t) => t.isActive).map((t) => _tripCard(t)),
                if (_commSvc.savedAnswers.isNotEmpty) ...[const SizedBox(height: 20), _savedResearch()],
                const SizedBox(height: 20), _aiCta(),
                const SizedBox(height: 100),
              ]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createSheet(),
        backgroundColor: HuddlColors.primary,
        icon: const Icon(Icons.add, color: HuddlColors.white, size: 20),
        label: Text('New Trip', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.white)),
      ),
    );
  }

  Widget _empty() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(color: HuddlColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
        child: const Icon(Icons.flight_takeoff, size: 40, color: HuddlColors.primary),
      ),
      const SizedBox(height: 16),
      Text('No trips planned yet', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
      const SizedBox(height: 8),
      Text('Create your first trip to get AI-powered\nchecklists and community tips!', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary, height: 1.4)),
      const SizedBox(height: 24),
      ElevatedButton(
        onPressed: () => _createSheet(),
        style: ElevatedButton.styleFrom(backgroundColor: HuddlColors.primary, foregroundColor: HuddlColors.white, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: Text('Plan a Trip', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    ]));
  }

  // ── Trip card — uses gradient + emoji fallback instead of broken images ──
  Widget _tripCard(UserTrip trip) {
    final emoji = _destEmojis[trip.destination] ?? '✈️';
    final fallbackColor = _destColors[trip.destination] ?? HuddlColors.primary;

    return GestureDetector(
      onTap: () => _openDetail(trip),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: HuddlColors.white, borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image header with robust fallback
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: SizedBox(
              height: 120, width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                // Gradient background (always visible as fallback)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [fallbackColor.withValues(alpha: 0.3), fallbackColor.withValues(alpha: 0.08)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(child: Text(emoji, style: const TextStyle(fontSize: 48))),
                ),
                // Gradient overlay for text readability
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
                    ),
                  ),
                ),
                // Countdown badge
                if (trip.daysUntil > 0)
                  Positioned(top: 12, right: 12, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.circular(10)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.access_time, size: 13, color: HuddlColors.primary),
                      const SizedBox(width: 4),
                      Text('${trip.daysUntil} days', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
                    ]),
                  )),
                // Name overlay
                Positioned(bottom: 12, left: 14, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(trip.destination, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: HuddlColors.white)),
                  Text(trip.dateRange, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.white.withValues(alpha: 0.9))),
                ])),
              ]),
            ),
          ),
          // Progress
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Trip Prep', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                    const Spacer(),
                    Text('${trip.completedItems}/${trip.totalItems} items', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: trip.progress, backgroundColor: HuddlColors.gray200, minHeight: 6,
                      valueColor: AlwaysStoppedAnimation<Color>(trip.progress >= 1 ? HuddlColors.successGreen : HuddlColors.primary),
                    ),
                  ),
                ])),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _infoChip(Icons.child_care, trip.childAges.isNotEmpty ? trip.childAges.first : 'No ages', HuddlColors.teal),
                const SizedBox(width: 8),
                _infoChip(Icons.checklist, '${trip.checklists.length} lists', HuddlColors.blue),
                if (trip.savedResearch.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _infoChip(Icons.bookmark, '${trip.savedResearch.length} saved', HuddlColors.primary),
                ],
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
      ]),
    );
  }

  Widget _savedResearch() {
    final saved = _commSvc.savedAnswers;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.bookmark, size: 20, color: HuddlColors.primary),
        const SizedBox(width: 8),
        Text('Saved Research', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
        const Spacer(),
        Text('${saved.length} items', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textHint)),
      ]),
      const SizedBox(height: 10),
      ...saved.map((s) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.bookmark, size: 14, color: HuddlColors.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(s.questionText, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.textDark), maxLines: 1, overflow: TextOverflow.ellipsis)),
            GestureDetector(onTap: () { _commSvc.removeSavedAnswer(s.answerId); setState(() {}); }, child: const Icon(Icons.close, size: 16, color: HuddlColors.textHint)),
          ]),
          const SizedBox(height: 4),
          Text(s.answerText, style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: HuddlColors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(s.destination, style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w500, color: HuddlColors.blue)),
            ),
            const SizedBox(width: 6),
            Text('by ${s.authorName}', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint)),
          ]),
        ]),
      )),
    ]);
  }

  Widget _aiCta() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TravelConciergeScreen())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFEDF4FF), Color(0xFFF5F9FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(gradient: HuddlColors.aiGradient, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Need help planning?', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            Text('Ask the AI Concierge about your trips', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary)),
          ])),
          const Icon(Icons.arrow_forward_ios, size: 14, color: HuddlColors.aiBlue),
        ]),
      ),
    );
  }

  void _openDetail(UserTrip trip) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _TripDetailScreen(trip: trip, commSvc: _commSvc)));
  }

  void _createSheet() {
    final destCtrl = TextEditingController();
    final ageCtrl = TextEditingController();
    DateTime? dep;
    DateTime? ret;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: HuddlColors.gray300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text('Plan a New Trip', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: HuddlColors.textDark)),
              Text('AI will generate checklists from community data', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
              const SizedBox(height: 20),
              Text('Where are you going?', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(14)),
                child: TextField(controller: destCtrl, style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(hintText: 'e.g. Tenerife, Mallorca...', hintStyle: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textHint), prefixIcon: const Icon(Icons.place, color: HuddlColors.textHint, size: 20), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 14))),
              ),
              const SizedBox(height: 14),
              Text('Child age(s)', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(14)),
                child: TextField(controller: ageCtrl, style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(hintText: 'e.g. 14 months, 3 years', hintStyle: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textHint), prefixIcon: const Icon(Icons.child_care, color: HuddlColors.textHint, size: 20), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 14))),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _datePicker('Departure', dep, () async {
                  final p = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 7)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (p != null) ss(() => dep = p);
                })),
                const SizedBox(width: 12),
                Expanded(child: _datePicker('Return', ret, () async {
                  final p = await showDatePicker(context: context, initialDate: dep?.add(const Duration(days: 7)) ?? DateTime.now().add(const Duration(days: 14)), firstDate: dep ?? DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 400)));
                  if (p != null) ss(() => ret = p);
                })),
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: HuddlColors.aiBlue.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.auto_awesome, size: 18, color: HuddlColors.aiBlue),
                  const SizedBox(width: 10),
                  Expanded(child: Text('AI will auto-generate checklists and packing lists based on community tips!', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.aiBlue, height: 1.4))),
                ]),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (destCtrl.text.trim().isEmpty) return;
                    Navigator.pop(ctx);
                    String? imageUrl; String? destId;
                    for (final d in _travelSvc.destinations) {
                      if (d.name.toLowerCase().contains(destCtrl.text.trim().toLowerCase()) || d.country.toLowerCase().contains(destCtrl.text.trim().toLowerCase())) {
                        imageUrl = d.imageUrl; destId = d.id; break;
                      }
                    }
                    setState(() => _trips.insert(0, UserTrip(
                      id: 'trip_${DateTime.now().millisecondsSinceEpoch}', destination: destCtrl.text.trim(),
                      destinationId: destId, imageUrl: imageUrl, departureDate: dep, returnDate: ret,
                      childAges: ageCtrl.text.trim().isNotEmpty ? [ageCtrl.text.trim()] : [],
                      checklists: _defaultChecklists(destCtrl.text.trim()),
                    )));
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: HuddlColors.primary, foregroundColor: HuddlColors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                  child: Text('Create Trip', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _datePicker(String label, DateTime? date, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: HuddlColors.textDark)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.calendar_today, size: 16, color: HuddlColors.textHint),
            const SizedBox(width: 8),
            Text(date != null ? '${date.day}/${date.month}/${date.year}' : 'Select date', style: GoogleFonts.poppins(fontSize: 13, color: date != null ? HuddlColors.textDark : HuddlColors.textHint)),
          ]),
        ),
      ]),
    );
  }

  List<TripChecklist> _defaultChecklists(String dest) {
    return [
      TripChecklist(id: 'new_docs', title: 'Documents', icon: Icons.description, color: HuddlColors.error, items: [
        ChecklistItem(id: 'n1', label: 'Passports (check expiry)'), ChecklistItem(id: 'n2', label: 'Travel insurance'),
        ChecklistItem(id: 'n3', label: 'EHIC/GHIC card'), ChecklistItem(id: 'n4', label: 'Booking confirmations'),
      ]),
      TripChecklist(id: 'new_flight', title: 'Flight Prep', icon: Icons.flight, color: HuddlColors.blue, items: [
        ChecklistItem(id: 'n5', label: 'Request bassinet seat', isAiGenerated: true),
        ChecklistItem(id: 'n6', label: 'Snacks & bottles in hand luggage'),
        ChecklistItem(id: 'n7', label: 'Spare clothes for parent & baby', isAiGenerated: true),
      ]),
      TripChecklist(id: 'new_baby', title: 'Baby Gear', icon: Icons.child_care, color: HuddlColors.teal, items: [
        ChecklistItem(id: 'n8', label: 'Travel pushchair or sling'),
        ChecklistItem(id: 'n9', label: 'Portable blackout blind', isAiGenerated: true),
        ChecklistItem(id: 'n10', label: 'Sun tent / beach shade'),
      ]),
      TripChecklist(id: 'new_health', title: 'Health & Safety', icon: Icons.medical_services, color: HuddlColors.primary, items: [
        ChecklistItem(id: 'n11', label: 'Baby sunscreen SPF50+'),
        ChecklistItem(id: 'n12', label: 'Children\'s medicine'),
        ChecklistItem(id: 'n13', label: 'Rehydration sachets'),
      ]),
    ];
  }
}

// =============================================================================
// TRIP DETAIL — Full checklist view
// =============================================================================
class _TripDetailScreen extends StatefulWidget {
  final UserTrip trip;
  final TravelCommunityService commSvc;
  const _TripDetailScreen({required this.trip, required this.commSvc});

  @override
  State<_TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<_TripDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final emoji = _destEmojis[trip.destination] ?? '✈️';
    final fc = _destColors[trip.destination] ?? HuddlColors.primary;

    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: CustomScrollView(slivers: [
        // Hero header with gradient fallback
        SliverAppBar(
          expandedHeight: 200, pinned: true, backgroundColor: HuddlColors.white,
          leading: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: HuddlColors.white.withValues(alpha: 0.9), shape: BoxShape.circle),
              child: const Icon(Icons.arrow_back_ios_new, size: 18, color: HuddlColors.textDark),
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            title: Text(trip.destination, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: HuddlColors.white)),
            background: Stack(fit: StackFit.expand, children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [fc.withValues(alpha: 0.35), fc.withValues(alpha: 0.1)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 72))),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)]),
                ),
              ),
            ]),
          ),
        ),

        // Info bar
        SliverToBoxAdapter(child: Container(
          color: HuddlColors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Row(children: [
            _info(Icons.calendar_today, trip.dateRange, HuddlColors.blue),
            const SizedBox(width: 12),
            if (trip.childAges.isNotEmpty) _info(Icons.child_care, trip.childAges.first, HuddlColors.teal),
            const Spacer(),
            if (trip.daysUntil > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: HuddlColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Text('${trip.daysUntil} days to go', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
              ),
          ]),
        )),

        // Progress
        SliverToBoxAdapter(child: Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Trip Prep Progress', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              const Spacer(),
              Text('${(trip.progress * 100).toInt()}%', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: trip.progress >= 1 ? HuddlColors.successGreen : HuddlColors.primary)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: trip.progress, backgroundColor: HuddlColors.gray200, valueColor: AlwaysStoppedAnimation<Color>(trip.progress >= 1 ? HuddlColors.successGreen : HuddlColors.primary), minHeight: 8),
            ),
            const SizedBox(height: 6),
            Text('${trip.completedItems} of ${trip.totalItems} items checked', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
          ]),
        )),

        // Checklists header
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(children: [
            Text('Checklists', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: HuddlColors.aiBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.auto_awesome, size: 11, color: HuddlColors.aiBlue),
                const SizedBox(width: 3),
                Text('AI + Community', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: HuddlColors.aiBlue)),
              ]),
            ),
          ]),
        )),

        SliverList(delegate: SliverChildBuilderDelegate(
          (_, i) => _checklistSection(trip.checklists[i]),
          childCount: trip.checklists.length,
        )),

        // Quick actions
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Quick Actions', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
        )),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: _quickAction(Icons.forum, 'Ask Parents', HuddlColors.primary, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AskParentsScreen())))),
            const SizedBox(width: 10),
            Expanded(child: _quickAction(Icons.auto_awesome, 'AI Concierge', HuddlColors.aiBlue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TravelConciergeScreen())))),
            const SizedBox(width: 10),
            Expanded(child: _quickAction(Icons.lightbulb, 'Tips', HuddlColors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => CommunityTipsScreen(filterDestination: trip.destination))))),
          ]),
        )),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ]),
    );
  }

  Widget _info(IconData icon, String text, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(text, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
    ]);
  }

  Widget _checklistSection(TripChecklist cl) {
    final done = cl.items.where((i) => i.isChecked).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      decoration: BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => cl.isExpanded = !cl.isExpanded),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: cl.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(cl.icon, size: 18, color: cl.color),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cl.title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                Text('$done/${cl.items.length} completed', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
              ])),
              Icon(cl.isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: HuddlColors.textHint),
            ]),
          ),
        ),
        if (cl.isExpanded) ...cl.items.map((i) => _checkItem(i)),
        if (cl.isExpanded) const SizedBox(height: 8),
      ]),
    );
  }

  Widget _checkItem(ChecklistItem item) {
    return GestureDetector(
      onTap: () => setState(() => item.isChecked = !item.isChecked),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22, height: 22, margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: item.isChecked ? HuddlColors.successGreen : HuddlColors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: item.isChecked ? HuddlColors.successGreen : HuddlColors.gray300, width: 2),
            ),
            child: item.isChecked ? const Icon(Icons.check, size: 14, color: HuddlColors.white) : null,
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(item.label, style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w500,
                color: item.isChecked ? HuddlColors.textHint : HuddlColors.textDark,
                decoration: item.isChecked ? TextDecoration.lineThrough : null,
              ))),
              if (item.isAiGenerated)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: HuddlColors.aiBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.auto_awesome, size: 9, color: HuddlColors.aiBlue),
                    const SizedBox(width: 2),
                    Text('AI', style: GoogleFonts.poppins(fontSize: 8, fontWeight: FontWeight.w600, color: HuddlColors.aiBlue)),
                  ]),
                ),
            ]),
            if (item.detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(item.detail!, style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint, height: 1.3)),
              ),
          ])),
        ]),
      ),
    );
  }

  Widget _quickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 6),
          Text(label, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: color), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
