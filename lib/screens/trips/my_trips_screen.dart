import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/travel_community_service.dart';
import '../../services/travel_service.dart';
import '../../services/subscription_service.dart';
import 'ask_parents_screen.dart';
import 'travel_concierge_screen.dart';


// =============================================================================
// MY TRIPS — Personal travel planner with community-informed data
// Saved research, AI-generated checklists, bookmarks, and trip planning
// =============================================================================

/// A user's planned trip with community-informed data
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

  int get daysUntil {
    if (departureDate == null) return -1;
    return departureDate!.difference(DateTime.now()).inDays;
  }

  String get dateRange {
    if (departureDate == null) return 'Dates not set';
    final dep = '${departureDate!.day}/${departureDate!.month}';
    if (returnDate == null) return dep;
    final ret = '${returnDate!.day}/${returnDate!.month}';
    return '$dep - $ret';
  }

  int get completedItems {
    int count = 0;
    for (final cl in checklists) {
      count += cl.items.where((i) => i.isChecked).length;
    }
    return count;
  }

  int get totalItems {
    int count = 0;
    for (final cl in checklists) {
      count += cl.items.length;
    }
    return count;
  }

  double get progress => totalItems == 0 ? 0 : completedItems / totalItems;
}

/// A checklist category within a trip
class TripChecklist {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final List<ChecklistItem> items;
  bool isExpanded;

  TripChecklist({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    List<ChecklistItem>? items,
    this.isExpanded = false,
  }) : items = items ?? [];
}

/// A single checklist item
class ChecklistItem {
  final String id;
  final String label;
  final String? detail;
  final bool isAiGenerated;
  bool isChecked;

  ChecklistItem({
    required this.id,
    required this.label,
    this.detail,
    this.isAiGenerated = false,
    this.isChecked = false,
  });
}

class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  final TravelCommunityService _communityService = TravelCommunityService();
  final TravelService _travelService = TravelService();
  final SubscriptionService _subscriptionService = SubscriptionService();
  bool _isLoading = true;
  final List<UserTrip> _trips = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _travelService.initialize();
    await _communityService.initialize();
    await _subscriptionService.initialize();
    _loadSampleTrips();
    if (mounted) setState(() => _isLoading = false);
  }

  void _loadSampleTrips() {
    final dests = _travelService.destinations;
    final tenerife = dests.firstWhere((d) => d.name == 'Tenerife', orElse: () => dests.first);
    final mallorca = dests.length > 1
        ? dests.firstWhere((d) => d.name == 'Mallorca', orElse: () => dests[1])
        : dests.first;

    _trips.addAll([
      UserTrip(
        id: 'trip_1',
        destination: 'Tenerife',
        destinationId: tenerife.id,
        imageUrl: tenerife.imageUrl,
        departureDate: DateTime.now().add(const Duration(days: 23)),
        returnDate: DateTime.now().add(const Duration(days: 30)),
        childAges: ['14 months'],
        isActive: true,
        savedResearch: _communityService.savedAnswers.take(2).toList(),
        checklists: [
          TripChecklist(
            id: 'cl_docs', title: 'Documents & Essentials', icon: Icons.description, color: HuddlColors.error,
            items: [
              ChecklistItem(id: 'ci_1', label: 'Passports (yours + baby)', detail: 'Check expiry dates — must be valid 6 months beyond travel', isChecked: true),
              ChecklistItem(id: 'ci_2', label: 'Travel insurance', detail: 'Community tip: Staysure or AllClear cover pre-existing conditions', isAiGenerated: true),
              ChecklistItem(id: 'ci_3', label: 'EHIC/GHIC health card', detail: 'Free from NHS — covers EU medical treatment'),
              ChecklistItem(id: 'ci_4', label: 'Printed booking confirmations', isChecked: true),
              ChecklistItem(id: 'ci_5', label: 'Baby\'s birth certificate (if name differs from passport)'),
            ],
          ),
          TripChecklist(
            id: 'cl_flight', title: 'Flight Prep', icon: Icons.flight, color: HuddlColors.blue,
            items: [
              ChecklistItem(id: 'ci_6', label: 'Request bassinet seat', detail: 'Parent tip: BA & easyJet offer bassinets for under-1s on Canary flights', isAiGenerated: true),
              ChecklistItem(id: 'ci_7', label: 'Gate-check pushchair', detail: 'Community tip: Wear sling through security, gate-check the buggy'),
              ChecklistItem(id: 'ci_8', label: 'Calpol sachets in hand luggage', detail: 'Under 100ml — security-friendly'),
              ChecklistItem(id: 'ci_9', label: 'New small toy for distraction', detail: 'Parent tip: Something they haven\'t seen before buys 30 mins', isAiGenerated: true),
              ChecklistItem(id: 'ci_10', label: 'Feed on takeoff/landing', detail: 'Helps equalise ear pressure — bottle or breastfeed'),
              ChecklistItem(id: 'ci_11', label: 'Spare clothes for baby AND you', detail: 'Trust the community on this one!', isAiGenerated: true),
            ],
          ),
          TripChecklist(
            id: 'cl_baby', title: 'Baby Gear', icon: Icons.child_care, color: HuddlColors.teal,
            items: [
              ChecklistItem(id: 'ci_12', label: 'Lightweight travel pushchair', detail: 'Community rec: BabyZen YoYo or Silver Cross Jet'),
              ChecklistItem(id: 'ci_13', label: 'Baby sling/carrier', detail: 'Essential for cobblestones and beach access', isAiGenerated: true),
              ChecklistItem(id: 'ci_14', label: 'Portable blackout blind', detail: 'Gro Anywhere Blind — game changer for hotel rooms'),
              ChecklistItem(id: 'ci_15', label: 'Sun tent / beach shade', detail: 'Tenerife sun is strong — SPF50 shade essential'),
              ChecklistItem(id: 'ci_16', label: 'Travel cot (or check hotel provides one)', detail: 'Parent tip: Most Spanish hotels provide free cots — call ahead', isAiGenerated: true),
            ],
          ),
          TripChecklist(
            id: 'cl_health', title: 'Health & Safety', icon: Icons.medical_services, color: HuddlColors.primary,
            items: [
              ChecklistItem(id: 'ci_17', label: 'Baby sunscreen SPF50+', detail: 'Soltan Kids or LaRoche-Posay recommended by parents'),
              ChecklistItem(id: 'ci_18', label: 'Calpol / Nurofen', detail: 'Pre-measure into travel-size containers'),
              ChecklistItem(id: 'ci_19', label: 'Teething gel', detail: 'Anbesol or Bonjela — 14 months is prime teething age', isAiGenerated: true),
              ChecklistItem(id: 'ci_20', label: 'Rehydration sachets', detail: 'Dioralyte — essential for tummy bugs'),
              ChecklistItem(id: 'ci_21', label: 'Plasters & antiseptic wipes'),
              ChecklistItem(id: 'ci_22', label: 'Mosquito repellent (DEET-free for babies)', detail: 'Incognito or Citronella-based spray'),
            ],
          ),
        ],
      ),
      UserTrip(
        id: 'trip_2',
        destination: 'Mallorca',
        destinationId: mallorca.id,
        imageUrl: mallorca.imageUrl,
        departureDate: DateTime.now().add(const Duration(days: 67)),
        returnDate: DateTime.now().add(const Duration(days: 74)),
        childAges: ['14 months'],
        isActive: true,
        checklists: [
          TripChecklist(
            id: 'cl_docs2', title: 'Documents', icon: Icons.description, color: HuddlColors.error,
            items: [
              ChecklistItem(id: 'ci_30', label: 'Passports'),
              ChecklistItem(id: 'ci_31', label: 'Travel insurance'),
              ChecklistItem(id: 'ci_32', label: 'Hotel confirmation'),
            ],
          ),
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: HuddlColors.primary))
          : _trips.isEmpty
              ? _buildEmptyState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Upcoming trips
                      ..._trips.where((t) => t.isActive).map((t) => _buildTripCard(t)),

                      // Saved Research section
                      if (_communityService.savedAnswers.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildSavedResearchSection(),
                      ],

                      // AI Concierge CTA
                      const SizedBox(height: 20),
                      _buildAiConciergeCard(),

                      const SizedBox(height: 100),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateTripSheet(),
        backgroundColor: HuddlColors.primary,
        icon: const Icon(Icons.add, color: HuddlColors.white, size: 20),
        label: Text('New Trip', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.white)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
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
            onPressed: () => _showCreateTripSheet(),
            style: ElevatedButton.styleFrom(
              backgroundColor: HuddlColors.primary, foregroundColor: HuddlColors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text('Plan a Trip', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Trip Card ──────────────────────────────────────────────────────────
  Widget _buildTripCard(UserTrip trip) {
    return GestureDetector(
      onTap: () => _openTripDetail(trip),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: HuddlColors.gray900.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image header
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              child: SizedBox(
                height: 120, width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    trip.imageUrl != null
                        ? Image.network(trip.imageUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: HuddlColors.peachLight,
                              child: Center(child: Icon(Icons.flight_takeoff, size: 40, color: HuddlColors.primary)),
                            ))
                        : Container(color: HuddlColors.peachLight, child: Center(child: Icon(Icons.flight_takeoff, size: 40, color: HuddlColors.primary))),
                    // Gradient overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.5)],
                        ),
                      ),
                    ),
                    // Countdown badge
                    if (trip.daysUntil > 0)
                      Positioned(
                        top: 12, right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.access_time, size: 13, color: HuddlColors.primary),
                            const SizedBox(width: 4),
                            Text('${trip.daysUntil} days', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
                          ]),
                        ),
                      ),
                    // Trip name overlay
                    Positioned(
                      bottom: 12, left: 14,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(trip.destination, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: HuddlColors.white)),
                        Text(trip.dateRange, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.white.withValues(alpha: 0.9))),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
            // Progress section
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Progress bar
                  Row(
                    children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text('Trip Prep', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                            const Spacer(),
                            Text('${trip.completedItems}/${trip.totalItems} items', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
                          ]),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: trip.progress,
                              backgroundColor: HuddlColors.gray200,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                trip.progress >= 1 ? HuddlColors.successGreen : HuddlColors.primary,
                              ),
                              minHeight: 6,
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Quick info row
                  Row(
                    children: [
                      _buildTripInfoChip(Icons.child_care, trip.childAges.isNotEmpty ? trip.childAges.first : 'No ages set', HuddlColors.teal),
                      const SizedBox(width: 8),
                      _buildTripInfoChip(Icons.checklist, '${trip.checklists.length} lists', HuddlColors.blue),
                      if (trip.savedResearch.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _buildTripInfoChip(Icons.bookmark, '${trip.savedResearch.length} saved', HuddlColors.primary),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripInfoChip(IconData icon, String label, Color color) {
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

  // ── Saved Research Section ────────────────────────────────────────────
  Widget _buildSavedResearchSection() {
    final saved = _communityService.savedAnswers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          decoration: BoxDecoration(
            color: HuddlColors.white, borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: HuddlColors.gray900.withValues(alpha: 0.03), blurRadius: 8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.bookmark, size: 14, color: HuddlColors.primary),
              const SizedBox(width: 6),
              Expanded(child: Text(s.questionText, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.textDark), maxLines: 1, overflow: TextOverflow.ellipsis)),
              GestureDetector(
                onTap: () {
                  _communityService.removeSavedAnswer(s.answerId);
                  setState(() {});
                },
                child: const Icon(Icons.close, size: 16, color: HuddlColors.textHint),
              ),
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
      ],
    );
  }

  // ── AI Concierge Card ────────────────────────────────────────────────
  Widget _buildAiConciergeCard() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TravelConciergeScreen())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFEDF4FF), Color(0xFFF5F9FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HuddlColors.aiBlue.withValues(alpha: 0.2)),
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
          Icon(Icons.arrow_forward_ios, size: 14, color: HuddlColors.aiBlue),
        ]),
      ),
    );
  }

  // ── Trip Detail ──────────────────────────────────────────────────────
  void _openTripDetail(UserTrip trip) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _TripDetailScreen(trip: trip, communityService: _communityService)));
  }

  // ── Create Trip ──────────────────────────────────────────────────────
  void _showCreateTripSheet() {
    final destController = TextEditingController();
    final ageController = TextEditingController();
    DateTime? departure;
    DateTime? returnDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: HuddlColors.gray300, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text('Plan a New Trip', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: HuddlColors.textDark)),
                Text('AI will generate checklists based on community data', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
                const SizedBox(height: 20),
                // Destination
                Text('Where are you going?', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(14)),
                  child: TextField(
                    controller: destController,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'e.g. Tenerife, Mallorca, Cornwall...',
                      hintStyle: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textHint),
                      prefixIcon: const Icon(Icons.place, color: HuddlColors.textHint, size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Child ages
                Text('Child age(s)', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(14)),
                  child: TextField(
                    controller: ageController,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'e.g. 14 months, 3 years',
                      hintStyle: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textHint),
                      prefixIcon: const Icon(Icons.child_care, color: HuddlColors.textHint, size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Date pickers
                Row(children: [
                  Expanded(child: _buildDatePicker(
                    'Departure',
                    departure,
                    () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setSheetState(() => departure = picked);
                    },
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _buildDatePicker(
                    'Return',
                    returnDate,
                    () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: departure?.add(const Duration(days: 7)) ?? DateTime.now().add(const Duration(days: 14)),
                        firstDate: departure ?? DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 400)),
                      );
                      if (picked != null) setSheetState(() => returnDate = picked);
                    },
                  )),
                ]),
                const SizedBox(height: 12),
                // AI info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: HuddlColors.aiBlue.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Icon(Icons.auto_awesome, size: 18, color: HuddlColors.aiBlue),
                    const SizedBox(width: 10),
                    Expanded(child: Text('AI will auto-generate travel prep checklists, packing lists, and health briefings based on community tips for your destination!', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.aiBlue, height: 1.4))),
                  ]),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (destController.text.trim().isEmpty) return;
                      Navigator.pop(ctx);

                      // Find matching destination image
                      String? imageUrl;
                      String? destId;
                      for (final d in _travelService.destinations) {
                        if (d.name.toLowerCase().contains(destController.text.trim().toLowerCase()) ||
                            d.country.toLowerCase().contains(destController.text.trim().toLowerCase())) {
                          imageUrl = d.imageUrl;
                          destId = d.id;
                          break;
                        }
                      }

                      final newTrip = UserTrip(
                        id: 'trip_${DateTime.now().millisecondsSinceEpoch}',
                        destination: destController.text.trim(),
                        destinationId: destId,
                        imageUrl: imageUrl,
                        departureDate: departure,
                        returnDate: returnDate,
                        childAges: ageController.text.trim().isNotEmpty ? [ageController.text.trim()] : [],
                        checklists: _generateDefaultChecklists(destController.text.trim()),
                      );

                      setState(() => _trips.insert(0, newTrip));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HuddlColors.primary, foregroundColor: HuddlColors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: Text('Create Trip', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDatePicker(String label, DateTime? date, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: HuddlColors.textDark)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.calendar_today, size: 16, color: HuddlColors.textHint),
              const SizedBox(width: 8),
              Text(
                date != null ? '${date.day}/${date.month}/${date.year}' : 'Select date',
                style: GoogleFonts.poppins(fontSize: 13, color: date != null ? HuddlColors.textDark : HuddlColors.textHint),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  List<TripChecklist> _generateDefaultChecklists(String destination) {
    return [
      TripChecklist(
        id: 'new_docs', title: 'Documents & Essentials', icon: Icons.description, color: HuddlColors.error,
        items: [
          ChecklistItem(id: 'n1', label: 'Passports (check expiry dates)'),
          ChecklistItem(id: 'n2', label: 'Travel insurance'),
          ChecklistItem(id: 'n3', label: 'EHIC/GHIC card'),
          ChecklistItem(id: 'n4', label: 'Booking confirmations'),
        ],
      ),
      TripChecklist(
        id: 'new_flight', title: 'Flight Prep', icon: Icons.flight, color: HuddlColors.blue,
        items: [
          ChecklistItem(id: 'n5', label: 'Request bassinet/bulkhead seat', isAiGenerated: true),
          ChecklistItem(id: 'n6', label: 'Snacks & bottles in hand luggage'),
          ChecklistItem(id: 'n7', label: 'Spare clothes for parent & baby', isAiGenerated: true),
        ],
      ),
      TripChecklist(
        id: 'new_baby', title: 'Baby Gear', icon: Icons.child_care, color: HuddlColors.teal,
        items: [
          ChecklistItem(id: 'n8', label: 'Travel pushchair or sling'),
          ChecklistItem(id: 'n9', label: 'Portable blackout blind', isAiGenerated: true),
          ChecklistItem(id: 'n10', label: 'Sun tent / beach shade'),
        ],
      ),
      TripChecklist(
        id: 'new_health', title: 'Health & Safety', icon: Icons.medical_services, color: HuddlColors.primary,
        items: [
          ChecklistItem(id: 'n11', label: 'Baby sunscreen SPF50+'),
          ChecklistItem(id: 'n12', label: 'Calpol / children\'s medicine'),
          ChecklistItem(id: 'n13', label: 'Rehydration sachets'),
        ],
      ),
    ];
  }
}

// =============================================================================
// TRIP DETAIL SCREEN — Full checklist view with community annotations
// =============================================================================

class _TripDetailScreen extends StatefulWidget {
  final UserTrip trip;
  final TravelCommunityService communityService;

  const _TripDetailScreen({required this.trip, required this.communityService});

  @override
  State<_TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<_TripDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;

    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: CustomScrollView(
        slivers: [
          // Hero header
          SliverAppBar(
            expandedHeight: 200, pinned: true,
            backgroundColor: HuddlColors.white,
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
              background: Stack(
                fit: StackFit.expand,
                children: [
                  trip.imageUrl != null
                      ? Image.network(trip.imageUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: HuddlColors.peachLight))
                      : Container(color: HuddlColors.peachLight),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Trip info bar
          SliverToBoxAdapter(
            child: Container(
              color: HuddlColors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(children: [
                _buildInfoItem(Icons.calendar_today, trip.dateRange, HuddlColors.blue),
                const SizedBox(width: 12),
                if (trip.childAges.isNotEmpty)
                  _buildInfoItem(Icons.child_care, trip.childAges.first, HuddlColors.teal),
                const Spacer(),
                if (trip.daysUntil > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: HuddlColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Text('${trip.daysUntil} days to go', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
                  ),
              ]),
            ),
          ),

          // Progress overview
          SliverToBoxAdapter(
            child: Container(
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
                  child: LinearProgressIndicator(
                    value: trip.progress,
                    backgroundColor: HuddlColors.gray200,
                    valueColor: AlwaysStoppedAnimation<Color>(trip.progress >= 1 ? HuddlColors.successGreen : HuddlColors.primary),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 6),
                Text('${trip.completedItems} of ${trip.totalItems} items checked', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
              ]),
            ),
          ),

          // Checklists
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(children: [
                Text('Checklists', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: HuddlColors.aiBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome, size: 11, color: HuddlColors.aiBlue),
                    const SizedBox(width: 3),
                    Text('AI + Community', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: HuddlColors.aiBlue)),
                  ]),
                ),
              ]),
            ),
          ),

          // Checklist items
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _buildChecklistSection(trip.checklists[i]),
              childCount: trip.checklists.length,
            ),
          ),

          // Quick actions
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Quick Actions', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(child: _buildQuickAction(Icons.forum, 'Ask Parents', HuddlColors.primary, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AskParentsScreen()));
                })),
                const SizedBox(width: 10),
                Expanded(child: _buildQuickAction(Icons.auto_awesome, 'AI Concierge', HuddlColors.aiBlue, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TravelConciergeScreen()));
                })),
                const SizedBox(width: 10),
                Expanded(child: _buildQuickAction(Icons.lightbulb, 'Community Tips', HuddlColors.teal, () {
                  // Would navigate to community tips filtered by destination
                })),
              ]),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String text, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(text, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
    ]);
  }

  Widget _buildChecklistSection(TripChecklist checklist) {
    final checkedCount = checklist.items.where((i) => i.isChecked).length;
    final total = checklist.items.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      decoration: BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          // Header
          GestureDetector(
            onTap: () => setState(() => checklist.isExpanded = !checklist.isExpanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: checklist.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(checklist.icon, size: 18, color: checklist.color),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(checklist.title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                  Text('$checkedCount/$total completed', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
                ])),
                Icon(checklist.isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: HuddlColors.textHint),
              ]),
            ),
          ),
          // Expandable items
          if (checklist.isExpanded)
            ...checklist.items.map((item) => _buildChecklistItem(item)),
          if (checklist.isExpanded) const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildChecklistItem(ChecklistItem item) {
    return GestureDetector(
      onTap: () => setState(() => item.isChecked = !item.isChecked),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22, height: 22,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: item.isChecked ? HuddlColors.successGreen : HuddlColors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: item.isChecked ? HuddlColors.successGreen : HuddlColors.gray300, width: 2),
              ),
              child: item.isChecked ? const Icon(Icons.check, size: 14, color: HuddlColors.white) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        item.label,
                        style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w500,
                          color: item.isChecked ? HuddlColors.textHint : HuddlColors.textDark,
                          decoration: item.isChecked ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (item.isAiGenerated)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: HuddlColors.aiBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.auto_awesome, size: 9, color: HuddlColors.aiBlue),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, Color color, VoidCallback onTap) {
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
