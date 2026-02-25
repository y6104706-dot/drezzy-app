import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Response DTOs
// Mirror the TypeScript interfaces in functions/src/*.ts exactly so that
// field names and types stay in sync with the deployed Cloud Functions.
// ─────────────────────────────────────────────────────────────────────────────

/// Returned by `generateFaceSwap`.
class FaceSwapResult {
  const FaceSwapResult({required this.displayImageUrl});

  final String displayImageUrl;

  factory FaceSwapResult._fromData(Map<Object?, Object?> data) =>
      FaceSwapResult(
        displayImageUrl: data['display_image_url'] as String,
      );
}

/// Returned by `processVirtualTryOn`.
/// The client should listen to `tryOnJobs/{jobId}` in Firestore for
/// the result URL — the job runs asynchronously via a Replicate webhook.
class VirtualTryOnJobResult {
  const VirtualTryOnJobResult({required this.jobId, required this.message});

  final String jobId;
  final String message;

  factory VirtualTryOnJobResult._fromData(Map<Object?, Object?> data) =>
      VirtualTryOnJobResult(
        jobId: data['job_id'] as String,
        message: data['message'] as String,
      );
}

// ── Voice search DTOs ─────────────────────────────────────────────────────────

/// Fashion attributes that Gemini extracted from the user's natural-language query.
/// Mirrors `ParsedAttributes` in voiceSearch.ts.
class ParsedAttributes {
  const ParsedAttributes({
    required this.category,
    required this.style,
    required this.color,
    required this.occasion,
    required this.specificFeatures,
  });

  /// One of: `"dress"` | `"shoes"` | `"bag"` | `null`
  final String? category;
  final String? style;
  final String? color;
  final String? occasion;
  final List<String> specificFeatures;

  factory ParsedAttributes._fromData(Map<Object?, Object?> data) =>
      ParsedAttributes(
        category: data['category'] as String?,
        style: data['style'] as String?,
        color: data['color'] as String?,
        occasion: data['occasion'] as String?,
        specificFeatures: (data['specific_features'] as List<Object?>?)
                ?.whereType<String>()
                .toList() ??
            [],
      );
}

/// A single listing entry returned inside a voice search result.
class VoiceSearchListing {
  const VoiceSearchListing({
    required this.id,
    required this.title,
    required this.category,
    required this.pricePerDay,
    required this.imageUrl,
    required this.score,
  });

  final String id;
  final String title;
  final String category;
  final double pricePerDay;
  final String imageUrl;

  /// Relevance score assigned by the Cloud Function scoring algorithm.
  final int score;

  factory VoiceSearchListing._fromData(Map<Object?, Object?> data) =>
      VoiceSearchListing(
        id: data['id'] as String,
        title: data['title'] as String,
        category: data['category'] as String,
        pricePerDay: (data['pricePerDay'] as num).toDouble(),
        imageUrl: data['imageUrl'] as String,
        score: (data['score'] as num).toInt(),
      );
}

/// Sealed union for the three possible outcomes of `processVoiceSearch`.
/// Mirrors the `VoiceSearchResponse` union type in voiceSearch.ts.
sealed class VoiceSearchResponse {
  const VoiceSearchResponse({required this.detectedLanguage});

  /// ISO 639-1 language code detected from the user's query (e.g. `"en"`, `"he"`).
  final String detectedLanguage;
}

/// The query was understood and listings were found.
final class VoiceSearchResults extends VoiceSearchResponse {
  const VoiceSearchResults({
    required super.detectedLanguage,
    required this.listings,
    required this.attributes,
    required this.conversationalResponse,
  });

  final List<VoiceSearchListing> listings;
  final ParsedAttributes attributes;

  /// Gemini-authored result announcement in the user's language.
  /// e.g. "Great choice! I found 8 stunning red floral dresses for you."
  final String conversationalResponse;
}

/// The query was too vague — Gemini needs one more detail before searching.
final class VoiceSearchClarification extends VoiceSearchResponse {
  const VoiceSearchClarification({
    required super.detectedLanguage,
    required this.question,
  });

  /// Friendly follow-up question in the user's own language.
  final String question;
}

/// The query was understood but no listings matched the filters.
final class VoiceSearchNoResults extends VoiceSearchResponse {
  const VoiceSearchNoResults({
    required super.detectedLanguage,
    required this.attributes,
    required this.conversationalResponse,
  });

  final ParsedAttributes attributes;

  /// Empathetic zero-results message authored by Gemini in the user's language.
  final String conversationalResponse;
}

// ─────────────────────────────────────────────────────────────────────────────
// CloudFunctionsService
// ─────────────────────────────────────────────────────────────────────────────

class CloudFunctionsService {
  CloudFunctionsService(this._functions);

  final FirebaseFunctions _functions;

  // ── generateFaceSwap ────────────────────────────────────────────────────────

  /// Applies InsightFace to the caller's listing photo, replacing the lender's
  /// face with a neutral placeholder. Ownership is validated server-side.
  ///
  /// [listingId] — the Firestore `listings/{id}` document to update.
  /// [imageUrl]  — URL of the source image whose face is transplanted.
  ///
  /// Polls synchronously (max ~80 s). Use with a progress indicator.
  Future<FaceSwapResult> generateFaceSwap({
    required String listingId,
    required String imageUrl,
  }) async {
    final result = await _functions
        .httpsCallable(
          'generateFaceSwap',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 125)),
        )
        .call<Map<Object?, Object?>>({
      'listing_id': listingId,
      'image_url': imageUrl,
    });
    return FaceSwapResult._fromData(result.data);
  }

  // ── processVirtualTryOn ─────────────────────────────────────────────────────

  /// Submits an async IDM-VTON job to Replicate and returns immediately with
  /// a Firestore job ID. Subscribe to `tryOnJobs/{jobId}` for status updates.
  /// The result URL and an FCM push notification arrive via webhook.
  ///
  /// [fcmToken] — the device's FCM registration token for push delivery.
  Future<VirtualTryOnJobResult> processVirtualTryOn({
    required String userImageUrl,
    required String garmentImageUrl,
    required String garmentDescription,
    required String fcmToken,
  }) async {
    final result = await _functions
        .httpsCallable(
          'processVirtualTryOn',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 35)),
        )
        .call<Map<Object?, Object?>>({
      'user_image_url': userImageUrl,
      'garment_image_url': garmentImageUrl,
      'garment_description': garmentDescription,
      'fcm_token': fcmToken,
    });
    return VirtualTryOnJobResult._fromData(result.data);
  }

  // ── processVoiceSearch ──────────────────────────────────────────────────────

  /// Sends the STT-transcribed text to Gemini 1.5 Flash for NL understanding,
  /// merges with the caller's saved profile (size, budget, category prefs),
  /// queries Firestore, and returns relevance-ranked results with a
  /// conversational response authored in the user's detected language.
  ///
  /// Returns one of three sealed variants:
  ///   - [VoiceSearchResults]       — listings found
  ///   - [VoiceSearchClarification] — query too vague; ask a follow-up
  ///   - [VoiceSearchNoResults]     — understood, but no matching listings
  Future<VoiceSearchResponse> processVoiceSearch({
    required String transcribedText,
  }) async {
    final result = await _functions
        .httpsCallable(
          'processVoiceSearch',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 35)),
        )
        .call<Map<Object?, Object?>>({
      'transcribed_text': transcribedText,
    });
    return _parseVoiceSearchResponse(result.data);
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  VoiceSearchResponse _parseVoiceSearchResponse(Map<Object?, Object?> data) {
    final type = data['type'] as String;
    final lang = (data['detected_language'] as String?) ?? 'en';

    switch (type) {
      case 'results':
        final rawListings = (data['listings'] as List<Object?>?) ?? [];
        return VoiceSearchResults(
          detectedLanguage: lang,
          listings: rawListings
              .whereType<Map<Object?, Object?>>()
              .map(VoiceSearchListing._fromData)
              .toList(),
          attributes: ParsedAttributes._fromData(
            data['attributes'] as Map<Object?, Object?>,
          ),
          conversationalResponse: data['conversational_response'] as String,
        );

      case 'clarification_needed':
        return VoiceSearchClarification(
          detectedLanguage: lang,
          question: data['question'] as String,
        );

      case 'no_results':
        return VoiceSearchNoResults(
          detectedLanguage: lang,
          attributes: ParsedAttributes._fromData(
            data['attributes'] as Map<Object?, Object?>,
          ),
          conversationalResponse: data['conversational_response'] as String,
        );

      default:
        throw StateError(
          'processVoiceSearch returned unknown type: "$type". '
          'Check functions/src/voiceSearch.ts for schema changes.',
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Riverpod provider
// ─────────────────────────────────────────────────────────────────────────────

/// Provides a singleton [CloudFunctionsService] backed by [FirebaseFunctions.instance].
///
/// For local development with the Firebase Emulator Suite, override this
/// provider in your ProviderScope overrides:
///
/// ```dart
/// cloudFunctionsServiceProvider.overrideWithValue(
///   CloudFunctionsService(
///     FirebaseFunctions.instanceFor(region: 'us-central1')
///       ..useFunctionsEmulator('localhost', 5001),
///   ),
/// )
/// ```
final cloudFunctionsServiceProvider = Provider<CloudFunctionsService>((ref) {
  return CloudFunctionsService(
    FirebaseFunctions.instanceFor(region: 'us-central1'),
  );
});
