import 'postcode_service.dart';

/// Geographic grain at which a resident group is keyed.
///
/// [district]  — launch grain. Group keyed on admin_district from postcodes.io
///               (e.g. "Cambridge", "Tower Hamlets"). Identical to the current
///               borough-based scheme — zero document-ID change.
/// [neighbourhood] — future grain. Keyed on a sub-district place name from the
///               place_grain Firestore table. NOT built yet — the seam is
///               reserved but the table does not exist.
enum PlaceGrain { district, neighbourhood }

/// Result of PlaceResolver.resolve(). Null return from resolve() means the
/// postcode's admin_district could not be determined and NO group should be
/// created — the caller falls back to the existing block-placement path.
class PlaceResult {
  /// Geographic grain used for this result.
  final PlaceGrain grain;

  /// Stable URL-safe slug used as the place token in the group ID.
  /// Derived by lower-casing placeName and replacing spaces/non-alphanumerics
  /// with underscores.  At district grain this equals the current borough slug
  /// so existing group document IDs are unchanged.
  /// Example: "Tower Hamlets" → "tower_hamlets"
  final String placeKey;

  /// Human-readable place name used in the group display name.
  /// At district grain equals admin_district verbatim.
  /// Example: "Tower Hamlets", "Cambridge"
  final String placeName;

  /// Raw admin_district value. Always written to the Firestore borough field
  /// so the security-rule boroughMatches() check continues to work unchanged.
  /// Must never be derived from placeKey — it is the authoritative string.
  final String borough;

  const PlaceResult({
    required this.grain,
    required this.placeKey,
    required this.placeName,
    required this.borough,
  });
}

/// Resolves a PostcodeGeoResult into a PlaceResult for resident-group placement.
///
/// Call resolve() once per placement; the result drives both the group ID
/// (via placeKey) and the display name (via placeName).  The borough field
/// is passed unchanged to Firestore — do not substitute placeKey for it.
///
/// Null-safe contract: resolve() returns null when admin_district is absent
/// (Welsh postcodes return 404 from postcodes.io; some Scottish postcodes
/// omit the field).  Callers MUST treat null as "placement not possible at
/// this grain" and either fall back to the outward-code cache value or route
/// to the existing "set your area" block-placement path.  A null result must
/// NEVER produce a group with an empty or garbage key.
class PlaceResolver {
  const PlaceResolver._();

  /// Resolve [geo] to a [PlaceResult] for resident-group placement.
  ///
  /// Returns null if the district cannot be determined from the geo result.
  ///
  /// ── Neighbourhood seam ──────────────────────────────────────────────────
  /// When the neighbourhood grain ships, insert a Firestore lookup here,
  /// keyed by geo.districtCode (GSS E-code) and optionally geo.wardCode,
  /// against a `place_grain` collection doc.  If the doc exists and carries
  /// a neighbourhood override for this ward/LSOA, return a PlaceResult with
  /// grain = PlaceGrain.neighbourhood and the override placeName/placeKey.
  ///
  /// That lookup must be async and must be performed BEFORE the district
  /// derivation below.  Do NOT add it now — the collection does not exist
  /// and an unconditional .get() on every signup would add unnecessary
  /// latency.  The seam is here; the table is not.
  /// ────────────────────────────────────────────────────────────────────────
  static PlaceResult? resolve(PostcodeGeoResult? geo) {
    if (geo == null) return null;

    // ── Neighbourhood override seam (NOT built) ──────────────────────────
    // Future: check place_grain/{geo.districtCode} in Firestore for a
    // ward- or LSOA-level override before falling through to district grain.
    // ────────────────────────────────────────────────────────────────────────

    // ── District grain (launch) ──────────────────────────────────────────
    final district = geo.borough; // admin_district from postcodes.io

    // Null-safe guard: Welsh (CF*) postcodes return 404; some Scottish
    // postcodes omit admin_district.  Return null so the caller falls back
    // to the outward-code cache value or blocks placement — never emit a
    // group from an empty district string.
    if (district == null || district.isEmpty) return null;

    // placeKey: stable slug for the group document ID.
    // Identical to the current borough-based ID token so no existing
    // document IDs change at launch grain.
    final placeKey = district
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');

    // Guard: if slugification produced an empty string (e.g. a district name
    // consisting entirely of non-alphanumeric characters — pathological but
    // defensive), treat as unresolvable.
    if (placeKey.isEmpty) return null;

    return PlaceResult(
      grain: PlaceGrain.district,
      placeKey: placeKey,
      placeName: district,   // display name = admin_district verbatim
      borough: district,     // Firestore borough field = admin_district verbatim
    );
  }
}
