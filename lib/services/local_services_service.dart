import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'ai_api_helper.dart';
import 'browser_storage.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';

// =============================================================================
// LOCAL SERVICES SERVICE — HUDDL TRUSTED LOCAL DIRECTORY
//
// Implements the Yelp-for-parents directory built on real WhatsApp-style
// community endorsements. This is NOT a star-rating system — it is a
// community endorsement network where every upvote is a named parent vouching.
//
// Core capabilities:
//
//  1. ServiceDirectory    — Borough-scoped listings by category. Each listing
//                           carries the professional's name, category, contact
//                           info, and a curated list of endorsement quotes
//                           from real local parents.
//
//  2. EndorsementEngine   — Parents endorse (not rate) a listing. Each
//                           endorsement optionally carries a quote
//                           ("Sandra is insured, reliable, brilliant with kids").
//                           Endorser credit: first name + borough parent.
//                           Sub-collection: local_services/{id}/endorsements/{uid}
//
//  3. AiExtraction        — Paste raw group-chat text; AI identifies service
//                           recommendations, extracts name/category/quote,
//                           and seeds a draft listing for the parent to review
//                           before submitting.
//
//  4. VerificationTier    — HVs, doulas, NCT instructors, CPR trainers can
//                           apply for a blue verified badge. Verification is
//                           manual (admin sets flag on Firestore document).
//
//  5. DirectBooking       — DM integration: "Enquire via Huddl" opens a
//                           pre-filled DM to the listing owner's UID (if they
//                           are a Huddl member) or copies contact details.
//
// Firestore schema:
//   local_services/{listingId}
//     — borough, category, name, tagline, description, phone, website
//     — ownerUid (nullable — not all pros are Huddl members)
//     — verificationTier, isVerified
//     — endorsementCount, viewCount
//     — createdAt, updatedAt
//     — createdByUid (parent who first added them)
//     — tags: List<String>
//     — borough: String          ← primary scope field
//     — listingSource: String    ← 'ai_discovered' | 'parent_added'
//     — aiRating: double?        ← star rating from AI web search (≥4.5 only)
//     — aiDiscoveredAt: Timestamp?
//   local_services/{listingId}/endorsements/{uid}
//     — uid, firstName, borough, quote, createdAt
//
// Moat rationale:
//   Real endorsements from verified local parents are impossible to fake on
//   Google Maps or Facebook. Every endorsement a parent makes on Huddl
//   strengthens the directory's network effect.
// =============================================================================

// ─── Service category enum ─────────────────────────────────────────────────

enum ServiceCategory {
  childcare,
  babysitting,
  cleaning,
  healthWellness,
  education,
  fitness,
  firstAid,
  doula,
  homeServices,
  photography,
  food,
  other,
}

extension ServiceCategoryX on ServiceCategory {
  String get displayName => switch (this) {
        ServiceCategory.childcare      => 'Childcare',
        ServiceCategory.babysitting    => 'Babysitting',
        ServiceCategory.cleaning       => 'Cleaning',
        ServiceCategory.healthWellness => 'Health & Wellness',
        ServiceCategory.education      => 'Tutoring & Education',
        ServiceCategory.fitness        => 'Fitness & Classes',
        ServiceCategory.firstAid       => 'First Aid & CPR',
        ServiceCategory.doula          => 'Doula & Birth',
        ServiceCategory.homeServices   => 'Home Services',
        ServiceCategory.photography    => 'Photography',
        ServiceCategory.food           => 'Food & Catering',
        ServiceCategory.other          => 'Other',
      };

  String get emoji => switch (this) {
        ServiceCategory.childcare      => '👶',
        ServiceCategory.babysitting    => '🧸',
        ServiceCategory.cleaning       => '🧹',
        ServiceCategory.healthWellness => '💆',
        ServiceCategory.education      => '📚',
        ServiceCategory.fitness        => '🏃',
        ServiceCategory.firstAid       => '🩺',
        ServiceCategory.doula          => '🤱',
        ServiceCategory.homeServices   => '🔧',
        ServiceCategory.photography    => '📸',
        ServiceCategory.food           => '🍱',
        ServiceCategory.other          => '✨',
      };

  String get firestoreValue => name;

  static ServiceCategory fromString(String v) {
    return ServiceCategory.values.firstWhere(
      (c) => c.name == v,
      orElse: () => ServiceCategory.other,
    );
  }
}

// ─── Verification tier enum ────────────────────────────────────────────────

enum VerificationTier {
  none,          // no badge — community listing only
  community,     // endorsed by 3+ local parents (auto)
  verified,      // manually verified by Huddl admin (blue badge)
  huddlVerified, // auto-verified via Partner subscription + business verification
}

extension VerificationTierX on VerificationTier {
  String get firestoreValue => name;
  String get badgeLabel => switch (this) {
        VerificationTier.none          => '',
        VerificationTier.community     => 'Community Pick',
        VerificationTier.verified      => 'Verified Pro',
        VerificationTier.huddlVerified => 'Partner',
      };
  bool get showsBadge => this != VerificationTier.none;

  static VerificationTier fromString(String v) {
    return VerificationTier.values.firstWhere(
      (t) => t.name == v,
      orElse: () => VerificationTier.none,
    );
  }
}

// ─── Endorsement model ────────────────────────────────────────────────────

class ServiceEndorsement {
  final String uid;
  final String firstName;
  final String borough;
  final String? quote;         // optional — "Sandra is reliable, insured, brilliant"
  final DateTime createdAt;
  // Owner reply (Partner feature)
  final String? ownerReply;
  final DateTime? ownerRepliedAt;

  const ServiceEndorsement({
    required this.uid,
    required this.firstName,
    required this.borough,
    this.quote,
    required this.createdAt,
    this.ownerReply,
    this.ownerRepliedAt,
  });

  bool get hasOwnerReply => ownerReply != null && ownerReply!.isNotEmpty;

  String get credit => '$firstName, $borough parent';

  Map<String, dynamic> toFirestore() => {
        'uid':           uid,
        'firstName':     firstName,
        'borough':       borough,
        'quote':         quote,
        'createdAt':     Timestamp.fromDate(createdAt),
        'ownerReply':    ownerReply,
        'ownerRepliedAt': ownerRepliedAt != null
            ? Timestamp.fromDate(ownerRepliedAt!)
            : null,
      };

  factory ServiceEndorsement.fromFirestore(Map<String, dynamic> d) {
    final ts = d['createdAt'];
    final replyTs = d['ownerRepliedAt'];
    return ServiceEndorsement(
      uid:            d['uid'] as String? ?? '',
      firstName:      d['firstName'] as String? ?? 'A parent',
      borough:        d['borough'] as String? ?? 'local',
      quote:          d['quote'] as String?,
      createdAt:      ts is Timestamp ? ts.toDate() : DateTime.now(),
      ownerReply:     d['ownerReply'] as String?,
      ownerRepliedAt: replyTs is Timestamp ? replyTs.toDate() : null,
    );
  }
}

// ─── Service listing model ─────────────────────────────────────────────────

class ServiceListing {
  final String id;
  final String name;           // "Sandra at Clean2Perfection"
  final String tagline;        // "Insured, reliable, family specialist"
  final String description;
  final ServiceCategory category;
  final String borough;
  final List<String> tags;     // ["insured", "DBS checked", "flexible hours"]
  final String? phone;
  final String? website;
  final String? ownerUid;      // null if pro is not a Huddl member
  final String createdByUid;
  final VerificationTier verificationTier;
  final bool isVerified;
  final int endorsementCount;
  final int viewCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  // Hydrated at read-time from sub-collection (not stored on main doc)
  final List<ServiceEndorsement> recentEndorsements;
  // Whether the current user has already endorsed this listing
  final bool hasEndorsed;

  // ── Source provenance ────────────────────────────────────────────────────
  /// 'ai_discovered' — found by Huddl AI web search (≥4.5★)
  /// 'parent_added'  — submitted by a community parent via Add / AI tab
  final String listingSource;

  /// Star rating as reported by AI web search (null for parent-added)
  final double? aiRating;

  /// When the AI discovery job last found/updated this listing
  final DateTime? aiDiscoveredAt;

  /// Per-listing image URL sourced from the business website or web search.
  /// Falls back to category image in the UI if null or empty.
  final String? imageUrl;

  /// The name the adding parent uses in their borough (e.g. "Sarah from Chesterton").
  /// Optional — only set on parent-added listings. Lets other parents identify
  /// and DM the person who added/endorsed the service.
  final String? parentName;

  // ── Partner-specific fields (v4) ───────────────────────────────────────────

  /// Whether the listing owner is a verified Huddl Partner business.
  final bool isPartnerListing;

  /// Booking / appointment URL for Partner listings.
  final String? bookingUrl;

  /// Priority sort weight for Partner listings in the directory (higher = first).
  final int priorityScore;

  const ServiceListing({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.category,
    required this.borough,
    required this.tags,
    this.phone,
    this.website,
    this.ownerUid,
    required this.createdByUid,
    required this.verificationTier,
    required this.isVerified,
    required this.endorsementCount,
    required this.viewCount,
    required this.createdAt,
    required this.updatedAt,
    this.recentEndorsements = const [],
    this.hasEndorsed = false,
    this.listingSource = 'parent_added',
    this.aiRating,
    this.aiDiscoveredAt,
    this.imageUrl,
    this.parentName,
    this.isPartnerListing = false,
    this.bookingUrl,
    this.priorityScore = 0,
  });

  ServiceListing copyWith({
    String? id,
    String? name,
    String? tagline,
    String? description,
    ServiceCategory? category,
    String? borough,
    List<String>? tags,
    String? phone,
    String? website,
    String? ownerUid,
    bool? isPartnerListing,
    String? bookingUrl,
    int? priorityScore,
    String? createdByUid,
    VerificationTier? verificationTier,
    bool? isVerified,
    int? endorsementCount,
    int? viewCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ServiceEndorsement>? recentEndorsements,
    bool? hasEndorsed,
    String? listingSource,
    double? aiRating,
    DateTime? aiDiscoveredAt,
    String? imageUrl,
    String? parentName,
  }) => ServiceListing(
        id:                  id                  ?? this.id,
        name:                name                ?? this.name,
        tagline:             tagline             ?? this.tagline,
        description:         description         ?? this.description,
        category:            category            ?? this.category,
        borough:             borough             ?? this.borough,
        tags:                tags                ?? this.tags,
        phone:               phone               ?? this.phone,
        website:             website             ?? this.website,
        ownerUid:            ownerUid            ?? this.ownerUid,
        createdByUid:        createdByUid        ?? this.createdByUid,
        verificationTier:    verificationTier    ?? this.verificationTier,
        isVerified:          isVerified          ?? this.isVerified,
        endorsementCount:    endorsementCount    ?? this.endorsementCount,
        viewCount:           viewCount           ?? this.viewCount,
        createdAt:           createdAt           ?? this.createdAt,
        updatedAt:           updatedAt           ?? this.updatedAt,
        recentEndorsements:  recentEndorsements  ?? this.recentEndorsements,
        hasEndorsed:         hasEndorsed         ?? this.hasEndorsed,
        listingSource:       listingSource       ?? this.listingSource,
        aiRating:            aiRating            ?? this.aiRating,
        aiDiscoveredAt:      aiDiscoveredAt      ?? this.aiDiscoveredAt,
        imageUrl:            imageUrl            ?? this.imageUrl,
        parentName:          parentName          ?? this.parentName,
        isPartnerListing:    isPartnerListing    ?? this.isPartnerListing,
        bookingUrl:          bookingUrl          ?? this.bookingUrl,
        priorityScore:       priorityScore       ?? this.priorityScore,
      );

  Map<String, dynamic> toFirestore() => {
        'name':              name,
        'tagline':           tagline,
        'description':       description,
        'category':          category.firestoreValue,
        'borough':           borough,
        'tags':              tags,
        'phone':             phone,
        'website':           website,
        'ownerUid':          ownerUid,
        'createdByUid':      createdByUid,
        'verificationTier':  verificationTier.firestoreValue,
        'isVerified':        isVerified,
        'endorsementCount':  endorsementCount,
        'viewCount':         viewCount,
        'createdAt':         Timestamp.fromDate(createdAt),
        'updatedAt':         Timestamp.fromDate(updatedAt),
        'listingSource':     listingSource,
        if (aiRating != null)       'aiRating':       aiRating,
        if (aiDiscoveredAt != null) 'aiDiscoveredAt': Timestamp.fromDate(aiDiscoveredAt!),
        if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
        if (parentName != null && parentName!.isNotEmpty) 'parentName': parentName,
        'isPartnerListing':  isPartnerListing,
        if (bookingUrl != null && bookingUrl!.isNotEmpty) 'bookingUrl': bookingUrl,
        'priorityScore':     priorityScore,
      };

  factory ServiceListing.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final cat = ServiceCategoryX.fromString(d['category'] as String? ?? '');
    final tier = VerificationTierX.fromString(
        d['verificationTier'] as String? ?? '');
    final ts = d['createdAt'];
    final uts = d['updatedAt'];
    return ServiceListing(
      id:               doc.id,
      name:             d['name']        as String? ?? '',
      tagline:          d['tagline']     as String? ?? '',
      description:      d['description'] as String? ?? '',
      category:         cat,
      borough:          d['borough']     as String? ?? '',
      tags:             (d['tags'] as List<dynamic>?)
                            ?.map((e) => e as String)
                            .toList() ?? [],
      phone:            d['phone']    as String?,
      website:          d['website']  as String?,
      ownerUid:         d['ownerUid'] as String?,
      createdByUid:     d['createdByUid'] as String? ?? '',
      verificationTier: tier,
      isVerified:       d['isVerified']       as bool? ?? false,
      endorsementCount: d['endorsementCount'] as int?  ?? 0,
      viewCount:        d['viewCount']        as int?  ?? 0,
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      updatedAt: uts is Timestamp ? uts.toDate() : DateTime.now(),
      listingSource:  d['listingSource'] as String? ?? 'parent_added',
      aiRating:       (d['aiRating'] as num?)?.toDouble(),
      aiDiscoveredAt: d['aiDiscoveredAt'] is Timestamp
          ? (d['aiDiscoveredAt'] as Timestamp).toDate()
          : null,
      imageUrl:          d['imageUrl'] as String?,
      parentName:        d['parentName'] as String?,
      isPartnerListing:  d['isPartnerListing'] as bool? ?? false,
      bookingUrl:        d['bookingUrl'] as String?,
      priorityScore:     d['priorityScore'] as int? ?? 0,
    );
  }
}

// ─── AI extraction result ──────────────────────────────────────────────────

/// Represents a service recommendation the AI identified in raw chat text.
class ExtractedServiceRecommendation {
  final String name;
  final String? quote;         // the endorsement text from the message
  final ServiceCategory category;
  final String? phone;
  final String? website;
  final List<String> tags;
  final String confidence;     // "high" | "medium" | "low"

  const ExtractedServiceRecommendation({
    required this.name,
    this.quote,
    required this.category,
    this.phone,
    this.website,
    required this.tags,
    required this.confidence,
  });
}

// ─── Service ──────────────────────────────────────────────────────────────

class LocalServicesService {
  // Singleton
  static final LocalServicesService _instance =
      LocalServicesService._internal();
  factory LocalServicesService() => _instance;
  LocalServicesService._internal();

  static const String _collection = 'local_services';
  static const String _draftKey   = 'services_draft_listing_v1';

  final FirebaseFirestore _db   = FirebaseFirestore.instance;
  final FirebaseAuth      _auth = FirebaseAuth.instance;

  // ── Borough helper ─────────────────────────────────────────────────────────

  String get _userBorough {
    // Prefer the borough that was directly resolved from the full postcode
    // via postcodes.io at onboarding / profile-edit time and persisted.
    final stored = OnboardingDataService().borough;
    if (stored != null && stored.isNotEmpty) return stored;

    // Fallback: sync cache-read from PostcodeService (populated if
    // lookupBoroughAsync has run this session) or outward-code prefix map.
    final postcode = OnboardingDataService().postcode;
    return PostcodeService().getBoroughFromPostcode(postcode) ?? 'Cambridge';
  }

  String get _firstName {
    final full = OnboardingDataService().name ?? '';
    return full.split(' ').first.trim();
  }

  // ── Streams ────────────────────────────────────────────────────────────────

  /// Live stream of all listings in the user's borough, optionally filtered.
  Stream<List<ServiceListing>> listingsStream({
    ServiceCategory? category,
    String? borough,
  }) {
    final targetBorough = borough ?? _userBorough;
    Query<Map<String, dynamic>> q = _db
        .collection(_collection)
        .where('borough', isEqualTo: targetBorough);
    if (category != null) {
      q = q.where('category', isEqualTo: category.firestoreValue);
    }
    return q.snapshots().map((snap) {
      final listings = snap.docs
          .map((d) => ServiceListing.fromFirestore(d))
          .toList();
      // Sort by endorsement count descending in memory (avoids composite index)
      listings.sort((a, b) => b.endorsementCount.compareTo(a.endorsementCount));
      return listings;
    });
  }

  /// Stream of the top-endorsed listings for a given borough (hero section).
  Stream<List<ServiceListing>> topEndorsedStream({int limit = 6}) {
    return _db
        .collection(_collection)
        .where('borough', isEqualTo: _userBorough)
        .snapshots()
        .map((snap) {
      final listings = snap.docs
          .map((d) => ServiceListing.fromFirestore(d))
          .toList();
      listings.sort((a, b) => b.endorsementCount.compareTo(a.endorsementCount));
      return listings.take(limit).toList();
    });
  }

  // ── Read helpers ───────────────────────────────────────────────────────────

  /// Fetch a single listing with its most recent endorsements hydrated.
  Future<ServiceListing?> getListing(String listingId) async {
    try {
      final doc = await _db
          .collection(_collection)
          .doc(listingId)
          .withConverter<Map<String, dynamic>>(
            fromFirestore: (s, _) => s.data() ?? {},
            toFirestore:   (d, _) => d,
          )
          .get();

      if (!doc.exists) return null;

      final snap = await _db
          .collection(_collection)
          .doc(listingId)
          .get();
      final base = ServiceListing.fromFirestore(snap);

      // Hydrate recent endorsements (up to 5)
      final endorsSnap = await _db
          .collection(_collection)
          .doc(listingId)
          .collection('endorsements')
          .limit(5)
          .get();
      final endorsements = endorsSnap.docs
          .map((d) => ServiceEndorsement.fromFirestore(d.data()))
          .toList();

      // Check if current user has endorsed
      final uid = _auth.currentUser?.uid;
      bool hasEndorsed = false;
      if (uid != null) {
        final myEndorse = await _db
            .collection(_collection)
            .doc(listingId)
            .collection('endorsements')
            .doc(uid)
            .get();
        hasEndorsed = myEndorse.exists;
      }

      return base.copyWith(
        recentEndorsements: endorsements,
        hasEndorsed: hasEndorsed,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('LocalServicesService.getListing: $e');
      return null;
    }
  }

  // ── Endorse ────────────────────────────────────────────────────────────────

  /// Endorse a listing. Idempotent — calling twice with the same UID is a no-op.
  /// [quote] is optional — the parent's personal endorsement text.
  Future<void> endorseListing(String listingId, {String? quote}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final firstName = _firstName;
    final borough   = _userBorough;

    final endorsRef = _db
        .collection(_collection)
        .doc(listingId)
        .collection('endorsements')
        .doc(uid);

    final existing = await endorsRef.get();
    if (existing.exists) return; // already endorsed

    final endorsement = ServiceEndorsement(
      uid:       uid,
      firstName: firstName,
      borough:   borough,
      quote:     quote,
      createdAt: DateTime.now(),
    );

    final batch = _db.batch();
    batch.set(endorsRef, endorsement.toFirestore());
    batch.update(
      _db.collection(_collection).doc(listingId),
      {
        'endorsementCount': FieldValue.increment(1),
        'updatedAt':        FieldValue.serverTimestamp(),
      },
    );
    await batch.commit();

    // Check if we should auto-promote to community tier
    final listDoc = await _db.collection(_collection).doc(listingId).get();
    final count = listDoc.data()?['endorsementCount'] as int? ?? 0;
    if (count >= 3) {
      final currentTier = VerificationTierX.fromString(
          listDoc.data()?['verificationTier'] as String? ?? '');
      if (currentTier == VerificationTier.none) {
        await _db.collection(_collection).doc(listingId).update({
          'verificationTier': VerificationTier.community.firestoreValue,
        });
      }
    }
  }

  /// Remove an endorsement (undo).
  Future<void> removeEndorsement(String listingId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final batch = _db.batch();
      batch.delete(_db
          .collection(_collection)
          .doc(listingId)
          .collection('endorsements')
          .doc(uid));
      batch.update(
        _db.collection(_collection).doc(listingId),
        {
          'endorsementCount': FieldValue.increment(-1),
          'updatedAt':        FieldValue.serverTimestamp(),
        },
      );
      await batch.commit();
    } catch (e) {
      if (kDebugMode) debugPrint('LocalServicesService.removeEndorsement: $e');
    }
  }

  // ── Record view ────────────────────────────────────────────────────────────

  // Session-level dedup: each listing is counted at most once per app session.
  final Set<String> _viewedThisSession = {};

  void recordView(String listingId, {bool isPartner = false}) {
    if (_viewedThisSession.contains(listingId)) return;
    _viewedThisSession.add(listingId);
    _db.collection(_collection).doc(listingId).update({
      'viewCount': FieldValue.increment(1),
    }).catchError((e) {
      if (kDebugMode) debugPrint('LocalServicesService.recordView: $e');
    });
    // Partner analytics: record per-listing view event
    if (isPartner) {
      final today = DateTime.now();
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      _db
          .collection('partner_analytics')
          .doc(listingId)
          .collection('views')
          .doc(dateKey)
          .set({'count': FieldValue.increment(1)}, SetOptions(merge: true))
          .catchError((_) {});
    }
  }

  // ── Reply to endorsement (Partner only) ─────────────────────────────────────

  /// Allows the Partner owner to post a public reply to an endorsement.
  /// The caller is responsible for confirming the user is the listing owner
  /// and has the Partner tier.
  Future<bool> replyToEndorsement({
    required String listingId,
    required String endorserUid,
    required String replyText,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    try {
      await _db
          .collection(_collection)
          .doc(listingId)
          .collection('endorsements')
          .doc(endorserUid)
          .update({
        'ownerReply':     replyText.trim(),
        'ownerRepliedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('LocalServicesService.replyToEndorsement: $e');
      return false;
    }
  }

  // ── Create listing ─────────────────────────────────────────────────────────

  Future<String?> createListing({
    required String name,
    required String tagline,
    required String description,
    required ServiceCategory category,
    List<String> tags = const [],
    String? phone,
    String? website,
    String? borough,
    String? parentName,   // the adding parent's name as known in their borough
    String? bookingUrl,   // Partner: booking / appointment URL
    bool isPartnerListing = false,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    try {
      final now = DateTime.now();
      final listing = ServiceListing(
        id:               '',
        name:             name,
        tagline:          tagline,
        description:      description,
        category:         category,
        borough:          borough ?? _userBorough,
        tags:             tags,
        phone:            phone,
        website:          website,
        ownerUid:         isPartnerListing ? uid : null,
        createdByUid:     uid,
        parentName:       parentName?.trim().isEmpty == true ? null : parentName?.trim(),
        verificationTier: isPartnerListing
            ? VerificationTier.huddlVerified
            : VerificationTier.none,
        isVerified:       isPartnerListing,
        endorsementCount: 0,
        viewCount:        0,
        createdAt:        now,
        updatedAt:        now,
        isPartnerListing: isPartnerListing,
        bookingUrl:       bookingUrl?.trim().isEmpty == true ? null : bookingUrl?.trim(),
        priorityScore:    isPartnerListing ? 10 : 0,
      );

      final ref = await _db
          .collection(_collection)
          .add(listing.toFirestore());
      return ref.id;
    } catch (e) {
      if (kDebugMode) debugPrint('LocalServicesService.createListing: $e');
      return null;
    }
  }

  // ── Draft persistence ──────────────────────────────────────────────────────

  Future<void> saveDraft(Map<String, dynamic> draft) async {
    await BrowserStorage.setString(_draftKey, jsonEncode(draft));
  }

  Future<Map<String, dynamic>?> loadDraft() async {
    final raw = await BrowserStorage.getString(_draftKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearDraft() async {
    await BrowserStorage.remove(_draftKey);
  }

  // ── AI extraction ──────────────────────────────────────────────────────────

  /// Analyse raw group-chat text and extract service recommendations.
  ///
  /// Returns a list of [ExtractedServiceRecommendation] objects sorted by
  /// confidence. The caller should present these as draft listings for review.
  Future<List<ExtractedServiceRecommendation>> extractFromChatText(
      String chatText) async {
    if (chatText.trim().isEmpty) return [];

    const prompt = '''
You are analysing UK parent WhatsApp group messages to extract local service recommendations.

Look for messages where parents recommend a specific person or business for a service
(e.g. cleaners, babysitters, CPR instructors, doulas, tutors, plumbers, photographers).

For each recommendation found, extract:
- name: the person/business name (e.g. "Sandra at Clean2Perfection", "Alli Pavis", "Martina at Little Gym")
- category: one of: childcare, babysitting, cleaning, healthWellness, education, fitness, firstAid, doula, homeServices, photography, food, other
- quote: the exact endorsement text from the message (keep it natural, under 120 chars)
- phone: phone number if mentioned (or null)
- website: website/Instagram if mentioned (or null)
- tags: up to 4 short tags like ["insured", "DBS checked", "flexible"] derived from the message
- confidence: "high" (named person + specific endorsement), "medium" (name + general praise), "low" (vague mention)

Respond ONLY with a valid JSON array. No markdown, no explanation. Example:
[{"name":"Sandra at Clean2Perfection","category":"cleaning","quote":"Insured, reliable, brilliant with our kids","phone":null,"website":null,"tags":["insured","reliable","family-friendly"],"confidence":"high"}]

If no service recommendations are found, respond with exactly: []
''';

    try {
      final response = await AiApiHelper.generateText(
        {
          'contents': [
            {
              'parts': [
                {'text': '$prompt\n\nGroup chat text:\n$chatText'},
              ],
            },
          ],
          'generationConfig': {
            'temperature':     0.1,
            'maxOutputTokens': 1024,
          },
        },
        timeout: const Duration(seconds: 30),
      );

      if (response == null) return [];

      // Strip markdown fences if present
      var json = response.trim();
      if (json.startsWith('```')) {
        json = json
            .replaceAll(RegExp(r'^```[a-z]*\n?'), '')
            .replaceAll(RegExp(r'\n?```$'), '')
            .trim();
      }

      final list = jsonDecode(json) as List<dynamic>;
      return list.map((item) {
        final m = item as Map<String, dynamic>;
        return ExtractedServiceRecommendation(
          name:       m['name']     as String? ?? '',
          quote:      m['quote']    as String?,
          category:   ServiceCategoryX.fromString(m['category'] as String? ?? ''),
          phone:      m['phone']    as String?,
          website:    m['website']  as String?,
          tags:       (m['tags'] as List<dynamic>?)
                          ?.map((e) => e as String)
                          .toList() ?? [],
          confidence: m['confidence'] as String? ?? 'medium',
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('LocalServicesService.extractFromChatText: $e');
      }
      return [];
    }
  }

  // ── My listings ────────────────────────────────────────────────────────────

  /// Listings created by the current user (across all boroughs).
  Stream<List<ServiceListing>> myListingsStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection(_collection)
        .where('createdByUid', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ServiceListing.fromFirestore(d))
            .toList());
  }

  // ── Check endorsement ──────────────────────────────────────────────────────

  Future<bool> hasEndorsed(String listingId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _db
        .collection(_collection)
        .doc(listingId)
        .collection('endorsements')
        .doc(uid)
        .get();
    return doc.exists;
  }

  // ── Fetch endorsements for a listing ──────────────────────────────────────

  Future<List<ServiceEndorsement>> getEndorsements(
      String listingId, {int limit = 10}) async {
    try {
      final snap = await _db
          .collection(_collection)
          .doc(listingId)
          .collection('endorsements')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs
          .map((d) => ServiceEndorsement.fromFirestore(d.data()))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('LocalServicesService.getEndorsements: $e');
      return [];
    }
  }
}
