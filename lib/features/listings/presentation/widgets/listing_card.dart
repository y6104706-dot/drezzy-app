import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/listing_model.dart';

/// High-end editorial listing card used in the Discovery Feed grid.
///
/// Layout: full-bleed [Hero] image with a bottom gradient overlay.
/// Price, title, and location chip are rendered over the gradient.
/// A wishlist heart lives in the top-right corner.
class ListingCard extends ConsumerStatefulWidget {
  final ListingModel listing;
  final VoidCallback onTap;

  const ListingCard({
    super.key,
    required this.listing,
    required this.onTap,
  });

  @override
  ConsumerState<ListingCard> createState() => _ListingCardState();
}

class _ListingCardState extends ConsumerState<ListingCard>
    with SingleTickerProviderStateMixin {
  bool _wishlisted = false;
  late final AnimationController _heartController;
  late final Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.35)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.35, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 50,
      ),
    ]).animate(_heartController);
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  void _toggleWishlist() {
    setState(() => _wishlisted = !_wishlisted);
    _heartController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Hero image ─────────────────────────────────────────────────
            Hero(
              tag: 'listing_image_${listing.id}',
              child: Image.network(
                listing.coverImageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _ImageFallback(
                  category: listing.category,
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return _ImageLoadingPlaceholder(
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                        : null,
                  );
                },
              ),
            ),

            // ── Gradient overlay (transparent → deep black) ───────────────
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.35, 0.72, 1.0],
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.88),
                    ],
                  ),
                ),
              ),
            ),

            // ── Wishlist button (top-right) ────────────────────────────────
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: _toggleWishlist,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: ScaleTransition(
                    scale: _heartScale,
                    child: Icon(
                      _wishlisted
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 16,
                      color: _wishlisted
                          ? DrezzyColors.champagneGold
                          : Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            ),

            // ── Bottom info overlay ────────────────────────────────────────
            Positioned(
              left: 10,
              right: 10,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Listing title
                  Text(
                    listing.title,
                    style: textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.2,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),

                  // Price + location row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Gold price tag
                      Text(
                        listing.priceLabel,
                        style: textTheme.labelMedium?.copyWith(
                          color: DrezzyColors.champagneGold,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const Spacer(),

                      // Location chip
                      _LocationChip(city: listing.locationName),
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
}

// ─── Location Chip ─────────────────────────────────────────────────────────

class _LocationChip extends StatelessWidget {
  final String city;
  const _LocationChip({required this.city});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: DrezzyColors.champagneGold.withValues(alpha: 0.45),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_on_rounded,
            size: 9,
            color: DrezzyColors.champagneGold,
          ),
          const SizedBox(width: 2),
          Text(
            city,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Image Loading States ──────────────────────────────────────────────────

class _ImageLoadingPlaceholder extends StatelessWidget {
  final double? value;
  const _ImageLoadingPlaceholder({this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DrezzyColors.charcoal,
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            value: value,
            strokeWidth: 1.5,
            color: DrezzyColors.champagneGold.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  final String category;
  const _ImageFallback({required this.category});

  static const _categoryIcons = {
    'dress': Icons.checkroom_rounded,
    'shoes': Icons.ice_skating_rounded,
    'bag': Icons.shopping_bag_outlined,
    'accessory': Icons.diamond_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DrezzyColors.charcoal,
      child: Center(
        child: Icon(
          _categoryIcons[category] ?? Icons.checkroom_rounded,
          size: 36,
          color: DrezzyColors.champagneGold.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
