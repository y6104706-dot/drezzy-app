import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/listing_model.dart';
import 'filter_provider.dart';

// ─── UI State ─────────────────────────────────────────────────────────────

/// Currently active category filter. Empty string means "All".
final selectedCategoryProvider = StateProvider<String>((ref) => '');

/// Current search query string.
final searchQueryProvider = StateProvider<String>((ref) => '');

// ─── Data ─────────────────────────────────────────────────────────────────

/// All listings streamed from Firestore (currently mocked).
///
/// TODO: Replace with a real Firestore stream:
/// ```dart
/// final listingsProvider = StreamProvider<List<ListingModel>>((ref) {
///   return FirebaseFirestore.instance
///       .collection('listings')
///       .where('status', isEqualTo: 'active')
///       .orderBy('createdAt', descending: true)
///       .snapshots()
///       .map((snap) => snap.docs
///           .map((d) => ListingModel.fromMap(d.id, d.data()))
///           .toList());
/// });
/// ```
final listingsProvider = FutureProvider<List<ListingModel>>((ref) async {
  await Future<void>.delayed(const Duration(milliseconds: 2200));
  return _mockListings;
});

/// Master derived provider — applies category, text search, size, price
/// range, and sort order in memory. Distance is UI-only until GPS is wired.
final filteredListingsProvider =
    Provider<AsyncValue<List<ListingModel>>>((ref) {
  final listingsAsync = ref.watch(listingsProvider);
  final category = ref.watch(selectedCategoryProvider);
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final filters = ref.watch(advancedFilterProvider);

  return listingsAsync.whenData((listings) {
    var result = List<ListingModel>.from(listings);

    // ── Category ──────────────────────────────────────────────────────────
    if (category.isNotEmpty) {
      result = result.where((l) => l.category == category).toList();
    }

    // ── Text search ───────────────────────────────────────────────────────
    if (query.isNotEmpty) {
      result = result.where((l) {
        return l.title.toLowerCase().contains(query) ||
            l.description.toLowerCase().contains(query) ||
            l.brand.toLowerCase().contains(query) ||
            l.tags.any((t) => t.toLowerCase().contains(query));
      }).toList();
    }

    // ── Size ──────────────────────────────────────────────────────────────
    if (filters.sizes.isNotEmpty) {
      result =
          result.where((l) => filters.sizes.contains(l.size)).toList();
    }

    // ── Price range ───────────────────────────────────────────────────────
    result = result
        .where((l) =>
            l.pricePerDay >= filters.priceRange.start &&
            l.pricePerDay <= filters.priceRange.end)
        .toList();

    // ── Sort ──────────────────────────────────────────────────────────────
    switch (filters.sortBy) {
      case SortOption.newest:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case SortOption.priceAsc:
        result.sort((a, b) => a.pricePerDay.compareTo(b.pricePerDay));
      case SortOption.priceDesc:
        result.sort((a, b) => b.pricePerDay.compareTo(a.pricePerDay));
      case SortOption.rating:
        break; // rating field not in mock data yet
    }

    return result;
  });
});

/// Combined active-filter chips from both category + advanced filters.
/// Consumed by the active chips row above the grid.
final activeFilterChipsProvider = Provider<List<FilterChipData>>((ref) {
  final category = ref.watch(selectedCategoryProvider);
  final advanced = ref.watch(advancedFilterProvider);

  const _labels = {
    'dress': 'Dresses',
    'shoes': 'Shoes',
    'bag': 'Bags',
    'accessory': 'Accessories',
  };

  final chips = <FilterChipData>[];

  if (category.isNotEmpty) {
    chips.add(FilterChipData(
      key: 'category',
      label: _labels[category] ?? category,
    ));
  }

  chips.addAll(advanced.activeChips);
  return chips;
});

// ─── Mock Data ────────────────────────────────────────────────────────────

/// 10 realistic mock listings used during local development.
/// Replace with Firestore once Firebase is initialised.
final List<ListingModel> _mockListings = [
  ListingModel(
    id: 'lst_001',
    lenderId: 'user_a',
    title: 'Midnight Silk Gown',
    description:
        'Stunning floor-length midnight blue silk gown. Perfect for black-tie events.',
    category: 'dress',
    brand: 'Zimmermann',
    size: 'S',
    pricePerDay: 55,
    depositAmount: 280,
    imageUrls: [
      'https://images.unsplash.com/photo-1566174053879-31528523f8ae?auto=format&fit=crop&w=600&q=80',
    ],
    coverImageUrl:
        'https://images.unsplash.com/photo-1566174053879-31528523f8ae?auto=format&fit=crop&w=600&q=80',
    tags: ['gown', 'black-tie', 'silk', 'evening'],
    locationName: 'Tel Aviv',
    status: 'active',
    createdAt: DateTime(2026, 1, 10),
  ),
  ListingModel(
    id: 'lst_002',
    lenderId: 'user_b',
    title: 'Cherry Red Mini',
    description:
        'Bold cherry-red structured mini dress. Great for cocktail parties and date nights.',
    category: 'dress',
    brand: 'Self-Portrait',
    size: 'M',
    pricePerDay: 38,
    depositAmount: 190,
    imageUrls: [
      'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?auto=format&fit=crop&w=600&q=80',
    ],
    coverImageUrl:
        'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?auto=format&fit=crop&w=600&q=80',
    tags: ['mini', 'red', 'cocktail', 'party'],
    locationName: 'London',
    status: 'active',
    createdAt: DateTime(2026, 1, 15),
  ),
  ListingModel(
    id: 'lst_003',
    lenderId: 'user_c',
    title: 'Ivory Lace Midi',
    description:
        'Delicate ivory lace midi dress. Effortlessly romantic for garden parties or weddings.',
    category: 'dress',
    brand: 'Needle & Thread',
    size: 'S',
    pricePerDay: 42,
    depositAmount: 210,
    imageUrls: [
      'https://images.unsplash.com/photo-1539109136881-3be0616acf4b?auto=format&fit=crop&w=600&q=80',
    ],
    coverImageUrl:
        'https://images.unsplash.com/photo-1539109136881-3be0616acf4b?auto=format&fit=crop&w=600&q=80',
    tags: ['lace', 'ivory', 'wedding-guest', 'midi', 'romantic'],
    locationName: 'Paris',
    status: 'active',
    createdAt: DateTime(2026, 1, 18),
  ),
  ListingModel(
    id: 'lst_004',
    lenderId: 'user_d',
    title: 'Emerald Column Gown',
    description:
        'Sleek emerald green column gown with a low back. A red-carpet statement piece.',
    category: 'dress',
    brand: 'Galvan',
    size: 'M',
    pricePerDay: 68,
    depositAmount: 340,
    imageUrls: [
      'https://images.unsplash.com/photo-1490481651871-ab68de25d43d?auto=format&fit=crop&w=600&q=80',
    ],
    coverImageUrl:
        'https://images.unsplash.com/photo-1490481651871-ab68de25d43d?auto=format&fit=crop&w=600&q=80',
    tags: ['column', 'emerald', 'green', 'red-carpet', 'gown'],
    locationName: 'New York',
    status: 'active',
    createdAt: DateTime(2026, 1, 22),
  ),
  ListingModel(
    id: 'lst_005',
    lenderId: 'user_e',
    title: 'Floral Wrap Dress',
    description:
        'Vibrant floral print wrap dress. Light and airy for summer events or brunch.',
    category: 'dress',
    brand: 'Diane von Furstenberg',
    size: 'S',
    pricePerDay: 28,
    depositAmount: 140,
    imageUrls: [
      'https://images.unsplash.com/photo-1572804013309-59a88b7e92f1?auto=format&fit=crop&w=600&q=80',
    ],
    coverImageUrl:
        'https://images.unsplash.com/photo-1572804013309-59a88b7e92f1?auto=format&fit=crop&w=600&q=80',
    tags: ['floral', 'wrap', 'summer', 'brunch', 'casual'],
    locationName: 'Tel Aviv',
    status: 'active',
    createdAt: DateTime(2026, 1, 25),
  ),
  ListingModel(
    id: 'lst_006',
    lenderId: 'user_f',
    title: 'Black Power Blazer Dress',
    description:
        'Sharp tailored black blazer dress. Power dressing at its finest.',
    category: 'dress',
    brand: 'Alexander McQueen',
    size: 'L',
    pricePerDay: 75,
    depositAmount: 380,
    imageUrls: [
      'https://images.unsplash.com/photo-1554412933-514a83d2f3c8?auto=format&fit=crop&w=600&q=80',
    ],
    coverImageUrl:
        'https://images.unsplash.com/photo-1554412933-514a83d2f3c8?auto=format&fit=crop&w=600&q=80',
    tags: ['blazer', 'black', 'power-dressing', 'tailored', 'work'],
    locationName: 'London',
    status: 'active',
    createdAt: DateTime(2026, 2, 1),
  ),
  ListingModel(
    id: 'lst_007',
    lenderId: 'user_g',
    title: 'Gold Sequin Slip',
    description:
        "Slinky gold sequin slip dress. The ultimate New Year's Eve / party piece.",
    category: 'dress',
    brand: 'Retrofête',
    size: 'S',
    pricePerDay: 48,
    depositAmount: 240,
    imageUrls: [
      'https://images.unsplash.com/photo-1617019114583-affb34d1b3cd?auto=format&fit=crop&w=600&q=80',
    ],
    coverImageUrl:
        'https://images.unsplash.com/photo-1617019114583-affb34d1b3cd?auto=format&fit=crop&w=600&q=80',
    tags: ['sequin', 'gold', 'party', 'NYE', 'slip'],
    locationName: 'Dubai',
    status: 'active',
    createdAt: DateTime(2026, 2, 5),
  ),
  ListingModel(
    id: 'lst_008',
    lenderId: 'user_h',
    title: 'Vintage Maxi Boho',
    description:
        'Flowing vintage-inspired boho maxi. Earthy tones, perfect for festivals or beach weddings.',
    category: 'dress',
    brand: 'Free People',
    size: 'M',
    pricePerDay: 22,
    depositAmount: 110,
    imageUrls: [
      'https://images.unsplash.com/photo-1551232864-3f0890e1777e?auto=format&fit=crop&w=600&q=80',
    ],
    coverImageUrl:
        'https://images.unsplash.com/photo-1551232864-3f0890e1777e?auto=format&fit=crop&w=600&q=80',
    tags: ['boho', 'maxi', 'festival', 'vintage', 'earthy'],
    locationName: 'Ibiza',
    status: 'active',
    createdAt: DateTime(2026, 2, 8),
  ),
  ListingModel(
    id: 'lst_009',
    lenderId: 'user_i',
    title: 'Cobalt Blue Corset',
    description:
        'Structured cobalt blue corset dress with boning. An editorial statement for any occasion.',
    category: 'dress',
    brand: 'Vivienne Westwood',
    size: 'XS',
    pricePerDay: 62,
    depositAmount: 310,
    imageUrls: [
      'https://images.unsplash.com/photo-1583846783214-7229a91b20ed?auto=format&fit=crop&w=600&q=80',
    ],
    coverImageUrl:
        'https://images.unsplash.com/photo-1583846783214-7229a91b20ed?auto=format&fit=crop&w=600&q=80',
    tags: ['corset', 'cobalt', 'blue', 'structured', 'editorial'],
    locationName: 'Milan',
    status: 'active',
    createdAt: DateTime(2026, 2, 10),
  ),
  ListingModel(
    id: 'lst_010',
    lenderId: 'user_j',
    title: 'Nude Pleated Maxi',
    description:
        'Ethereal nude pleated maxi with a draped silhouette. Minimalist luxury at its best.',
    category: 'dress',
    brand: 'Totême',
    size: 'M',
    pricePerDay: 45,
    depositAmount: 225,
    imageUrls: [
      'https://images.unsplash.com/photo-1596783074918-c84cb06531ca?auto=format&fit=crop&w=600&q=80',
    ],
    coverImageUrl:
        'https://images.unsplash.com/photo-1596783074918-c84cb06531ca?auto=format&fit=crop&w=600&q=80',
    tags: ['nude', 'pleated', 'maxi', 'minimal', 'draped'],
    locationName: 'Copenhagen',
    status: 'active',
    createdAt: DateTime(2026, 2, 12),
  ),
];
