import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A minimal [VideoPlayerPlatform] that tracks how often players are created,
/// how often playback is toggled and how many video surfaces are mounted at
/// the same time.
class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  FakeVideoPlayerPlatform({this.pauseOnSurfaceUnmount = false});

  /// Emulates browsers, which pause a video element that is removed from the
  /// DOM: unmounting the surface of a playing player emits an
  /// `isPlayingStateUpdate(false)` event, without counting as a pause() call.
  final bool pauseOnSurfaceUnmount;

  final surfaceTracker = SurfaceTracker();
  final _eventControllers = <int, StreamController<VideoEvent>>{};
  final _playing = <int>{};
  var createCount = 0;
  var playCount = 0;
  var pauseCount = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final playerId = createCount++;
    // Closed by close() in tearDown.
    // ignore: close_sinks
    final eventController = StreamController<VideoEvent>();
    _eventControllers[playerId] = eventController;
    eventController.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(minutes: 1),
        size: const Size(1920, 1080),
      ),
    );
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    return _eventControllers[playerId]!.stream;
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) {
    return _TrackedVideoSurface(
      tracker: surfaceTracker,
      onUnmounted: () => _surfaceUnmounted(options.playerId),
    );
  }

  void _surfaceUnmounted(int playerId) {
    if (!pauseOnSurfaceUnmount || !_playing.remove(playerId)) {
      return;
    }
    _eventControllers[playerId]?.add(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: false,
      ),
    );
  }

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> pause(int playerId) async {
    pauseCount++;
    _playing.remove(playerId);
  }

  @override
  Future<void> play(int playerId) async {
    playCount++;
    _playing.add(playerId);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  void resetPlaybackCalls() {
    playCount = 0;
    pauseCount = 0;
  }

  Future<void> close() async {
    await Future.wait(
      _eventControllers.values.map((controller) => controller.close()),
    );
  }
}

class SurfaceTracker {
  var active = 0;
  var maximumActive = 0;

  void mount() {
    active++;
    if (active > maximumActive) {
      maximumActive = active;
    }
  }

  void unmount() {
    active--;
  }
}

class _TrackedVideoSurface extends StatefulWidget {
  const _TrackedVideoSurface({required this.tracker, required this.onUnmounted});

  final SurfaceTracker tracker;
  final VoidCallback onUnmounted;

  @override
  State<_TrackedVideoSurface> createState() => _TrackedVideoSurfaceState();
}

class _TrackedVideoSurfaceState extends State<_TrackedVideoSurface> {
  @override
  void initState() {
    super.initState();
    widget.tracker.mount();
  }

  @override
  void dispose() {
    widget.tracker.unmount();
    widget.onUnmounted();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}
