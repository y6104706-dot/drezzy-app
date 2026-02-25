import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Thin wrapper around [FlutterTts] configured for a premium, unhurried voice.
///
/// Injected app-wide via [ttsServiceProvider].
class TtsService {
  final _tts = FlutterTts();

  TtsService() {
    _configure();
  }

  Future<void> _configure() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.46); // slightly slower → refined feel
    await _tts.setVolume(0.9);
    await _tts.setPitch(0.95);     // just below neutral → warm, confident
  }

  /// Stops any active speech, then reads [text] aloud.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() async => _tts.stop();

  /// Builds and speaks a contextual response after a voice search completes.
  ///
  /// [query]       — the transcript the user said.
  /// [resultCount] — number of listings returned by the filter.
  Future<void> announceSearchResult(String query, int resultCount) async {
    final String message;
    if (resultCount == 0) {
      message = "Nothing found for $query. Try a different style.";
    } else if (resultCount == 1) {
      message = "I found one stunning piece for $query.";
    } else {
      message = "I curated $resultCount looks for $query. Here they are.";
    }
    await speak(message);
  }
}

/// App-scoped singleton — one [TtsService] for the lifetime of the ProviderScope.
final ttsServiceProvider = Provider<TtsService>((ref) => TtsService());
