import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../../core/api/ai_client.dart';
import '../../../../core/services/cloud_functions_service.dart';
import '../services/tts_service.dart';

// ─── Status enum ──────────────────────────────────────────────────────────────

enum VoiceStatus {
  /// Default state — overlay is closed.
  idle,

  /// Calling SpeechToText.initialize() for the first time.
  initializing,

  /// Actively recording the user's voice.
  listening,

  /// Speech captured; Cloud Function call in-flight.
  processing,

  /// Gemini asked a clarifying question — TTS is speaking it now.
  /// The overlay shows the question text then auto-dismisses.
  clarifying,

  /// Final transcript is ready — the screen populates the search bar.
  done,

  /// SpeechToText is unavailable on this device.
  unavailable,

  /// User denied microphone / speech-recognition permission.
  permissionDenied,

  /// STT or Cloud Function returned an error.
  error,
}

// ─── State ────────────────────────────────────────────────────────────────────

class VoiceSearchState {
  const VoiceSearchState({
    this.status = VoiceStatus.idle,
    this.liveTranscript = '',
    this.finalTranscript = '',
    this.errorMessage,
    this.conversationalResponse,
    this.cloudSearchResult,
  });

  /// Words captured so far (updates live while listening).
  final String liveTranscript;

  /// Confirmed final transcript set when speech recognition ends.
  final String finalTranscript;

  /// Human-readable error string when [status] is [VoiceStatus.error].
  final String? errorMessage;

  /// Gemini-authored message spoken via TTS after the CF call completes:
  ///   - For [VoiceSearchResults]       → result announcement
  ///   - For [VoiceSearchClarification] → follow-up question
  ///   - For [VoiceSearchNoResults]     → empathetic zero-results message
  final String? conversationalResponse;

  /// The full typed response from [processVoiceSearch] Cloud Function.
  /// Available when status is [VoiceStatus.done] or [VoiceStatus.clarifying].
  final VoiceSearchResponse? cloudSearchResult;

  final VoiceStatus status;

  VoiceSearchState copyWith({
    VoiceStatus? status,
    String? liveTranscript,
    String? finalTranscript,
    String? errorMessage,
    String? conversationalResponse,
    VoiceSearchResponse? cloudSearchResult,
  }) =>
      VoiceSearchState(
        status: status ?? this.status,
        liveTranscript: liveTranscript ?? this.liveTranscript,
        finalTranscript: finalTranscript ?? this.finalTranscript,
        errorMessage: errorMessage ?? this.errorMessage,
        conversationalResponse:
            conversationalResponse ?? this.conversationalResponse,
        cloudSearchResult: cloudSearchResult ?? this.cloudSearchResult,
      );

  bool get isActive =>
      status == VoiceStatus.listening ||
      status == VoiceStatus.initializing ||
      status == VoiceStatus.processing;
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class VoiceSearchNotifier extends Notifier<VoiceSearchState> {
  final _speech = SpeechToText();
  bool _initialized = false;

  @override
  VoiceSearchState build() => const VoiceSearchState();

  // ── Public API ──────────────────────────────────────────────────────────────

  Future<void> startListening() async {
    // Reset to a clean initialising slate (clears transcript, response, result).
    state = const VoiceSearchState(status: VoiceStatus.initializing);

    if (!_initialized) {
      _initialized = await _speech.initialize(
        onError: _onError,
        onStatus: _onSttStatus,
      );
    }

    if (!_initialized) {
      if (state.status != VoiceStatus.permissionDenied &&
          state.status != VoiceStatus.error) {
        state = const VoiceSearchState(status: VoiceStatus.unavailable);
      }
      return;
    }

    state = const VoiceSearchState(status: VoiceStatus.listening);

    await _speech.listen(
      onResult: _onResult,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 2, milliseconds: 500),
      cancelOnError: true,
    );

    if (state.status == VoiceStatus.listening) {
      state = const VoiceSearchState(status: VoiceStatus.idle);
    }
  }

  /// Called by the overlay's × button or hardware back.
  Future<void> cancel() async {
    await _speech.cancel();
    state = const VoiceSearchState();
  }

  /// Resets to idle after the screen has consumed the final result.
  void reset() => state = const VoiceSearchState();

  // ── Private STT callbacks ───────────────────────────────────────────────────

  void _onResult(SpeechRecognitionResult result) {
    state = state.copyWith(liveTranscript: result.recognizedWords);

    if (result.finalResult && result.recognizedWords.isNotEmpty) {
      // Fire-and-forget — the async work happens inside _finalise.
      unawaited(_finalise(result.recognizedWords));
    }
  }

  void _onError(SpeechRecognitionError error) {
    if (error.errorMsg.contains('permission') ||
        error.errorMsg.contains('not_allowed')) {
      state = state.copyWith(status: VoiceStatus.permissionDenied);
    } else {
      state = state.copyWith(
        status: VoiceStatus.error,
        errorMessage: error.errorMsg,
      );
    }
  }

  void _onSttStatus(String status) {
    if (status == 'done' && state.status == VoiceStatus.listening) {
      if (state.liveTranscript.isNotEmpty) {
        unawaited(_finalise(state.liveTranscript));
      } else {
        state = const VoiceSearchState(status: VoiceStatus.idle);
      }
    }
  }

  // ── Cloud Function + TTS bridge ─────────────────────────────────────────────

  Future<void> _finalise(String transcript) async {
    // Show the "Drezzy is finding your perfect look..." spinner.
    state = VoiceSearchState(
      status: VoiceStatus.processing,
      finalTranscript: transcript,
    );

    try {
      final response =
          await ref.read(aiClientProvider).processVoiceSearch(transcript);

      final message = switch (response) {
        VoiceSearchResults r => r.conversationalResponse,
        VoiceSearchClarification r => r.question,
        VoiceSearchNoResults r => r.conversationalResponse,
      };

      // Speak Gemini's response while the overlay is still visible.
      // Fire-and-forget: TTS runs on its own audio channel and must not
      // delay the state transition that triggers the overlay auto-dismiss.
      unawaited(ref.read(ttsServiceProvider).speak(message));

      state = VoiceSearchState(
        status: response is VoiceSearchClarification
            ? VoiceStatus.clarifying
            : VoiceStatus.done,
        finalTranscript: transcript,
        conversationalResponse: message,
        cloudSearchResult: response,
      );
    } on AiClientException catch (e) {
      switch (e.error) {
        case AiClientError.firebaseNotInitialized:
          // Expected during development — skip the CF call, go straight to
          // done so the local mock filter still runs.
          debugPrint(
            '[VoiceSearch] Firebase not configured — CF call skipped.\n$e',
          );
          state = VoiceSearchState(
            status: VoiceStatus.done,
            finalTranscript: transcript,
          );

        case AiClientError.notAuthenticated:
          state = VoiceSearchState(
            status: VoiceStatus.error,
            finalTranscript: transcript,
            errorMessage: 'Sign in to use voice search.',
          );

        case AiClientError.callFailed:
          state = VoiceSearchState(
            status: VoiceStatus.error,
            finalTranscript: transcript,
            errorMessage: 'Could not reach Drezzy. Check your connection.',
          );
      }
    } catch (e) {
      debugPrint('[VoiceSearch] Unexpected error in _finalise: $e');
      state = VoiceSearchState(
        status: VoiceStatus.error,
        finalTranscript: transcript,
        errorMessage: 'Voice search failed. Please try again.',
      );
    }
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final voiceSearchProvider =
    NotifierProvider<VoiceSearchNotifier, VoiceSearchState>(
  VoiceSearchNotifier.new,
);
