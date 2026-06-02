import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/huddl_colors.dart';
import '../constants/app_text_styles.dart';

// =============================================================================
// PLACES AUTOCOMPLETE FIELD
//
// A drop-in replacement for the bare TextField in the location section of
// Create / Edit Meetup screens.  Calls the Google Places Autocomplete API
// directly (no package dependency) and shows an inline suggestion overlay.
//
// Usage:
//   PlacesAutocompleteField(
//     controller: _locationCtrl,
//     onPlaceSelected: (address) { setState(() { _locationCtrl.text = address; }); },
//   )
//
// API: Places Autocomplete (legacy) — simple GET, no session-token billing.
//   https://maps.googleapis.com/maps/api/place/autocomplete/json
// =============================================================================

class PlacesAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final void Function(String address) onPlaceSelected;
  final Color accentColor;

  const PlacesAutocompleteField({
    super.key,
    required this.controller,
    required this.onPlaceSelected,
    this.accentColor = HuddlColors.primary,
  });

  @override
  State<PlacesAutocompleteField> createState() =>
      _PlacesAutocompleteFieldState();
}

class _PlacesAutocompleteFieldState extends State<PlacesAutocompleteField> {
  // ── Places API key ─────────────────────────────────────────────────────────
  // Sourced from --dart-define=GOOGLE_PLACES_API_KEY=AIza... at build time.
  // SECURITY: Rotate via Google Cloud Console if previously exposed.
  static const String _key = String.fromEnvironment(
    'GOOGLE_PLACES_API_KEY',
    defaultValue: '',
  );
  static const String _baseUrl =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';

  // ── State ─────────────────────────────────────────────────────────────────
  List<_Prediction> _predictions = [];
  bool _loading = false;
  Timer? _debounce;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlay;
  final FocusNode _focus = FocusNode();
  bool _suppressSearch = false; // true when the user just selected a result

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focus.addListener(() {
      if (!_focus.hasFocus) _removeOverlay();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(() {});
    _focus.dispose();
    widget.controller.removeListener(_onTextChanged);
    _removeOverlay();
    super.dispose();
  }

  // ── Text change handler ───────────────────────────────────────────────────

  void _onTextChanged() {
    if (_suppressSearch) {
      _suppressSearch = false;
      return;
    }
    final q = widget.controller.text.trim();
    if (q.length < 3) {
      _debounce?.cancel();
      setState(() => _predictions = []);
      _removeOverlay();
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _fetchPredictions(q));
  }

  // ── Network call ──────────────────────────────────────────────────────────

  Future<void> _fetchPredictions(String input) async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'input': input,
        'key': _key,
        'types': 'geocode|establishment',
        'language': 'en-GB',
        // Bias results toward the UK
        'components': 'country:gb',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        final preds = (body['predictions'] as List<dynamic>? ?? [])
            .map((p) => _Prediction.fromJson(p as Map<String, dynamic>))
            .toList();
        setState(() {
          _predictions = preds;
          _loading = false;
        });
        if (preds.isNotEmpty) {
          _showOverlay();
        } else {
          _removeOverlay();
        }
      } else {
        if (kDebugMode) debugPrint('[Places] HTTP ${res.statusCode}');
        setState(() => _loading = false);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Places] Error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Overlay management ────────────────────────────────────────────────────

  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.of(context);
    _overlay = OverlayEntry(
      builder: (ctx) => Positioned(
        width: _fieldWidth(),
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 52), // just below the text field
          child: _SuggestionList(
            predictions: _predictions,
            loading: _loading,
            accentColor: widget.accentColor,
            onSelect: _onPredictionSelected,
          ),
        ),
      ),
    );
    overlay.insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  // Approximate field width — fallback 320 is sensible for a form field
  double _fieldWidth() {
    try {
      final box = context.findRenderObject() as RenderBox?;
      return box?.size.width ?? 320;
    } catch (_) {
      return 320;
    }
  }

  // ── Selection ─────────────────────────────────────────────────────────────

  void _onPredictionSelected(_Prediction p) {
    _suppressSearch = true;
    widget.controller.text = p.description;
    // Move cursor to end
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: p.description.length),
    );
    setState(() => _predictions = []);
    _removeOverlay();
    _focus.unfocus();
    widget.onPlaceSelected(p.description);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Stack(
        children: [
          TextField(
            controller: widget.controller,
            focusNode: _focus,
            style: HuddlText.body(color: HuddlColors.textDark),
            decoration: InputDecoration(
              hintText: 'Add a location or address',
              hintStyle: HuddlText.body(color: HuddlColors.neutral300),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              border: InputBorder.none,
              // trailing loading spinner
              suffixIcon: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              widget.accentColor),
                        ),
                      ),
                    )
                  : widget.controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16,
                              color: HuddlColors.neutral300),
                          onPressed: () {
                            widget.controller.clear();
                            setState(() => _predictions = []);
                            _removeOverlay();
                            widget.onPlaceSelected('');
                          },
                        )
                      : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Suggestion list overlay widget ───────────────────────────────────────────

class _SuggestionList extends StatelessWidget {
  final List<_Prediction> predictions;
  final bool loading;
  final Color accentColor;
  final void Function(_Prediction) onSelect;

  const _SuggestionList({
    required this.predictions,
    required this.loading,
    required this.accentColor,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (predictions.isEmpty) return const SizedBox.shrink();

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: Colors.white,
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView.separated(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: predictions.length,
            separatorBuilder: (_, __) => const Divider(
                height: 1, thickness: 0.5, color: HuddlColors.neutral100),
            itemBuilder: (ctx, i) {
              final p = predictions[i];
              return InkWell(
                onTap: () => onSelect(p),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 16, color: accentColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.mainText,
                              style: HuddlText.body(color: HuddlColors.textDark),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (p.secondaryText.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              Text(
                                p.secondaryText,
                                style: HuddlText.caption(color: HuddlColors.neutral300),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
        },
          ),
        ),
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _Prediction {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  const _Prediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  factory _Prediction.fromJson(Map<String, dynamic> j) {
    final st = j['structured_formatting'] as Map<String, dynamic>? ?? {};
    return _Prediction(
      placeId: j['place_id'] as String? ?? '',
      description: j['description'] as String? ?? '',
      mainText: st['main_text'] as String? ?? j['description'] as String? ?? '',
      secondaryText: st['secondary_text'] as String? ?? '',
    );
  }
}
