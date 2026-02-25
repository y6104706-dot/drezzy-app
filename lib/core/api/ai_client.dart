import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cloud_functions_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Error model
// ─────────────────────────────────────────────────────────────────────────────

enum AiClientError {
  /// Firebase Auth reports no signed-in user.
  notAuthenticated,

  /// Firebase has not been initialised yet (stub firebase_options.dart).
  /// The app degrades gracefully — local mock data is still shown.
  firebaseNotInitialized,

  /// The Cloud Function returned an error (network, quota, internal, etc.).
  callFailed,
}

class AiClientException implements Exception {
  const AiClientException(this.error, [this.details]);

  final AiClientError error;

  /// Raw error string from the Firebase SDK, for logging.
  final String? details;

  @override
  String toString() => 'AiClientException(${error.name}): $details';
}

// ─────────────────────────────────────────────────────────────────────────────
// AiClient
// ─────────────────────────────────────────────────────────────────────────────

/// Thin gateway that sits between [VoiceSearchNotifier] and
/// [CloudFunctionsService].
///
/// Responsibilities:
///   1. **Auth guard** — verifies a Firebase user is signed in before making
///      any callable request. The Cloud Functions enforce this server-side too,
///      but failing early gives a faster, more descriptive error.
///   2. **Error normalisation** — maps [FirebaseFunctionsException] codes to
///      the typed [AiClientException] enum so callers don't need to parse
///      raw error strings.
///   3. **Graceful degradation** — if Firebase isn't initialised yet (stub
///      `firebase_options.dart`) the [AiClientError.firebaseNotInitialized]
///      variant is thrown so the notifier can fall back to the local mock flow.
class AiClient {
  AiClient(this._functions);

  final CloudFunctionsService _functions;

  // ── processVoiceSearch ─────────────────────────────────────────────────────

  /// Sends [transcribedText] to the `processVoiceSearch` Cloud Function and
  /// returns a typed [VoiceSearchResponse].
  ///
  /// Throws [AiClientException] on auth failure, uninitialised Firebase, or
  /// any Firebase Functions error. All other exceptions bubble through as-is.
  Future<VoiceSearchResponse> processVoiceSearch(
    String transcribedText,
  ) async {
    _assertAuth();
    try {
      return await _functions.processVoiceSearch(
        transcribedText: transcribedText,
      );
    } on FirebaseFunctionsException catch (e) {
      throw AiClientException(
        AiClientError.callFailed,
        '${e.code}: ${e.message}',
      );
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  /// Checks Firebase Auth state. Throws [AiClientException] rather than
  /// returning a bool so the call site can use a simple try-catch.
  void _assertAuth() {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw const AiClientException(
          AiClientError.notAuthenticated,
          'No signed-in Firebase user.',
        );
      }
    } on AiClientException {
      rethrow;
    } catch (_) {
      // FirebaseApp.defaultApp has not been initialised yet.
      throw const AiClientException(
        AiClientError.firebaseNotInitialized,
        'Firebase.initializeApp() has not completed. '
        'Run `flutterfire configure` and add the real firebase_options.dart.',
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Riverpod provider
// ─────────────────────────────────────────────────────────────────────────────

/// Provides a singleton [AiClient] wired to [CloudFunctionsService].
///
/// Swap it in tests / Emulator mode:
/// ```dart
/// aiClientProvider.overrideWithValue(MockAiClient())
/// ```
final aiClientProvider = Provider<AiClient>((ref) {
  return AiClient(ref.read(cloudFunctionsServiceProvider));
});
