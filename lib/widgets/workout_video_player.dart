/// আমার ডায়েট — workout video player widget.
///
/// Renders a `video_player.VideoPlayerController` with chunky
/// elderly-friendly play/pause + 10s skip controls.
///
/// Behaviour:
///   • The widget takes a `storagePath` (e.g. "Brisk Walking.mp4") and
///     resolves it to a fresh signed URL on init. Tokens are
///     short-lived, so we never cache the URL itself — we re-sign on
///     each rebuild.
///   • When the widget is disposed, the controller is disposed to
///     avoid memory leaks.
///   • Pauses cleanly when the host screen is popped or replaced.
///
/// Falls back to a static "video unavailable" tile if the bucket
/// lookup fails (no internet, missing file, expired token, etc.).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'mono_widgets.dart';

class WorkoutVideoPlayer extends StatefulWidget {
  /// Object-storage path *inside* the `exercise` bucket, e.g.
  /// "Brisk Walking.mp4". May be null/blank — the widget renders an
  /// empty placeholder in that case.
  final String? storagePath;

  /// Friendly label shown above the video (typically the workout name).
  final String label;

  /// When true the video restarts automatically after reaching the end.
  /// Default is false so the parent screen can chain the countdown timer
  /// after the video plays through.
  final bool autoLoop;

  /// When true the video starts playing as soon as the controller is
  /// ready. Default is false — playback only starts when the user
  /// taps the play overlay or the chunky bottom button. This matches
  /// the elderly-friendly expectation: an elderly user opens the
  /// exercise, sees the video frame with a big "tap to play" overlay,
  /// and decides consciously when to start.
  final bool autoPlay;

  /// When true (default) the workout video is audible whenever the
  /// user un-mutes it. When false the video is forced to be silent
  /// and the mute/unmute control is hidden. The user must be able to
  /// hear the workout cues, so the default is `true`.
  final bool audioEnabled;

  /// Fires once when the video plays to the end (or, if [storagePath] is
  /// empty/null, as soon as the widget mounts — useful for chaining the
  /// timer without forcing the user to wait for missing media).
  final VoidCallback? onFinished;

  /// Fires when the user explicitly taps the "skip" overlay. Provides
  /// an escape hatch for users who already know the exercise.
  final VoidCallback? onSkip;

  const WorkoutVideoPlayer({
    super.key,
    required this.storagePath,
    required this.label,
    this.autoLoop = false,
    this.autoPlay = false,
    this.audioEnabled = true,
    this.onFinished,
    this.onSkip,
  });

  @override
  State<WorkoutVideoPlayer> createState() => _WorkoutVideoPlayerState();
}

class _WorkoutVideoPlayerState extends State<WorkoutVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initialising = true;
  String? _error;
  bool _finishedFired = false;
  VoidCallback? _completionListener;

  /// Whether the user has muted the workout video. Defaults to `false`
  /// (audio ON) so the elderly user hears the workout cues by default.
  /// When [WorkoutVideoPlayer.audioEnabled] is `false` this is forced
  /// to `true` so the controller stays silent regardless.
  bool _muted = false;

  bool get _effectiveMuted => !widget.audioEnabled || _muted;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant WorkoutVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath) {
      _disposeController();
      _finishedFired = false;
      _init();
    }
  }

  Future<void> _init() async {
    final path = widget.storagePath?.trim();
    if (path == null || path.isEmpty) {
      // No video to play — release the parent immediately so the
      // countdown timer can take over without a dead wait.
      setState(() {
        _initialising = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onFinished?.call();
      });
      return;
    }
    try {
      final url =
          await SupabaseService.createExerciseVideoSignedUrl(path);
      if (!mounted) return;
      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controller = ctrl;
      await ctrl.initialize();
      await ctrl.setLooping(widget.autoLoop);
      // Apply the initial volume from the current mute state. The
      // default is UNMUTED so the elderly user hears the workout
      // audio cues by default; they can mute anytime via the
      // toggle button in the header. When `audioEnabled` is false
      // (e.g. silent-only deployments) the volume is forced to 0.
      try {
        await ctrl.setVolume(_effectiveMuted ? 0.0 : 1.0);
      } catch (_) {
        // Some platforms refuse setVolume before fully ready — we
        // retry after `initialize()` returned, see the second call
        // further down.
      }
      if (widget.autoPlay) {
        try {
          await ctrl.play();
          // Re-apply the volume right after starting playback — a
          // few Android builds briefly restore system volume during
          // the very first `play()` call.
          await ctrl.setVolume(_effectiveMuted ? 0.0 : 1.0);
        } catch (_) {
          // Some platforms refuse setVolume before fully ready — that's
          // fine, the user can still tap the play button below.
        }
      }

      // Listen for natural end-of-stream so the parent screen can
      // flip the user into the countdown flow exactly once. We also
      // catch ExoPlayer runtime errors (e.g. an expired signed URL,
      // unsupported codec, or a missing file) and surface them as the
      // "video unavailable" placeholder instead of leaving the user
      // staring at a blank player.
      void listener() {
        if (!mounted) return;
        final v = ctrl.value;

        if (v.hasError && !_finishedFired) {
          _finishedFired = true;
          setState(() {
            _error = v.errorDescription ??
                'ভিডিও চালানো যাচ্ছে না — স্টোরেজ ফাইল বা সাইনড URL সমস্যা হতে পারে';
          });
          // Release the parent so the countdown is still usable when
          // the video cannot be played back at all.
          widget.onFinished?.call();
          return;
        }

        if (_finishedFired) return;
        if (v.position >= v.duration - const Duration(milliseconds: 250)) {
          _finishedFired = true;
          try {
            ctrl.pause();
            ctrl.seekTo(v.duration);
          } catch (_) {}
          widget.onFinished?.call();
        }
      }

      ctrl.addListener(listener);
      _completionListener = listener;

      if (!mounted) return;
      setState(() {
        _initialising = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialising = false;
        _error = e.toString();
      });
    }
  }

  void _disposeController() {
    final c = _controller;
    if (c == null) return;
    final listener = _completionListener;
    if (listener != null) {
      try {
        c.removeListener(listener);
      } catch (_) {}
    }
    _completionListener = null;
    try {
      c.pause();
    } catch (_) {}
    c.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    HapticFeedback.selectionClick();
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    setState(() {});
  }

  /// User-driven mute toggle. Reflects the new state into the
  /// underlying controller immediately so the change is audible
  /// without waiting for a play/pause cycle.
  Future<void> _toggleMute() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    HapticFeedback.selectionClick();
    setState(() => _muted = !_muted);
    try {
      await c.setVolume(_effectiveMuted ? 0.0 : 1.0);
    } catch (_) {
      // Some platforms refuse setVolume when the controller is in
      // a transient state — the next _togglePlay will retry.
    }
  }

  void _skip(int seconds) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final target = c.value.position +
        Duration(seconds: seconds);
    final clamped = target.isNegative
        ? Duration.zero
        : (target > c.value.duration ? c.value.duration : target);
    c.seekTo(clamped);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final hasVideo = c != null && c.value.isInitialized && _error == null;
    final hasError = _error != null;
    final path = widget.storagePath?.trim();
    final noPath = path == null || path.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.play_circle_fill_rounded,
                    color: AppColors.ink,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Overline(
                        'ভিডিও গাইড',
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.paper,
                        ),
                      ),
                    ],
                  ),
                ),
                // User-driven mute toggle. The default is UNMUTED so
                // the elderly user hears the workout audio cues. Tapping
                // flips the icon + label and immediately calls
                // `setVolume` so the change is audible on the spot.
                if (widget.audioEnabled)
                  Pressable(
                    onTap: _toggleMute,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.paper,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _effectiveMuted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            size: 14,
                            color: AppColors.ink,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _effectiveMuted ? 'নীরব' : 'শব্দ',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  // Forced-silent deployments: show the static label
                  // so the user knows the audio won't play.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.volume_off_rounded,
                          size: 14,
                          color: AppColors.ink,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'নীরব',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.onSkip != null)
                  Pressable(
                    onTap: () {
                      _finishedFired = true;
                      widget.onSkip?.call();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.paper,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'এড়িয়ে যান',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Player surface
          AspectRatio(
            aspectRatio: hasVideo ? c.value.aspectRatio : 16 / 9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (hasVideo)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _togglePlay,
                      child: VideoPlayer(c),
                    ),
                  )
                else
                  Positioned.fill(
                    child: Container(
                      color: AppColors.graphite,
                      alignment: Alignment.center,
                      child: _initialising
                          ? const LoadingMark(size: 28)
                          : hasError
                              ? _Unavailable(
                                  icon: Icons.cloud_off_rounded,
                                  title: 'ভিডিও লোড হচ্ছে না',
                                  subtitle: _error!,
                                )
                              : noPath
                                  ? const _Unavailable(
                                      icon: Icons.videocam_off_rounded,
                                      title: 'ভিডিও শীঘ্রই আসছে',
                                      subtitle: 'প্রথমে ব্যায়ামের বিবরণ পড়ুন',
                                    )
                                  : const _Unavailable(
                                      icon: Icons.videocam_off_rounded,
                                      title: 'ভিডিও নেই',
                                      subtitle: 'এই ব্যায়ামের ভিডিও যোগ হয়নি',
                                    ),
                    ),
                  ),
                if (hasVideo && !c.value.isPlaying)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                size: 52,
                                color: AppColors.paper,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'ট্যাপ করে চালু করুন',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.paper,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Small reminder under the play hint that
                            // reflects the current audio state. Tapping
                            // the play button (i.e. the video frame) or
                            // the header pill flips it.
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.paper,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _effectiveMuted
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                    size: 14,
                                    color: AppColors.ink,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _effectiveMuted ? 'নীরব' : 'শব্দ চালু',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (hasVideo) _buildControls(),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final c = _controller!;
    final playing = c.value.isPlaying;
    final pos = c.value.position;
    final dur = c.value.duration;
    final progress = dur.inMilliseconds == 0
        ? 0.0
        : pos.inMilliseconds / dur.inMilliseconds;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: AppColors.ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.graphite,
              color: AppColors.paper,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ctrlBtn(
                icon: Icons.replay_10_rounded,
                label: '১০ সেকেন্ড পেছনে',
                onPressed: () => _skip(-10),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: Pressable(
                    onTap: _togglePlay,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.paper,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: AppColors.ink,
                            size: 28,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            playing ? 'বিরতি' : 'চালু করুন',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _ctrlBtn(
                icon: Icons.forward_10_rounded,
                label: '১০ সেকেন্ড সামনে',
                onPressed: () => _skip(10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ctrlBtn({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 56,
      height: 52,
      child: Pressable(
        onTap: onPressed,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.graphite,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: AppColors.paper, size: 28),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _Unavailable({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.paper, size: 36),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.paper,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.paper.withValues(alpha: 0.78),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}