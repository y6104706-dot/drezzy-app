import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/filter_provider.dart';
import '../providers/listings_provider.dart';

// ─── Size options (canonical order) ───────────────────────────────────────

const _sizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL'];

const _categoryOptions = {
  '': 'All',
  'dress': 'Dresses',
  'shoes': 'Shoes',
  'bag': 'Bags',
  'accessory': 'Accessories',
};

// ─── Entry point ──────────────────────────────────────────────────────────

/// Opens the advanced filter sheet using the current [WidgetRef].
void showFilterSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ProviderScope(
      // Inherit the parent scope so the sheet can read and write providers.
      parent: ProviderScope.containerOf(context),
      child: const _FilterSheet(),
    ),
  );
}

// ─── Sheet root ────────────────────────────────────────────────────────────

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  // Local draft — only written to providers when "Apply" is tapped.
  late String _category;
  late AdvancedFilterState _draft;

  @override
  void initState() {
    super.initState();
    _category = ref.read(selectedCategoryProvider);
    _draft = ref.read(advancedFilterProvider);
  }

  void _apply() {
    ref.read(selectedCategoryProvider.notifier).state = _category;
    ref.read(advancedFilterProvider.notifier).applyDraft(_draft);
    Navigator.of(context).pop();
  }

  void _clearAll() {
    setState(() {
      _category = '';
      _draft = const AdvancedFilterState();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ─────────────────────────────────────────────────
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header row ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 16, 4),
            child: Row(
              children: [
                Text('FILTERS',
                    style: text.titleMedium?.copyWith(
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w700,
                    )),
                const Spacer(),
                TextButton(
                  onPressed: _clearAll,
                  child: Text(
                    'CLEAR ALL',
                    style: text.labelSmall?.copyWith(
                      color: DrezzyColors.champagneGold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Scrollable body ─────────────────────────────────────────────
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.72,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _divider(),
                  _sectionLabel('CATEGORY'),
                  const SizedBox(height: 12),
                  _CategorySection(
                    selected: _category,
                    onChanged: (v) => setState(() => _category = v),
                  ),
                  _divider(),
                  _sectionLabel('SIZE'),
                  const SizedBox(height: 12),
                  _SizeSection(
                    selected: _draft.sizes,
                    onToggle: (size) => setState(
                      () => _draft = _draft.copyWith(
                        sizes: Set.from(_draft.sizes)..toggle(size),
                      ),
                    ),
                  ),
                  _divider(),
                  _sectionLabel('PRICE RANGE'),
                  const SizedBox(height: 4),
                  _PriceRangeSection(
                    range: _draft.priceRange,
                    onChanged: (r) =>
                        setState(() => _draft = _draft.copyWith(priceRange: r)),
                  ),
                  _divider(),
                  _sectionLabel('DISTANCE'),
                  const SizedBox(height: 4),
                  _DistanceSection(
                    value: _draft.maxDistanceKm,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(maxDistanceKm: v),
                    ),
                  ),
                  _divider(),
                  _sectionLabel('SORT BY'),
                  const SizedBox(height: 8),
                  _SortSection(
                    selected: _draft.sortBy,
                    onChanged: (s) =>
                        setState(() => _draft = _draft.copyWith(sortBy: s)),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // ── Apply button ────────────────────────────────────────────────
          _ApplyButton(onTap: _apply),
        ],
      ),
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Divider(
          height: 0,
          thickness: 0.5,
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      );

  Widget _sectionLabel(String label) => Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.7),
              letterSpacing: 2.0,
              fontSize: 10,
            ),
      );
}

// ─── Category section ──────────────────────────────────────────────────────

class _CategorySection extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _CategorySection(
      {required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _categoryOptions.entries.map((e) {
        return _Chip(
          label: e.value,
          selected: selected == e.key,
          onTap: () => onChanged(e.key),
        );
      }).toList(),
    );
  }
}

// ─── Size section ──────────────────────────────────────────────────────────

class _SizeSection extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const _SizeSection({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _sizes
          .map(
            (s) => _Chip(
              label: s,
              selected: selected.contains(s),
              onTap: () => onToggle(s),
            ),
          )
          .toList(),
    );
  }
}

// ─── Price range section ────────────────────────────────────────────────────

class _PriceRangeSection extends StatelessWidget {
  final RangeValues range;
  final ValueChanged<RangeValues> onChanged;
  const _PriceRangeSection({required this.range, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '£${range.start.toInt()}',
              style: text.labelMedium
                  ?.copyWith(color: DrezzyColors.champagneGold),
            ),
            Text(
              '£${range.end.toInt()}',
              style: text.labelMedium
                  ?.copyWith(color: DrezzyColors.champagneGold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: _sliderTheme(context),
          child: RangeSlider(
            values: range,
            min: AdvancedFilterState.kMinPrice,
            max: AdvancedFilterState.kMaxPrice,
            divisions: 50,
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('£0', style: _captionStyle(context)),
            Text('£500', style: _captionStyle(context)),
          ],
        ),
      ],
    );
  }
}

// ─── Distance section ───────────────────────────────────────────────────────

class _DistanceSection extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _DistanceSection({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.location_on_rounded,
                size: 14, color: DrezzyColors.champagneGold),
            const SizedBox(width: 4),
            Text(
              value >= AdvancedFilterState.kMaxDistance
                  ? 'Any distance'
                  : 'Within ${value.toInt()} km',
              style: text.labelMedium
                  ?.copyWith(color: DrezzyColors.champagneGold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: _sliderTheme(context),
          child: Slider(
            value: value,
            min: 5,
            max: AdvancedFilterState.kMaxDistance,
            divisions: 19,
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('5 km', style: _captionStyle(context)),
            Text('Any', style: _captionStyle(context)),
          ],
        ),
      ],
    );
  }
}

// ─── Sort section ───────────────────────────────────────────────────────────

class _SortSection extends StatelessWidget {
  final SortOption selected;
  final ValueChanged<SortOption> onChanged;
  const _SortSection({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: SortOption.values.map((opt) {
        final isSelected = opt == selected;
        return InkWell(
          onTap: () => onChanged(opt),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                // Custom radio circle
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? DrezzyColors.champagneGold
                          : colors.outlineVariant,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: DrezzyColors.champagneGold,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Text(
                  opt.label,
                  style: text.bodyMedium?.copyWith(
                    color: isSelected
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Apply button ────────────────────────────────────────────────────────────

class _ApplyButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ApplyButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottom),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: DrezzyColors.champagneGold,
            foregroundColor: DrezzyColors.nearBlack,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            textStyle: Theme.of(context).textTheme.labelLarge,
          ),
          child: const Text('APPLY FILTERS'),
        ),
      ),
    );
  }
}

// ─── Shared selectable chip ───────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? DrezzyColors.champagneGold.withValues(alpha: 0.18)
              : colors.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: selected
                ? DrezzyColors.champagneGold.withValues(alpha: 0.75)
                : colors.outlineVariant.withValues(alpha: 0.45),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: text.labelMedium?.copyWith(
            color: selected
                ? DrezzyColors.champagneGold
                : colors.onSurfaceVariant,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

SliderThemeData _sliderTheme(BuildContext context) =>
    SliderTheme.of(context).copyWith(
      activeTrackColor: DrezzyColors.champagneGold,
      inactiveTrackColor:
          DrezzyColors.champagneGold.withValues(alpha: 0.18),
      thumbColor: DrezzyColors.champagneGold,
      overlayColor: DrezzyColors.champagneGold.withValues(alpha: 0.12),
      activeTickMarkColor: Colors.transparent,
      inactiveTickMarkColor: Colors.transparent,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      trackHeight: 2,
    );

TextStyle? _captionStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.5),
          fontSize: 10,
        );

// ─── Set toggle extension ─────────────────────────────────────────────────────

extension _SetToggle<T> on Set<T> {
  void toggle(T value) {
    if (contains(value)) {
      remove(value);
    } else {
      add(value);
    }
  }
}
