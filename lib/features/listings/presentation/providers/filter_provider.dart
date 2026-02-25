import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Sort options ───────────────────────────────────────────────────────────

enum SortOption {
  newest('Newest'),
  priceAsc('Price: Low to High'),
  priceDesc('Price: High to Low'),
  rating('Top Rated');

  const SortOption(this.label);
  final String label;
}

// ─── Active chip model ──────────────────────────────────────────────────────

/// A single visible filter badge rendered above the results grid.
/// [key] uniquely identifies the chip so it can be removed individually.
@immutable
class FilterChipData {
  final String key;
  final String label;
  const FilterChipData({required this.key, required this.label});
}

// ─── Sentinel ───────────────────────────────────────────────────────────────
// Used in copyWith to distinguish "set to null" from "keep existing value"
// for the nullable voice-filter fields.

const _keep = Object();

// ─── Helpers ────────────────────────────────────────────────────────────────

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ─── Filter state ───────────────────────────────────────────────────────────

@immutable
class AdvancedFilterState {
  static const double kMinPrice = 0;
  static const double kMaxPrice = 500;
  static const double kMaxDistance = 100;

  // ── Manual filter fields (set by the filter sheet UI) ──────────────────────

  /// Multi-selected clothing/shoe sizes (e.g. {'S', 'M'}).
  final Set<String> sizes;

  /// Price-per-day range in GBP.
  final RangeValues priceRange;

  /// Maximum rental pickup distance in km.
  final double maxDistanceKm;

  /// Current sort order applied to the results grid.
  final SortOption sortBy;

  // ── Voice-search filter fields ──────────────────────────────────────────────
  // Populated by [AdvancedFilterNotifier.applyVoiceSearchFilters] whenever
  // the Cloud Function processVoiceSearch returns a `type: "results"` response.
  // These map 1-to-1 to the `attributes` object in the function's JSON payload:
  //
  //   attributes.style            → style
  //   attributes.color            → color
  //   attributes.occasion         → occasion
  //   attributes.specific_features → specificFeatures

  /// Fashion style extracted by AI (e.g. "elegant", "bohemian", "floral").
  final String? style;

  /// Colour extracted by AI (e.g. "red", "black", "multicolor").
  final String? color;

  /// Occasion extracted by AI (e.g. "wedding", "party", "office").
  final String? occasion;

  /// Specific garment features extracted by AI (e.g. ["midi", "sleeveless"]).
  final List<String> specificFeatures;

  const AdvancedFilterState({
    this.sizes = const {},
    this.priceRange = const RangeValues(kMinPrice, kMaxPrice),
    this.maxDistanceKm = kMaxDistance,
    this.sortBy = SortOption.newest,
    this.style,
    this.color,
    this.occasion,
    this.specificFeatures = const [],
  });

  /// Returns a copy with the given fields replaced.
  ///
  /// For the nullable voice-filter fields ([style], [color], [occasion]),
  /// pass `null` explicitly to clear the field, or omit the argument to
  /// keep the existing value.
  AdvancedFilterState copyWith({
    Set<String>? sizes,
    RangeValues? priceRange,
    double? maxDistanceKm,
    SortOption? sortBy,
    Object? style = _keep,
    Object? color = _keep,
    Object? occasion = _keep,
    List<String>? specificFeatures,
  }) =>
      AdvancedFilterState(
        sizes: sizes ?? this.sizes,
        priceRange: priceRange ?? this.priceRange,
        maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
        sortBy: sortBy ?? this.sortBy,
        style: identical(style, _keep) ? this.style : style as String?,
        color: identical(color, _keep) ? this.color : color as String?,
        occasion:
            identical(occasion, _keep) ? this.occasion : occasion as String?,
        specificFeatures: specificFeatures ?? this.specificFeatures,
      );

  // ── Computed properties ─────────────────────────────────────────────────────

  /// True when any filter — manual or AI-derived — deviates from defaults.
  bool get hasActiveFilters =>
      sizes.isNotEmpty ||
      priceRange.start > kMinPrice ||
      priceRange.end < kMaxPrice ||
      maxDistanceKm < kMaxDistance ||
      sortBy != SortOption.newest ||
      hasVoiceFilters;

  /// True when at least one AI-derived voice filter is set.
  /// Useful for showing a "Clear AI filters" affordance separately from
  /// the "Clear all" button.
  bool get hasVoiceFilters =>
      style != null ||
      color != null ||
      occasion != null ||
      specificFeatures.isNotEmpty;

  /// Ordered list of chip badges to render above the results grid.
  ///
  /// Voice-search chips appear first (they are more specific and contextual),
  /// followed by manual filter chips.
  List<FilterChipData> get activeChips {
    final chips = <FilterChipData>[];

    // ── Voice-search chips ──────────────────────────────────────────────────
    // Keys are prefixed with "voice_" to distinguish them from manual chips
    // in [AdvancedFilterNotifier.removeChip].

    if (style != null) {
      chips.add(FilterChipData(
        key: 'voice_style',
        label: 'Style: ${_capitalize(style!)}',
      ));
    }
    if (color != null) {
      chips.add(FilterChipData(
        key: 'voice_color',
        label: 'Color: ${_capitalize(color!)}',
      ));
    }
    if (occasion != null) {
      chips.add(FilterChipData(
        key: 'voice_occasion',
        label: 'Occasion: ${_capitalize(occasion!)}',
      ));
    }
    for (final feature in specificFeatures) {
      chips.add(FilterChipData(
        key: 'voice_feature_$feature',
        label: _capitalize(feature),
      ));
    }

    // ── Manual filter chips ─────────────────────────────────────────────────

    final sortedSizes = sizes.toList()..sort();
    for (final size in sortedSizes) {
      chips.add(FilterChipData(key: 'size_$size', label: 'Size: $size'));
    }

    if (priceRange.start > kMinPrice || priceRange.end < kMaxPrice) {
      chips.add(FilterChipData(
        key: 'price',
        label: '£${priceRange.start.toInt()}–£${priceRange.end.toInt()}',
      ));
    }

    if (maxDistanceKm < kMaxDistance) {
      chips.add(FilterChipData(
        key: 'distance',
        label: '≤ ${maxDistanceKm.toInt()} km',
      ));
    }

    if (sortBy != SortOption.newest) {
      chips.add(FilterChipData(key: 'sort', label: sortBy.label));
    }

    return chips;
  }
}

// ─── Notifier ───────────────────────────────────────────────────────────────

class AdvancedFilterNotifier extends Notifier<AdvancedFilterState> {
  @override
  AdvancedFilterState build() => const AdvancedFilterState();

  // ── Manual filter mutations ─────────────────────────────────────────────────

  void toggleSize(String size) {
    final updated = Set<String>.from(state.sizes);
    if (updated.contains(size)) {
      updated.remove(size);
    } else {
      updated.add(size);
    }
    state = state.copyWith(sizes: updated);
  }

  void setPriceRange(RangeValues range) =>
      state = state.copyWith(priceRange: range);

  void setMaxDistance(double km) =>
      state = state.copyWith(maxDistanceKm: km);

  void setSortBy(SortOption sort) => state = state.copyWith(sortBy: sort);

  // ── Chip removal ────────────────────────────────────────────────────────────

  /// Removes a single active filter chip identified by [key].
  /// Handles both voice-search chips (prefixed "voice_") and manual chips.
  void removeChip(String key) {
    if (key == 'voice_style') {
      state = state.copyWith(style: null);
    } else if (key == 'voice_color') {
      state = state.copyWith(color: null);
    } else if (key == 'voice_occasion') {
      state = state.copyWith(occasion: null);
    } else if (key.startsWith('voice_feature_')) {
      final feature = key.substring('voice_feature_'.length);
      state = state.copyWith(
        specificFeatures:
            state.specificFeatures.where((f) => f != feature).toList(),
      );
    } else if (key.startsWith('size_')) {
      final size = key.substring(5);
      final updated = Set<String>.from(state.sizes)..remove(size);
      state = state.copyWith(sizes: updated);
    } else if (key == 'price') {
      state = state.copyWith(
        priceRange: const RangeValues(
          AdvancedFilterState.kMinPrice,
          AdvancedFilterState.kMaxPrice,
        ),
      );
    } else if (key == 'distance') {
      state = state.copyWith(maxDistanceKm: AdvancedFilterState.kMaxDistance);
    } else if (key == 'sort') {
      state = state.copyWith(sortBy: SortOption.newest);
    }
  }

  // ── Bulk mutations ──────────────────────────────────────────────────────────

  /// Resets every filter — manual and AI-derived — to defaults.
  void clearAll() => state = const AdvancedFilterState();

  /// Clears only AI-derived voice filters, leaving manual filters intact.
  /// Useful when the user wants to wipe the AI context but keep their
  /// manually set price range, sizes, etc.
  void clearVoiceFilters() => state = state.copyWith(
        style: null,
        color: null,
        occasion: null,
        specificFeatures: const [],
      );

  /// Atomically replaces the entire state with [draft].
  /// Used by the filter sheet's "Apply" button after the user has
  /// interacted with sliders and toggles on the draft copy.
  void applyDraft(AdvancedFilterState draft) => state = draft;

  // ── Voice-search integration ────────────────────────────────────────────────

  /// Applies the `attributes` map from a `processVoiceSearch` Cloud Function
  /// response directly into the filter state.
  ///
  /// **Usage** — call this immediately after receiving a `type: "results"`
  /// response from the function:
  ///
  /// ```dart
  /// // In your screen or notifier, after calling the Cloud Function:
  /// final data = result.data as Map<String, dynamic>;
  ///
  /// if (data['type'] == 'results') {
  ///   final attrs = data['attributes'] as Map<String, dynamic>;
  ///   ref.read(advancedFilterProvider.notifier).applyVoiceSearchFilters(attrs);
  ///
  ///   // Category is managed by selectedCategoryProvider — update it separately:
  ///   final category = attrs['category'] as String?;
  ///   if (category != null) {
  ///     ref.read(selectedCategoryProvider.notifier).state = category;
  ///   }
  /// }
  /// ```
  ///
  /// **Contract** — the [attributes] map must match the `ParsedAttributes`
  /// interface returned by `processVoiceSearch`:
  ///
  /// ```json
  /// {
  ///   "category":          "dress" | "shoes" | "bag" | null,
  ///   "style":             string | null,
  ///   "color":             string | null,
  ///   "occasion":          string | null,
  ///   "specific_features": string[]
  /// }
  /// ```
  ///
  /// Manual filters ([sizes], [priceRange], [maxDistanceKm], [sortBy]) are
  /// intentionally preserved — this method only updates the AI-derived fields.
  void applyVoiceSearchFilters(Map<String, dynamic> attributes) {
    final features = (attributes['specific_features'] as List<dynamic>?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];

    state = state.copyWith(
      style: attributes['style'] as String?,
      color: attributes['color'] as String?,
      occasion: attributes['occasion'] as String?,
      specificFeatures: features,
    );
  }
}

// ─── Provider ───────────────────────────────────────────────────────────────

final advancedFilterProvider =
    NotifierProvider<AdvancedFilterNotifier, AdvancedFilterState>(
  AdvancedFilterNotifier.new,
);
