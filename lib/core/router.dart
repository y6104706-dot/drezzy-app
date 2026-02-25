import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/listings/domain/listing_model.dart';
import '../features/listings/presentation/screens/discovery_feed_screen.dart';
import '../features/listings/presentation/screens/listing_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Route path constants
// Use these everywhere instead of raw strings to prevent typos.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class AppRoutes {
  // ── Auth ───────────────────────────────────────────────────────────────────
  static const String login = '/login';
  static const String register = '/register';

  // ── Core ───────────────────────────────────────────────────────────────────
  static const String home = '/';
  static const String profile = '/profile';
  static const String bookings = '/bookings';

  // ── Listings ───────────────────────────────────────────────────────────────
  /// Path param: `:id` — Firestore document ID of the listing.
  static const String listingDetail = '/listing/:id';

  /// Static segment — must be registered BEFORE [listingDetail] so GoRouter
  /// does not try to match "create" as a listing ID.
  static const String createListing = '/listing/create';

  // ── Checkout ───────────────────────────────────────────────────────────────
  static const String checkout = '/checkout';

  // ── AI / Try-On ────────────────────────────────────────────────────────────
  /// Path param: `:jobId` — Firestore document ID of the `tryOnJobs` entry.
  static const String tryOnResult = '/try-on/:jobId';

  // ── Typed helper builders ──────────────────────────────────────────────────
  static String listingDetailPath(String id) => '/listing/$id';
  static String tryOnResultPath(String jobId) => '/try-on/$jobId';
}

// ─────────────────────────────────────────────────────────────────────────────
// Router provider
// ─────────────────────────────────────────────────────────────────────────────

/// Provides the singleton [GoRouter] instance for the whole app.
///
/// Auth redirect will be wired here once `authStateProvider` exists:
///
/// ```dart
/// redirect: (context, state) {
///   final isLoggedIn = ref.read(authStateProvider).valueOrNull != null;
///   final onAuthRoute = state.matchedLocation == AppRoutes.login
///       || state.matchedLocation == AppRoutes.register;
///   if (!isLoggedIn && !onAuthRoute) return AppRoutes.login;
///   if (isLoggedIn && onAuthRoute) return AppRoutes.home;
///   return null;
/// },
/// refreshListenable: ref.watch(authStateListenableProvider),
/// ```
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: true,
    errorBuilder: (context, state) => _ErrorScreen(error: state.error),
    routes: [
      // ── Home / Browse ───────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const DiscoveryFeedScreen(),
      ),

      // ── Auth ────────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) =>
            const _PlaceholderScreen(title: 'Login', icon: Icons.lock_outline),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const _PlaceholderScreen(
            title: 'Create Account', icon: Icons.person_add_outlined),
      ),

      // ── Listings ────────────────────────────────────────────────────────────
      // IMPORTANT: /listing/create must come before /listing/:id so that the
      // literal "create" segment is not mistakenly parsed as a listing ID.
      GoRoute(
        path: AppRoutes.createListing,
        builder: (context, state) => const _PlaceholderScreen(
            title: 'List an Item', icon: Icons.add_photo_alternate_outlined),
      ),
      GoRoute(
        path: AppRoutes.listingDetail,
        builder: (context, state) {
          // ListingModel is passed via context.push(..., extra: listing).
          // If navigated to directly (e.g. deep-link / share), fall back to
          // the placeholder until a Firestore fetch-by-id is implemented.
          final listing = state.extra as ListingModel?;
          if (listing == null) {
            final id = state.pathParameters['id']!;
            return _PlaceholderScreen(
              title: 'Listing',
              icon: Icons.checkroom_outlined,
              subtitle: id,
            );
          }
          return ListingDetailScreen(listing: listing);
        },
      ),

      // ── Checkout ────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.checkout,
        builder: (context, state) => const _PlaceholderScreen(
            title: 'Checkout', icon: Icons.payment_outlined),
      ),

      // ── User ────────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const _PlaceholderScreen(
            title: 'My Profile', icon: Icons.account_circle_outlined),
      ),
      GoRoute(
        path: AppRoutes.bookings,
        builder: (context, state) => const _PlaceholderScreen(
            title: 'My Bookings', icon: Icons.calendar_month_outlined),
      ),

      // ── AI / Try-On ─────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.tryOnResult,
        builder: (context, state) {
          final jobId = state.pathParameters['jobId']!;
          return _PlaceholderScreen(
            title: 'Try-On Result',
            icon: Icons.auto_awesome_outlined,
            subtitle: jobId,
          );
        },
      ),
    ],
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// Placeholder screen
// Temporary UI shown for routes whose screens have not been implemented yet.
// Replace each instance by importing the real screen and swapping the builder.
// ─────────────────────────────────────────────────────────────────────────────

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({
    required this.title,
    required this.icon,
    this.subtitle,
  });

  final String title;
  final IconData icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: context.canPop()
            ? IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: cs.onSurface, size: 18),
                onPressed: context.pop,
              )
            : null,
        title: Text(title, style: tt.titleMedium),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: cs.primary, size: 36),
            ),
            const SizedBox(height: 24),
            Text(title, style: tt.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Coming soon',
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurface.withOpacity(0.45),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.3),
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error screen
// Shown by GoRouter when no route matches (404) or a route throws.
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error});

  final Exception? error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded,
                    color: cs.error, size: 56),
                const SizedBox(height: 20),
                Text('Page not found', style: tt.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  error?.toString() ?? 'The requested route does not exist.',
                  textAlign: TextAlign.center,
                  style: tt.bodySmall
                      ?.copyWith(color: cs.onSurface.withOpacity(0.45)),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => context.go(AppRoutes.home),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Go home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
