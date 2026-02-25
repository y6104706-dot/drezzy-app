import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../../features/ai_services/presentation/providers/voice_search_provider.dart';
import '../../../../features/ai_services/presentation/widgets/voice_stylist_overlay.dart';
import '../providers/filter_provider.dart';
import '../providers/listings_provider.dart';
import '../widgets/filter_bottom_sheet.dart';
import '../widgets/listing_card.dart';
import '../../../../core/services/cloud_functions_service.dart';

// ── Face Swap PoC ─────────────────────────────────────────────────────────────
// TODO(dev): Remove this block once a real Create Listing flow is implemented.
// These constants feed the developer Proof-of-Concept FAB below.
const _kPocListingId = 'lst_001';
const _kPocListingTitle = 'Midnight Silk Gown';
const _kPocOriginalImageUrl =
    'https://images.unsplash.com/photo-1566174053879-31528523f8ae'
    '?auto=format&fit=crop&w=600&q=80';
// Public Unsplash portrait used as the «face-donor selfie» in the PoC test.
const _kPocDonorFaceUrl =
    'https://images.unsplash.com/photo-1534528741775-53994a69daeb'
    '?auto=format&fit=crop&w=400&q=80';

// ─── Category tab constants ─────────────────────────────────────────────────

class _Category {
  final String label;
  final String value;
  final IconData icon;
  const _Category(this.label, this.value, this.icon);
}

const _categories = [
  _Category('All', '', Icons.auto_awesome_rounded),
  _Category('Dresses', 'dress', Icons.checkroom_rounded),
  _Category('Shoes', 'shoes', Icons.ice_skating_rounded),
  _Category('Bags', 'bag', Icons.shopping_bag_outlined),
  _Category('Accessories', 'accessory', Icons.diamond_outlined),
];

// ─── Screen ─────────────────────────────────────────────────────────────────

class DiscoveryFeedScreen extends ConsumerStatefulWidget {
  const DiscoveryFeedScreen({super.key});

  @override
  ConsumerState<DiscoveryFeedScreen> createState() =>
      _DiscoveryFeedScreenState();
}

class _DiscoveryFeedScreenState extends ConsumerState<DiscoveryFeedScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _headerElevated = false;

  // TODO(dev): Remove — PoC only.
  bool _pocLoading = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final elevated = _scrollController.offset > 2;
      if (elevated != _headerElevated) {
        setState(() => _headerElevated = elevated);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Face Swap PoC ───────────────────────────────────────────────────────────
  // TODO(dev): Remove — temporary developer test mechanism.

  Future<void> _runFaceSwapPoc() async {
    if (_pocLoading) return;
    setState(() => _pocLoading = true);

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 120),
        backgroundColor: DrezzyColors.nearBlack,
        behavior: SnackBarBehavior.floating,
        // Raised above the FAB so they don't overlap.
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: DrezzyColors.champagneGold.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: DrezzyColors.champagneGold,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                '✨  Drezzy AI is processing — InsightFace via Replicate (~60 s)',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final result = await ref
          .read(cloudFunctionsServiceProvider)
          .generateFaceSwap(
            listingId: _kPocListingId,
            imageUrl: _kPocDonorFaceUrl,
          );

      messenger.hideCurrentSnackBar();
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => _FaceSwapResultDialog(
          resultUrl: result.displayImageUrl,
          listingTitle: _kPocListingTitle,
          originalUrl: _kPocOriginalImageUrl,
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => _FaceSwapErrorDialog(details: e.toString()),
      );
    } finally {
      if (mounted) setState(() => _pocLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // ── Voice search listener ───────────────────────────────────────────────
    ref.listen<VoiceSearchState>(voiceSearchProvider, (_, next) {
      if (next.status == VoiceStatus.done &&
          next.finalTranscript.isNotEmpty) {
        // Populate the search bar — this triggers the local mock filter.
        // TTS is now fired inside VoiceSearchNotifier with Gemini's own
        // conversational_response, so we do NOT call TtsService here.
        _searchController.text = next.finalTranscript;
        ref.read(searchQueryProvider.notifier).state = next.finalTranscript;

        // Apply AI-extracted filter attributes to the grid.
        // Both VoiceSearchResults and VoiceSearchNoResults carry a
        // ParsedAttributes object — apply them so the chip bar reflects
        // what Gemini understood, even when zero listings matched.
        final result = next.cloudSearchResult;
        ParsedAttributes? attrs;
        if (result is VoiceSearchResults) {
          attrs = result.attributes;
        } else if (result is VoiceSearchNoResults) {
          attrs = result.attributes;
        }
        if (attrs != null) {
          ref
              .read(advancedFilterProvider.notifier)
              .applyVoiceSearchFilters({
                'style': attrs.style,
                'color': attrs.color,
                'occasion': attrs.occasion,
                'specific_features': attrs.specificFeatures,
              });
          if (attrs.category != null) {
            ref.read(selectedCategoryProvider.notifier).state =
                attrs.category!;
          }
        }

        // Let the overlay finish its exit animation before resetting state.
        Future.delayed(const Duration(milliseconds: 120), () {
          ref.read(voiceSearchProvider.notifier).reset();
        });
      } else if (next.status == VoiceStatus.clarifying) {
        // Gemini asked a follow-up question.
        // The overlay shows the question text and TTS speaks it.
        // We do not update the search bar — no search was performed yet.
        // Reset state once TTS has had time to finish (~3 s),
        // so the user can tap the mic again to answer.
        Future.delayed(const Duration(milliseconds: 3500), () {
          ref.read(voiceSearchProvider.notifier).reset();
        });
      }
    });

    return Scaffold(
      backgroundColor: colors.surface,
      // TODO(dev): Remove FAB once PoC is verified.
      floatingActionButton: _PocFab(
        isLoading: _pocLoading,
        onPressed: _runFaceSwapPoc,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Sticky header ───────────────────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: colors.surface,
                boxShadow: _headerElevated
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TopBar(),
                  const SizedBox(height: 12),
                  _SearchBar(controller: _searchController),
                  const SizedBox(height: 12),
                  _CategoryChips(),
                  // Active filter chips — animates in/out
                  _ActiveFilterChips(),
                  const SizedBox(height: 4),
                ],
              ),
            ),

            // ── Grid ────────────────────────────────────────────────────────
            Expanded(
              child: _GridArea(scrollController: _scrollController),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Top bar ────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'DREZZY',
            style: text.titleLarge?.copyWith(
              letterSpacing: 5,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {},
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.notifications_none_rounded,
                    color: colors.onSurface, size: 24),
                Positioned(
                  top: -1,
                  right: -1,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: DrezzyColors.champagneGold,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4),
            child: CircleAvatar(
              radius: 16,
              backgroundColor:
                  DrezzyColors.champagneGold.withValues(alpha: 0.15),
              child: const Icon(
                Icons.person_outline_rounded,
                size: 18,
                color: DrezzyColors.champagneGold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Search bar ──────────────────────────────────────────────────────────────

class _SearchBar extends ConsumerWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final voiceStatus =
        ref.watch(voiceSearchProvider.select((s) => s.status));
    final micActive = voiceStatus == VoiceStatus.listening ||
        voiceStatus == VoiceStatus.initializing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // ── Text field ──────────────────────────────────────────────────
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 46,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: micActive
                      ? DrezzyColors.champagneGold.withValues(alpha: 0.6)
                      : colors.outlineVariant.withValues(alpha: 0.4),
                  width: micActive ? 1.0 : 0.5,
                ),
              ),
              child: TextField(
                controller: controller,
                onChanged: (v) =>
                    ref.read(searchQueryProvider.notifier).state = v,
                style: text.bodyMedium?.copyWith(color: colors.onSurface),
                decoration: InputDecoration(
                  hintText: 'Search for your dream dress...',
                  hintStyle: text.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 18, color: colors.onSurfaceVariant),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (ctx, value, __) {
                      if (value.text.isNotEmpty) {
                        return GestureDetector(
                          onTap: () {
                            controller.clear();
                            ref
                                .read(searchQueryProvider.notifier)
                                .state = '';
                          },
                          child: Icon(Icons.close_rounded,
                              size: 16, color: colors.onSurfaceVariant),
                        );
                      }
                      return _MicButton(
                        isActive: micActive,
                        onTap: () async =>
                            VoiceStylistOverlay.show(ctx),
                      );
                    },
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // ── Filter / Tune button ────────────────────────────────────────
          _FilterButton(),
        ],
      ),
    );
  }
}

// ─── Mic button ─────────────────────────────────────────────────────────────

class _MicButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  const _MicButton({required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? DrezzyColors.champagneGold.withValues(alpha: 0.15)
                : Colors.transparent,
            border: isActive
                ? Border.all(
                    color: DrezzyColors.champagneGold.withValues(alpha: 0.5))
                : null,
          ),
          child: Icon(
            isActive ? Icons.mic_rounded : Icons.mic_none_rounded,
            size: 17,
            color: isActive
                ? DrezzyColors.champagneGold
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ─── Filter / Tune button ────────────────────────────────────────────────────

class _FilterButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Show a gold dot whenever any advanced filter or category is active.
    final hasFilters = ref.watch(
      advancedFilterProvider.select((s) => s.hasActiveFilters),
    );
    final hasCategory =
        ref.watch(selectedCategoryProvider.select((c) => c.isNotEmpty));
    final showDot = hasFilters || hasCategory;

    return GestureDetector(
      onTap: () => showFilterSheet(context, ref),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          border: Border.all(
            color: showDot
                ? DrezzyColors.champagneGold.withValues(alpha: 0.8)
                : DrezzyColors.champagneGold.withValues(alpha: 0.5),
            width: showDot ? 1.2 : 0.8,
          ),
          borderRadius: BorderRadius.circular(4),
          color: showDot
              ? DrezzyColors.champagneGold.withValues(alpha: 0.14)
              : DrezzyColors.champagneGold.withValues(alpha: 0.07),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.tune_rounded,
                size: 20, color: DrezzyColors.champagneGold),
            if (showDot)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: DrezzyColors.champagneGold,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Category chips ──────────────────────────────────────────────────────────

class _CategoryChips extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedCategoryProvider);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = _categories[i];
          final isSelected = cat.value == selected;
          return GestureDetector(
            onTap: () =>
                ref.read(selectedCategoryProvider.notifier).state =
                    cat.value,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? DrezzyColors.champagneGold.withValues(alpha: 0.18)
                    : colors.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: isSelected
                      ? DrezzyColors.champagneGold.withValues(alpha: 0.7)
                      : colors.outlineVariant.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(cat.icon,
                      size: 12,
                      color: isSelected
                          ? DrezzyColors.champagneGold
                          : colors.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text(
                    cat.label,
                    style: text.labelMedium?.copyWith(
                      color: isSelected
                          ? DrezzyColors.champagneGold
                          : colors.onSurfaceVariant,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Active filter chips row ─────────────────────────────────────────────────

class _ActiveFilterChips extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chips = ref.watch(activeFilterChipsProvider);

    // AnimatedSize smoothly opens / closes the row.
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: chips.isEmpty
          ? const SizedBox(width: double.infinity)
          : SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                itemCount: chips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final chip = chips[i];
                  return _ActiveChipBadge(
                    chip: chip,
                    onRemove: () {
                      if (chip.key == 'category') {
                        ref
                            .read(selectedCategoryProvider.notifier)
                            .state = '';
                      } else {
                        ref
                            .read(advancedFilterProvider.notifier)
                            .removeChip(chip.key);
                      }
                    },
                  );
                },
              ),
            ),
    );
  }
}

class _ActiveChipBadge extends StatelessWidget {
  final FilterChipData chip;
  final VoidCallback onRemove;
  const _ActiveChipBadge({required this.chip, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: DrezzyColors.champagneGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: DrezzyColors.champagneGold.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            chip.label,
            style: text.labelSmall?.copyWith(
              color: DrezzyColors.champagneGold,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close_rounded,
              size: 13,
              color: DrezzyColors.champagneGold.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

// ─── Grid area ───────────────────────────────────────────────────────────────

class _GridArea extends ConsumerWidget {
  final ScrollController scrollController;
  const _GridArea({required this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(filteredListingsProvider);
    return listingsAsync.when(
      loading: () => _SkeletonGrid(scrollController: scrollController),
      error: (err, _) => _ErrorState(message: err.toString()),
      data: (listings) => listings.isEmpty
          ? const _EmptyState()
          : _ListingsGrid(
              listings: listings,
              scrollController: scrollController,
            ),
    );
  }
}

// ── Real grid ────────────────────────────────────────────────────────────────

class _ListingsGrid extends StatelessWidget {
  final List listings;
  final ScrollController scrollController;
  const _ListingsGrid(
      {required this.listings, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.66,
      ),
      itemCount: listings.length,
      itemBuilder: (context, i) => ListingCard(
        listing: listings[i],
        onTap: () => context.push(
          AppRoutes.listingDetailPath(listings[i].id),
          extra: listings[i],
        ),
      ),
    );
  }
}

// ── Skeleton grid ─────────────────────────────────────────────────────────────

class _SkeletonGrid extends StatelessWidget {
  final ScrollController scrollController;
  const _SkeletonGrid({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.66,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => const ListingCardSkeleton(),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 48,
                color: DrezzyColors.champagneGold.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('No results found',
                style: text.titleMedium?.copyWith(color: colors.onSurface),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Try a different search or adjust your filters.',
                style: text.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ── Error state ────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 40, color: DrezzyColors.error),
            const SizedBox(height: 12),
            Text('Something went wrong',
                style: text.titleMedium?.copyWith(color: colors.onSurface)),
            const SizedBox(height: 6),
            Text(message,
                style: text.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PoC widgets — TODO(dev): remove once Create Listing flow is shipped.
// ─────────────────────────────────────────────────────────────────────────────

// ── FAB ───────────────────────────────────────────────────────────────────────

class _PocFab extends StatelessWidget {
  const _PocFab({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: isLoading ? null : onPressed,
      backgroundColor: DrezzyColors.nearBlack,
      foregroundColor: DrezzyColors.champagneGold,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: DrezzyColors.champagneGold.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      icon: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: DrezzyColors.champagneGold,
              ),
            )
          : const Icon(Icons.auto_awesome_rounded, size: 20),
      label: Text(
        isLoading ? 'Processing…' : 'Face Swap PoC',
        style: const TextStyle(
          letterSpacing: 1,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ── Result dialog ─────────────────────────────────────────────────────────────

class _FaceSwapResultDialog extends StatelessWidget {
  const _FaceSwapResultDialog({
    required this.resultUrl,
    required this.listingTitle,
    required this.originalUrl,
  });

  final String resultUrl;
  final String listingTitle;
  final String originalUrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header band ────────────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: DrezzyColors.champagneGold.withValues(alpha: 0.10),
                border: Border(
                  bottom: BorderSide(
                    color: DrezzyColors.champagneGold.withValues(alpha: 0.22),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: DrezzyColors.champagneGold,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'FACE SWAP',
                    style: tt.labelLarge?.copyWith(
                      color: DrezzyColors.champagneGold,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  // "PoC" badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: DrezzyColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: DrezzyColors.success.withValues(alpha: 0.45),
                        width: 0.5,
                      ),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: DrezzyColors.success,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Before / After image strip ──────────────────────────────────────
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Row(
                children: [
                  // Before
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          originalUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const ColoredBox(color: DrezzyColors.charcoal),
                        ),
                        const Positioned(
                          bottom: 6,
                          left: 6,
                          child: _ImageLabel(label: 'BEFORE', isAfter: false),
                        ),
                      ],
                    ),
                  ),
                  // Divider
                  Container(
                    width: 1.5,
                    color:
                        DrezzyColors.champagneGold.withValues(alpha: 0.4),
                  ),
                  // After (AI result)
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          resultUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return const ColoredBox(
                              color: DrezzyColors.charcoal,
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: DrezzyColors.champagneGold,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: DrezzyColors.charcoal,
                            child: Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: DrezzyColors.champagneGold,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                        const Positioned(
                          bottom: 6,
                          right: 6,
                          child: _ImageLabel(label: 'AFTER', isAfter: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Footer ─────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listingTitle,
                    style: tt.titleSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Lender identity anonymised by InsightFace · Replicate API',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Result URL chip
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest
                          .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      resultUrl.length > 58
                          ? '${resultUrl.substring(0, 58)}…'
                          : resultUrl,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9.5,
                        color: DrezzyColors.champagneGold,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: DrezzyColors.champagneGold,
                        foregroundColor: DrezzyColors.nearBlack,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'CLOSE',
                        style: TextStyle(
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Before / After label badge ────────────────────────────────────────────────

class _ImageLabel extends StatelessWidget {
  const _ImageLabel({required this.label, required this.isAfter});

  final String label;
  final bool isAfter;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xCC000000), // black ~80% opacity
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            color: isAfter ? DrezzyColors.champagneGold : Colors.white70,
            fontSize: 9,
            fontWeight: isAfter ? FontWeight.w700 : FontWeight.w400,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}

// ── Error dialog ──────────────────────────────────────────────────────────────

class _FaceSwapErrorDialog extends StatelessWidget {
  const _FaceSwapErrorDialog({required this.details});

  final String details;

  static const _steps = [
    'Run  flutterfire configure  to link your Firebase project',
    'Deploy: firebase deploy --only functions',
    "Create a listing in Firestore with document id 'lst_001'",
    'Fill in REPLICATE_API_TOKEN in functions/.env and redeploy',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          const Icon(
            Icons.construction_rounded,
            color: DrezzyColors.champagneGold,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'CF Not Ready',
              style: tt.titleMedium?.copyWith(color: cs.onSurface),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The generateFaceSwap Cloud Function call was not successful.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            // Error details
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: DrezzyColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: DrezzyColors.error.withValues(alpha: 0.25),
                  width: 0.5,
                ),
              ),
              child: Text(
                details.length > 220
                    ? '${details.substring(0, 220)}…'
                    : details,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  height: 1.55,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'To run this PoC end-to-end:',
              style: tt.labelMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ..._steps.map(
              (step) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.arrow_right_rounded,
                      size: 14,
                      color: DrezzyColors.champagneGold,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        step,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'DISMISS',
            style: TextStyle(
              color: DrezzyColors.champagneGold,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
