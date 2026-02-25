import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/voice_search_provider.dart';

// ─── Entry-point ──────────────────────────────────────────────────────────────

class VoiceStylistOverlay extends ConsumerStatefulWidget {
  const VoiceStylistOverlay({super.key});

  /// Shows the overlay and starts listening.
  /// Returns when the overlay is dismissed (either auto on [VoiceStatus.done]
  /// or manually via the × button).
  static Future<void> show(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Voice Stylist',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (_, __, ___) => const VoiceStylistOverlay(),
      transitionBuilder: (_, animation, __, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curve),
            child: child,
          ),
        );
      },
    );
  }

  @override
  ConsumerState<VoiceStylistOverlay> createState() =>
      _VoiceStylistOverlayState();
}

class _VoiceStylistOverlayState extends ConsumerState<VoiceStylistOverlay>
    with TickerProviderStateMixin {
  // ── Pulse ring animation (3 staggered rings while listening) ────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double> _ring1Scale, _ring1Opacity;
  late final Animation<double> _ring2Scale, _ring2Opacity;
  late final Animation<double> _ring3Scale, _ring3Opacity;

  // ── Waveform bars (5 bars, each own controller) ─────────────────────────
  late final List<AnimationController> _waveCtrl;
  late final List<Animation<double>> _waveAnim;

  // Guard against double-pop
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _buildPulseAnimations();
    _buildWaveAnimations();

    // Start listening once the overlay is fully inserted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(voiceSearchProvider.notifier).startListening();
      }
    });
  }

  void _buildPulseAnimations() {
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    Animation<double> scale(double start) => Tween<double>(
          begin: 1.0,
          end: 2.4,
        ).animate(
          CurvedAnimation(
            parent: _pulseCtrl,
            curve: Interval(start, (start + 0.55).clamp(0.0, 1.0),
                curve: Curves.easeOut),
          ),
        );

    Animation<double> opacity(double start) => Tween<double>(
          begin: 0.55,
          end: 0.0,
        ).animate(
          CurvedAnimation(
            parent: _pulseCtrl,
            curve: Interval(start, (start + 0.55).clamp(0.0, 1.0),
                curve: Curves.easeOut),
          ),
        );

    _ring1Scale = scale(0.0);
    _ring1Opacity = opacity(0.0);
    _ring2Scale = scale(0.18);
    _ring2Opacity = opacity(0.18);
    _ring3Scale = scale(0.36);
    _ring3Opacity = opacity(0.36);
  }

  void _buildWaveAnimations() {
    // 5 bars with slightly different speeds for an organic waveform feel.
    final durations = [420, 560, 380, 500, 460];
    final maxHeights = [18.0, 28.0, 14.0, 24.0, 20.0];

    _waveCtrl = List.generate(
      5,
      (i) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: durations[i]),
      )..repeat(reverse: true),
    );

    _waveAnim = List.generate(
      5,
      (i) => Tween<double>(begin: 4, end: maxHeights[i]).animate(
        CurvedAnimation(parent: _waveCtrl[i], curve: Curves.easeInOut),
      ),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    for (final c in _waveCtrl) {
      c.dispose();
    }
    // Cancel STT if the overlay is dismissed without completing naturally.
    ref.read(voiceSearchProvider.notifier).cancel();
    super.dispose();
  }

  // ── Dismiss ──────────────────────────────────────────────────────────────

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    ref.read(voiceSearchProvider.notifier).cancel();
    if (mounted) Navigator.of(context).pop();
  }

  // ── Animation helpers based on current state ─────────────────────────────

  void _syncAnimationsToState(VoiceStatus status) {
    if (status == VoiceStatus.listening) {
      if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat();
      for (final c in _waveCtrl) {
        if (!c.isAnimating) c.repeat(reverse: true);
      }
    } else {
      if (_pulseCtrl.isAnimating) _pulseCtrl.stop();
      for (final c in _waveCtrl) {
        if (c.isAnimating) c.stop();
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Watch state and react to lifecycle transitions.
    final voiceState = ref.watch(voiceSearchProvider);
    _syncAnimationsToState(voiceState.status);

    ref.listen<VoiceSearchState>(voiceSearchProvider, (_, next) {
      if (_dismissed) return;

      if (next.status == VoiceStatus.done) {
        // Results ready — close immediately so the grid can update.
        _dismissed = true;
        if (mounted) Navigator.of(context).pop();
      } else if (next.status == VoiceStatus.clarifying) {
        // Gemini asked a follow-up question. TTS is already speaking it.
        // Keep the overlay visible for 2 s so the user can read the question,
        // then auto-dismiss — they can tap the mic again to answer.
        _dismissed = true;
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Blurred backdrop ──────────────────────────────────────────────
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              color: Colors.black.withValues(alpha: 0.80),
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Top bar: brand label + close button
                _buildTopBar(),

                const Spacer(flex: 2),

                // Orb + pulse rings
                _buildOrbArea(voiceState),

                const SizedBox(height: 36),

                // Status line
                _buildStatusLine(voiceState),

                const SizedBox(height: 20),

                // Live transcript or processing message
                _buildTranscriptArea(voiceState),

                // Waveform (only while listening)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: voiceState.status == VoiceStatus.listening
                      ? Padding(
                          padding: const EdgeInsets.only(top: 28),
                          child: _WaveformBars(
                            animations: _waveAnim,
                          ),
                        )
                      : const SizedBox(height: 28 + 32),
                ),

                const Spacer(flex: 3),

                // Bottom hint
                _buildBottomHint(voiceState),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Branding
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'DREZZY',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      letterSpacing: 5,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                'VOICE STYLIST',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: DrezzyColors.champagneGold,
                      letterSpacing: 3.5,
                      fontSize: 9,
                    ),
              ),
            ],
          ),

          // Close ×
          GestureDetector(
            onTap: _dismiss,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                ),
                color: Colors.white.withValues(alpha: 0.08),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Orb + pulse rings ────────────────────────────────────────────────────

  Widget _buildOrbArea(VoiceSearchState state) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ring 3 — outermost
          _PulseRing(scale: _ring3Scale, opacity: _ring3Opacity),

          // Ring 2
          _PulseRing(scale: _ring2Scale, opacity: _ring2Opacity),

          // Ring 1 — innermost
          _PulseRing(scale: _ring1Scale, opacity: _ring1Opacity),

          // Center orb
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: state.status == VoiceStatus.processing ||
                    state.status == VoiceStatus.done ||
                    state.status == VoiceStatus.clarifying
                ? _ProcessingOrb(key: const ValueKey('processing'))
                : state.status == VoiceStatus.error ||
                        state.status == VoiceStatus.permissionDenied ||
                        state.status == VoiceStatus.unavailable
                    ? _ErrorOrb(key: const ValueKey('error'))
                    : _MicOrb(
                        key: const ValueKey('mic'),
                        isInitializing:
                            state.status == VoiceStatus.initializing,
                      ),
          ),
        ],
      ),
    );
  }

  // ── Status text ──────────────────────────────────────────────────────────

  Widget _buildStatusLine(VoiceSearchState state) {
    final String label = switch (state.status) {
      VoiceStatus.initializing => 'Initializing...',
      VoiceStatus.listening => 'Listening...',
      VoiceStatus.processing => 'Drezzy is finding your perfect look...',
      VoiceStatus.done => 'Got it — searching now',
      VoiceStatus.clarifying => 'One moment — Drezzy needs a detail...',
      VoiceStatus.unavailable =>
        'Voice recognition unavailable on this device',
      VoiceStatus.permissionDenied =>
        'Microphone access denied — please enable in Settings',
      VoiceStatus.error => 'Oops, something went wrong',
      VoiceStatus.idle => '',
    };

    final Color color = switch (state.status) {
      VoiceStatus.listening => DrezzyColors.champagneGold,
      VoiceStatus.processing ||
      VoiceStatus.done ||
      VoiceStatus.clarifying =>
        DrezzyColors.champagneGold.withValues(alpha: 0.85),
      VoiceStatus.error ||
      VoiceStatus.permissionDenied ||
      VoiceStatus.unavailable =>
        DrezzyColors.error.withValues(alpha: 0.9),
      _ => Colors.white.withValues(alpha: 0.6),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Text(
        label,
        key: ValueKey(state.status),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              letterSpacing: 1.8,
              fontSize: 11,
            ),
      ),
    );
  }

  // ── Transcript ────────────────────────────────────────────────────────────

  Widget _buildTranscriptArea(VoiceSearchState state) {
    // For clarifying, show Gemini's question so the user can read while TTS speaks.
    final bool showClarification = state.status == VoiceStatus.clarifying &&
        (state.conversationalResponse?.isNotEmpty ?? false);
    final bool showFinal = !showClarification &&
        (state.status == VoiceStatus.processing ||
            state.status == VoiceStatus.done) &&
        state.finalTranscript.isNotEmpty;
    final bool showLive = !showFinal &&
        !showClarification &&
        state.status == VoiceStatus.listening &&
        state.liveTranscript.isNotEmpty;

    final String text = showClarification
        ? state.conversationalResponse!
        : showFinal
            ? '"${state.finalTranscript}"'
            : showLive
                ? '"${state.liveTranscript}"'
                : '';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: text.isEmpty
          ? const SizedBox(height: 48, key: ValueKey('empty'))
          : Padding(
              key: ValueKey(text),
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                text,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w300,
                      height: 1.35,
                      fontSize: 22,
                    ),
              ),
            ),
    );
  }

  // ── Bottom hint ──────────────────────────────────────────────────────────

  Widget _buildBottomHint(VoiceSearchState state) {
    final String hint = switch (state.status) {
      VoiceStatus.listening => 'Speak now · Tap × to cancel',
      VoiceStatus.processing => 'Please wait...',
      VoiceStatus.initializing => 'Starting microphone...',
      VoiceStatus.clarifying => 'Tap the mic to answer...',
      VoiceStatus.error ||
      VoiceStatus.permissionDenied ||
      VoiceStatus.unavailable =>
        'Tap × to dismiss',
      _ => '',
    };

    if (hint.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 0.5,
          color: Colors.white.withValues(alpha: 0.15),
        ),
        const SizedBox(width: 12),
        Text(
          hint,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.35),
                letterSpacing: 1.2,
                fontSize: 10,
              ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 32,
          height: 0.5,
          color: Colors.white.withValues(alpha: 0.15),
        ),
      ],
    );
  }
}

// ─── Pulse ring ───────────────────────────────────────────────────────────────

class _PulseRing extends StatelessWidget {
  final Animation<double> scale;
  final Animation<double> opacity;

  const _PulseRing({required this.scale, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([scale, opacity]),
      builder: (_, __) => Transform.scale(
        scale: scale.value,
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: DrezzyColors.champagneGold
                  .withValues(alpha: opacity.value.clamp(0.0, 1.0)),
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Center orb variants ──────────────────────────────────────────────────────

class _MicOrb extends StatelessWidget {
  final bool isInitializing;
  const _MicOrb({super.key, required this.isInitializing});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: DrezzyColors.champagneGold,
        boxShadow: [
          BoxShadow(
            color: DrezzyColors.champagneGold.withValues(alpha: 0.35),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: isInitializing
          ? const Padding(
              padding: EdgeInsets.all(26),
              child: CircularProgressIndicator(
                color: DrezzyColors.nearBlack,
                strokeWidth: 2,
              ),
            )
          : const Icon(
              Icons.mic_rounded,
              color: DrezzyColors.nearBlack,
              size: 38,
            ),
    );
  }
}

class _ProcessingOrb extends StatelessWidget {
  const _ProcessingOrb({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
        border: Border.all(
          color: DrezzyColors.champagneGold,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: DrezzyColors.champagneGold.withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(
          color: DrezzyColors.champagneGold,
          strokeWidth: 2,
        ),
      ),
    );
  }
}

class _ErrorOrb extends StatelessWidget {
  const _ErrorOrb({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: DrezzyColors.error.withValues(alpha: 0.1),
        border: Border.all(
          color: DrezzyColors.error.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: Icon(
        Icons.mic_off_rounded,
        color: DrezzyColors.error.withValues(alpha: 0.8),
        size: 34,
      ),
    );
  }
}

// ─── Waveform bars ────────────────────────────────────────────────────────────

class _WaveformBars extends StatelessWidget {
  final List<Animation<double>> animations;
  const _WaveformBars({required this.animations});

  @override
  Widget build(BuildContext context) {
    const barWidth = 3.0;
    const barSpacing = 5.0;

    return SizedBox(
      height: 32,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(animations.length, (i) {
          return Padding(
            padding: EdgeInsets.only(
              right: i < animations.length - 1 ? barSpacing : 0,
            ),
            child: AnimatedBuilder(
              animation: animations[i],
              builder: (_, __) => Container(
                width: barWidth,
                height: animations[i].value,
                decoration: BoxDecoration(
                  color: DrezzyColors.champagneGold.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
