import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/travel_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PARENTS ABROAD — Temporary travel community hub
// ═══════════════════════════════════════════════════════════════════════════════

class ParentsAbroadScreen extends StatefulWidget {
  final TravelDestination destination;
  const ParentsAbroadScreen({super.key, required this.destination});

  @override
  State<ParentsAbroadScreen> createState() => _ParentsAbroadScreenState();
}

class _ParentsAbroadScreenState extends State<ParentsAbroadScreen> {
  final TravelService _travelService = TravelService();
  late ParentsAbroad _data;
  bool _hasJoinedHub = false;
  final Set<String> _joinedActivities = {};
  final Set<String> _messagedFamilies = {};

  @override
  void initState() {
    super.initState();
    _data = _travelService.getParentsAbroad(widget.destination.id);
  }

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.white)),
      backgroundColor: color ?? HuddlColors.teal,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 20), onPressed: () => Navigator.pop(context)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Parents Abroad', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            Text(widget.destination.name, style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.teal)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status card ─────────────────────────────────────
            _buildStatusCard(),
            const SizedBox(height: 24),
            // ── Families here now ───────────────────────────────
            Text('Huddl families here now', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            const SizedBox(height: 4),
            Text('Connect with local parents for playdates and tips', style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary)),
            const SizedBox(height: 14),
            ..._data.families.map((f) => _buildFamilyCard(f)),
            const SizedBox(height: 24),
            // ── Community activities ─────────────────────────────
            Text('Community activities', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            const SizedBox(height: 4),
            Text('Meet-ups organised by huddl parents on holiday', style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary)),
            const SizedBox(height: 14),
            ..._data.activities.map((a) => _buildActivityCard(a)),
            const SizedBox(height: 24),
            // ── Live companion ───────────────────────────────────
            _buildLiveCompanionSection(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // ── Status card ─────────────────────────────────────────────────────────

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF3ED), Color(0xFFFFFFFF)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(gradient: HuddlColors.primaryGradient, borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.groups, color: HuddlColors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_data.familiesHere} huddl families in ${_data.destinationName}', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                  Text('This week', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Avatar row
          Row(
            children: [
              ..._data.families.take(4).map((f) {
                final color = Color(int.parse(f.avatarColor.replaceFirst('#', '0xFF')));
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withValues(alpha: 0.2),
                    child: Text(f.parentName[0], style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
                  ),
                );
              }),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  if (!_hasJoinedHub) {
                    setState(() => _hasJoinedHub = true);
                    _showSnack('You\'ve joined the ${_data.destinationName} travel hub! You\'ll see updates from families here.');
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: _hasJoinedHub ? null : HuddlColors.primaryGradient,
                    color: _hasJoinedHub ? HuddlColors.teal.withValues(alpha: 0.15) : null,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _hasJoinedHub ? 'Joined ✓' : 'Join Hub',
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: _hasJoinedHub ? HuddlColors.teal : HuddlColors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Family card ─────────────────────────────────────────────────────────

  Widget _buildFamilyCard(AbroadFamily family) {
    final color = Color(int.parse(family.avatarColor.replaceFirst('#', '0xFF')));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HuddlColors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Text(family.parentName[0], style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: color)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(family.parentName, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              Text(family.childAges, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.calendar_today, size: 12, color: HuddlColors.textHint),
                const SizedBox(width: 4),
                Text(family.stayDates, style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
              ]),
              Row(children: [
                Icon(Icons.hotel, size: 12, color: HuddlColors.textHint),
                const SizedBox(width: 4),
                Text(family.accommodation, style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
              ]),
            ]),
          ),
          Column(children: [
            GestureDetector(
              onTap: () {
                if (_messagedFamilies.contains(family.parentName)) return;
                setState(() => _messagedFamilies.add(family.parentName));
                _showSnack('Message request sent to ${family.parentName}! They\'ll be notified.');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _messagedFamilies.contains(family.parentName)
                      ? HuddlColors.teal.withValues(alpha: 0.1)
                      : HuddlColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _messagedFamilies.contains(family.parentName) ? 'Sent ✓' : 'Message',
                  style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: _messagedFamilies.contains(family.parentName) ? HuddlColors.teal : HuddlColors.primary,
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Activity card ───────────────────────────────────────────────────────

  Widget _buildActivityCard(AbroadActivity activity) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HuddlColors.teal.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: HuddlColors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.event, color: HuddlColors.teal, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(activity.title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                  Text('Organised by ${activity.organiser}', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: HuddlColors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text('${activity.spotsLeft} spots', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.teal)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.access_time, size: 14, color: HuddlColors.textHint),
              const SizedBox(width: 4),
              Text(activity.dateTime, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.place, size: 14, color: HuddlColors.textHint),
              const SizedBox(width: 4),
              Expanded(child: Text(activity.location, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary))),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_joinedActivities.contains(activity.title)) return;
                  setState(() => _joinedActivities.add(activity.title));
                  _showSnack('You\'re in! ${activity.organiser} will be notified. See you at ${activity.dateTime}.');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: _joinedActivities.contains(activity.title) ? null : HuddlColors.primaryGradient,
                    color: _joinedActivities.contains(activity.title) ? HuddlColors.teal.withValues(alpha: 0.15) : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _joinedActivities.contains(activity.title) ? 'Joined ✓' : 'Join Activity',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: _joinedActivities.contains(activity.title) ? HuddlColors.teal : HuddlColors.white,
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Live companion section ──────────────────────────────────────────────

  Widget _buildLiveCompanionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Live Trip Companion', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
        const SizedBox(height: 4),
        Text('Quick help while you\'re on holiday', style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _buildQuickHelpCard(Icons.local_pharmacy, 'Nappy\nemergency', 'Nearest shop\nopen now', HuddlColors.primary)),
            const SizedBox(width: 10),
            Expanded(child: _buildQuickHelpCard(Icons.child_friendly, 'Meltdown\nmode', 'Nearest play\narea', HuddlColors.teal)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildQuickHelpCard(Icons.restaurant, 'Family\nlunch', 'Highchairs\nnearby', HuddlColors.accentAmber)),
            const SizedBox(width: 10),
            Expanded(child: _buildQuickHelpCard(Icons.cloud, 'Rainy\nday', 'Indoor\nactivities', HuddlColors.blue)),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickHelpCard(IconData icon, String title, String subtitle, Color color) {
    return GestureDetector(
      onTap: () {
        _showSnack('Searching for "${title.replaceAll('\n', ' ')}" near you in ${widget.destination.name}...', color: color);
      },
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
          const SizedBox(height: 2),
          Text(subtitle, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary)),
        ],
      ),
    ),
    );
  }
}
