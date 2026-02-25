import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/cloud_functions_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/listing_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Try-On state machine
// ─────────────────────────────────────────────────────────────────────────────

enum _TryOnStatus { idle, submitting, waiting, done, error }

// Sample full-body photo used until the real user-photo upload is wired up.
// Replace with an image_picker flow once the user profile screen is built.
const _kDemoUserPhotoUrl =
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330'
    '?auto=format&fit=crop&w=400&q=80';

// ─────────────────────────────────────────────────────────────────────────────
// ListingDetailScreen
// ─────────────────────────────────────────────────────────────────────────────

class ListingDetailScreen extends ConsumerStatefulWidget {
  final ListingModel listing;

  const ListingDetailScreen({super.key, required this.listing});

  @override
  ConsumerState<ListingDetailScreen> createState() =>
      _ListingDetailScreenState();
}

class _ListingDetailScreenState extends ConsumerState<ListingDetailScreen> {
  // ── Try-On state ────────────────────────────────────────────────────────────
  _TryOnStatus _tryOnStatus = _TryOnStatus.idle;
  String? _tryOnJobId;
  String? _tryOnResultUrl;
  String? _tryOnError;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _tryOnSub;

  ListingModel get listing => widget.listing;

  @override
  void dispose() {
    _tryOnSub?.cancel();
    super.dispose();
  }

  // ── Try-On logic ─────────────────────────────────────────────────────────

  Future<void> _startTryOn() async {
    setState(() {
      _tryOnStatus = _TryOnStatus.submitting;
      _tryOnError = null;
    });

    try {
      // Best-effort FCM token — falls back to a placeholder when Firebase is
      // not yet configured (normal during local development).
      String fcmToken = 'dev_token_no_fcm';
      try {
        fcmToken =
            await FirebaseMessaging.instance.getToken() ?? fcmToken;
      } catch (_) {}

      final result =
          await ref.read(cloudFunctionsServiceProvider).processVirtualTryOn(
                userImageUrl: _kDemoUserPhotoUrl,
                garmentImageUrl: listing.coverImageUrl,
                garmentDescription: listing.description,
                fcmToken: fcmToken,
              );

      if (!mounted) return;
      setState(() {
        _tryOnJobId = result.jobId;
        _tryOnStatus = _TryOnStatus.waiting;
      });
      _watchJob(result.jobId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _tryOnStatus = _TryOnStatus.error;
          _tryOnError = e.toString();
        });
      }
    }
  }

  /// Subscribes to `tryOnJobs/{jobId}` in Firestore so the UI updates the
  /// moment the Replicate webhook writes the result URL back.
  void _watchJob(String jobId) {
    _tryOnSub?.cancel();
    _tryOnSub = FirebaseFirestore.instance
        .collection('tryOnJobs')
        .doc(jobId)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        final data = snap.data();
        if (data == null) return;
        final status = data['status'] as String?;

        if (status == 'completed') {
          setState(() {
            _tryOnResultUrl = (data['result_url'] as String?) ?? '';
            _tryOnStatus = _TryOnStatus.done;
          });
          _tryOnSub?.cancel();
        } else if (status == 'failed') {
          setState(() {
            _tryOnError =
                (data['error_message'] as String?) ?? 'Try-On failed.';
            _tryOnStatus = _TryOnStatus.error;
          });
          _tryOnSub?.cancel();
        }
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _tryOnError = e.toString();
            _tryOnStatus = _TryOnStatus.error;
          });
        }
      },
    );
  }

  void _resetTryOn() {
    _tryOnSub?.cancel();
    setState(() {
      _tryOnStatus = _TryOnStatus.idle;
      _tryOnJobId = null;
      _tryOnResultUrl = null;
      _tryOnError = null;
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      extendBodyBehindAppBar: true,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Expandable hero image ────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 460,
            pinned: true,
            stretch: true,
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0.5,
            leading: _BackButton(),
            actions: const [_WishlistButton(), SizedBox(width: 8)],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.blurBackground,
              ],
              background: Hero(
                tag: 'listing_image_${listing.id}',
                child: _HeroImage(url: listing.coverImageUrl),
              ),
            ),
          ),

          // ── Page content ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ListingHeader(listing: listing),
                  const SizedBox(height: 32),
                  _VirtualTryOnSection(
                    listing: listing,
                    status: _tryOnStatus,
                    resultUrl: _tryOnResultUrl,
                    errorMessage: _tryOnError,
                    jobId: _tryOnJobId,
                    onTryOn: _startTryOn,
                    onReset: _resetTryOn,
                  ),
                  const SizedBox(height: 32),
                  _SectionDivider(),
                  const SizedBox(height: 28),
                  _DescriptionSection(listing: listing),
                  const SizedBox(height: 28),
                  _TagsSection(tags: listing.tags),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _RentNowBar(listing: listing),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Back / Wishlist buttons (floating over the hero image)
// ─────────────────────────────────────────────────────────────────────────────

class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: GestureDetector(
        onTap: () => context.pop(),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 16,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _WishlistButton extends StatefulWidget {
  const _WishlistButton();

  @override
  State<_WishlistButton> createState() => _WishlistButtonState();
}

class _WishlistButtonState extends State<_WishlistButton>
    with SingleTickerProviderStateMixin {
  bool _saved = false;
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.4)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 45),
      TweenSequenceItem(
          tween: Tween(begin: 1.4, end: 1.0)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 55),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() => _saved = !_saved);
        _ctrl.forward(from: 0);
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: ScaleTransition(
          scale: _scale,
          child: Icon(
            _saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            size: 18,
            color: _saved
                ? DrezzyColors.champagneGold
                : Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero image
// ─────────────────────────────────────────────────────────────────────────────

class _HeroImage extends StatelessWidget {
  final String url;
  const _HeroImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          url,
          fit: BoxFit.cover,
          frameBuilder: (ctx, child, frame, wasSynchronous) {
            if (wasSynchronous) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (_, __, ___) => Container(
            color: DrezzyColors.charcoal,
            child: const Icon(Icons.checkroom_outlined,
                size: 48, color: DrezzyColors.champagneGold),
          ),
        ),
        // Bottom scrim so the AppBar icons stay readable
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.35, 1.0],
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.6),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Listing header (title, brand, price, location, size, rating)
// ─────────────────────────────────────────────────────────────────────────────

class _ListingHeader extends StatelessWidget {
  final ListingModel listing;
  const _ListingHeader({required this.listing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Brand + rating row
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: DrezzyColors.champagneGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: DrezzyColors.champagneGold.withValues(alpha: 0.35),
                  width: 0.7,
                ),
              ),
              child: Text(
                listing.brand.toUpperCase(),
                style: tt.labelSmall?.copyWith(
                  color: DrezzyColors.champagneGold,
                  letterSpacing: 1.5,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            Icon(Icons.star_rounded,
                size: 14, color: DrezzyColors.champagneGold),
            const SizedBox(width: 3),
            Text('4.9',
                style: tt.labelSmall?.copyWith(
                    color: cs.onSurface, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Text('(24)',
                style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 10),

        // Title
        Text(
          listing.title,
          style: tt.headlineMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 14),

        // Price + size + location
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Price
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '£${listing.pricePerDay.toStringAsFixed(0)}',
                    style: tt.titleLarge?.copyWith(
                      color: DrezzyColors.champagneGold,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  TextSpan(
                    text: ' / day',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),

            // Size chip
            _InfoChip(
                icon: Icons.straighten_rounded, label: 'Size ${listing.size}'),
            const SizedBox(width: 8),

            // Location chip
            _InfoChip(
                icon: Icons.location_on_outlined,
                label: listing.locationName),
          ],
        ),
        const SizedBox(height: 14),

        // Deposit note
        Row(
          children: [
            Icon(Icons.shield_outlined,
                size: 13, color: cs.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              'Deposit: £${listing.depositAmount.toStringAsFixed(0)} — '
              'refunded within 48 h of return',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border:
            Border.all(color: cs.outlineVariant.withValues(alpha: 0.4), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label,
              style: tt.labelSmall?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w500,
                  fontSize: 11)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Virtual Try-On section
// ─────────────────────────────────────────────────────────────────────────────

class _VirtualTryOnSection extends StatelessWidget {
  final ListingModel listing;
  final _TryOnStatus status;
  final String? resultUrl;
  final String? errorMessage;
  final String? jobId;
  final VoidCallback onTryOn;
  final VoidCallback onReset;

  const _VirtualTryOnSection({
    required this.listing,
    required this.status,
    required this.resultUrl,
    required this.errorMessage,
    required this.jobId,
    required this.onTryOn,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: DrezzyColors.champagneGold.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                const Text('✨', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(
                  'VIRTUAL TRY-ON',
                  style: tt.labelMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: DrezzyColors.champagneGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'AI',
                    style: tt.labelSmall?.copyWith(
                      color: DrezzyColors.champagneGold,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'See yourself wearing this piece before you rent.',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Dynamic content by status ───────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _buildStatusContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusContent(BuildContext context) {
    switch (status) {
      case _TryOnStatus.idle:
        return _TryOnIdleContent(
            key: const ValueKey('idle'), listing: listing, onTryOn: onTryOn);
      case _TryOnStatus.submitting:
        return const _TryOnSubmittingContent(key: ValueKey('submitting'));
      case _TryOnStatus.waiting:
        return _TryOnWaitingContent(key: const ValueKey('waiting'), jobId: jobId);
      case _TryOnStatus.done:
        return _TryOnResultContent(
            key: const ValueKey('done'),
            resultUrl: resultUrl ?? '',
            listing: listing,
            onReset: onReset);
      case _TryOnStatus.error:
        return _TryOnErrorContent(
            key: const ValueKey('error'),
            errorMessage: errorMessage ?? 'Unknown error.',
            onRetry: onTryOn,
            onReset: onReset);
    }
  }
}

// ── Idle content ──────────────────────────────────────────────────────────────

class _TryOnIdleContent extends StatelessWidget {
  final ListingModel listing;
  final VoidCallback onTryOn;
  const _TryOnIdleContent(
      {super.key, required this.listing, required this.onTryOn});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        children: [
          // Before-pair strip
          Row(
            children: [
              // Your demo photo
              Expanded(
                child: Column(
                  children: [
                    _PhotoFrame(
                      imageUrl: _kDemoUserPhotoUrl,
                      label: 'YOU',
                      labelColor: cs.primary,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.add_rounded,
                    size: 20,
                    color: DrezzyColors.champagneGold.withValues(alpha: 0.6)),
              ),
              // Garment photo
              Expanded(
                child: _PhotoFrame(
                  imageUrl: listing.coverImageUrl,
                  label: 'GARMENT',
                  labelColor: DrezzyColors.champagneGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // CTA
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onTryOn,
              style: FilledButton.styleFrom(
                backgroundColor: DrezzyColors.champagneGold,
                foregroundColor: DrezzyColors.obsidianPlum,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
                textStyle: tt.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('TRY IT ON'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Powered by IDM-VTON · Results in ~60 s',
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.55),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Submitting content ────────────────────────────────────────────────────────

class _TryOnSubmittingContent extends StatelessWidget {
  const _TryOnSubmittingContent({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: DrezzyColors.champagneGold,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Submitting to Drezzy AI…',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Waiting content (Firestore stream live) ───────────────────────────────────

class _TryOnWaitingContent extends StatelessWidget {
  final String? jobId;
  const _TryOnWaitingContent({super.key, required this.jobId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        children: [
          LinearProgressIndicator(
            backgroundColor: cs.surfaceContainerHighest,
            color: DrezzyColors.champagneGold,
            minHeight: 2,
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('✨', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Text(
                'AI is working its magic…',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Listening for result via Firestore stream',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.55),
              fontSize: 11,
            ),
          ),
          if (jobId != null) ...[
            const SizedBox(height: 6),
            Text(
              'Job: $jobId',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Result content ────────────────────────────────────────────────────────────

class _TryOnResultContent extends StatelessWidget {
  final String resultUrl;
  final ListingModel listing;
  final VoidCallback onReset;

  const _TryOnResultContent({
    super.key,
    required this.resultUrl,
    required this.listing,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        children: [
          // Success header
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: Colors.green.withValues(alpha: 0.35), width: 0.6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline_rounded,
                        size: 13, color: Colors.green),
                    const SizedBox(width: 5),
                    Text(
                      'TRY-ON COMPLETE',
                      style: tt.labelSmall?.copyWith(
                        color: Colors.green,
                        letterSpacing: 1,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Before / After comparison strip
          Row(
            children: [
              Expanded(
                child: _PhotoFrame(
                  imageUrl: listing.coverImageUrl,
                  label: 'BEFORE',
                  labelColor: cs.onSurfaceVariant,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 18,
                    color: DrezzyColors.champagneGold.withValues(alpha: 0.7)),
              ),
              Expanded(
                child: _FadeInNetworkImage(
                  url: resultUrl,
                  label: 'AFTER',
                  labelColor: DrezzyColors.champagneGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Try-again link
          TextButton.icon(
            onPressed: onReset,
            style: TextButton.styleFrom(
              foregroundColor: cs.onSurfaceVariant,
              textStyle: tt.bodySmall,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('Try with a different photo'),
          ),
        ],
      ),
    );
  }
}

// ── Error content ─────────────────────────────────────────────────────────────

class _TryOnErrorContent extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onReset;

  const _TryOnErrorContent({
    super.key,
    required this.errorMessage,
    required this.onRetry,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.construction_outlined,
                  size: 16, color: cs.error.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Text(
                'CF Not Ready',
                style: tt.titleSmall?.copyWith(
                    color: cs.error, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              errorMessage,
              style: tt.bodySmall?.copyWith(
                  color: cs.onErrorContainer, fontFamily: 'monospace'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Setup checklist:',
            style: tt.labelSmall?.copyWith(
                color: cs.onSurface, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ...const [
            '1. Run flutterfire configure --project=<your-id>',
            '2. cd functions && npm install && npm run build',
            '3. firebase deploy --only functions',
            '4. Set REPLICATE_API_TOKEN in Firebase secret manager',
          ].map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                step,
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DrezzyColors.champagneGold,
                    side: BorderSide(
                        color: DrezzyColors.champagneGold.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: const Text('Retry'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton(
                  onPressed: onReset,
                  style: TextButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant),
                  child: const Text('Dismiss'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable photo frame widget
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoFrame extends StatelessWidget {
  final String imageUrl;
  final String label;
  final Color labelColor;

  const _PhotoFrame({
    required this.imageUrl,
    required this.label,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: AspectRatio(
            aspectRatio: 0.75,
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              frameBuilder: (ctx, child, frame, wasSynchronous) {
                if (wasSynchronous) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  child: child,
                );
              },
              errorBuilder: (_, __, ___) => Container(
                color: DrezzyColors.charcoal,
                child: const Icon(Icons.checkroom_outlined,
                    color: DrezzyColors.champagneGold),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FadeInNetworkImage — premium result reveal
// Wraps Image.network with a frameBuilder-based opacity fade so the result
// image dissolves in smoothly once the download completes.
// ─────────────────────────────────────────────────────────────────────────────

class _FadeInNetworkImage extends StatelessWidget {
  final String url;
  final String label;
  final Color labelColor;

  const _FadeInNetworkImage({
    required this.url,
    required this.label,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: AspectRatio(
            aspectRatio: 0.75,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Placeholder shimmer while image loads
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        DrezzyColors.charcoal,
                        DrezzyColors.champagneGold.withValues(alpha: 0.08),
                        DrezzyColors.charcoal,
                      ],
                    ),
                  ),
                ),
                // FadeInImage via frameBuilder — zero extra dependencies
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  frameBuilder:
                      (ctx, child, frame, wasSynchronous) {
                    if (wasSynchronous) return child;
                    return AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      // Luxuriously slow cross-dissolve for the reveal.
                      duration: const Duration(milliseconds: 750),
                      curve: Curves.easeOut,
                      child: child,
                    );
                  },
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: DrezzyColors.champagneGold, size: 32),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Description & Tags
// ─────────────────────────────────────────────────────────────────────────────

class _DescriptionSection extends StatelessWidget {
  final ListingModel listing;
  const _DescriptionSection({required this.listing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ABOUT THIS PIECE',
          style: tt.labelSmall?.copyWith(
            color: DrezzyColors.champagneGold,
            letterSpacing: 2,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          listing.description,
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.85),
            height: 1.65,
          ),
        ),
      ],
    );
  }
}

class _TagsSection extends StatelessWidget {
  final List<String> tags;
  const _TagsSection({required this.tags});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags.map((t) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.35), width: 0.5),
          ),
          child: Text(
            '#$t',
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section divider
// ─────────────────────────────────────────────────────────────────────────────

class _SectionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.25),
      thickness: 0.6,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky bottom rent bar
// ─────────────────────────────────────────────────────────────────────────────

class _RentNowBar extends StatelessWidget {
  final ListingModel listing;
  const _RentNowBar({required this.listing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Price summary
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '£${listing.pricePerDay.toStringAsFixed(0)}',
                style: tt.titleLarge?.copyWith(
                  color: DrezzyColors.champagneGold,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'per day',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: FilledButton(
              onPressed: () {
                // TODO: context.push(AppRoutes.checkout, extra: listing)
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Checkout coming soon!'),
                    backgroundColor: cs.surfaceContainerHighest,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: DrezzyColors.champagneGold,
                foregroundColor: DrezzyColors.obsidianPlum,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
                textStyle: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              child: const Text('RENT NOW'),
            ),
          ),
        ],
      ),
    );
  }
}
