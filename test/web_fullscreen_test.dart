@TestOn('browser')
library;

import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  late VideoPlayerPlatform originalVideoPlayerPlatform;
  late _FakeVideoPlayerPlatform videoPlayerPlatform;
  late VideoPlayerController videoPlayerController;
  late ChewieController chewieController;

  setUp(() async {
    originalVideoPlayerPlatform = VideoPlayerPlatform.instance;
    videoPlayerPlatform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = videoPlayerPlatform;

    videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/video.mp4'),
    );
    await videoPlayerController.initialize();
    await videoPlayerController.play();
    chewieController = ChewieController(
      videoPlayerController: videoPlayerController,
      showControls: false,
      useNativeFullScreenOnWeb: false,
    );
    videoPlayerPlatform.resetPlaybackCalls();
  });

  tearDown(() async {
    chewieController.dispose();
    await videoPlayerController.dispose();
    await videoPlayerPlatform.close();
    VideoPlayerPlatform.instance = originalVideoPlayerPlatform;
  });

  testWidgets(
    'reuses one player and one video surface across fullscreen transitions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Chewie(controller: chewieController)),
        ),
      );
      await tester.pump();

      expect(videoPlayerPlatform.createCount, 1);
      expect(videoPlayerPlatform.surfaceTracker.active, 1);

      for (var cycle = 0; cycle < 3; cycle++) {
        chewieController.enterFullScreen();
        chewieController.enterFullScreen();
        await tester.pumpAndSettle();

        expect(chewieController.isFullScreen, isTrue);
        expect(videoPlayerPlatform.createCount, 1);
        expect(videoPlayerPlatform.surfaceTracker.active, 1);

        chewieController.exitFullScreen();
        chewieController.exitFullScreen();
        await tester.pumpAndSettle();

        expect(chewieController.isFullScreen, isFalse);
        expect(videoPlayerPlatform.createCount, 1);
        expect(videoPlayerPlatform.surfaceTracker.active, 1);
      }

      expect(videoPlayerPlatform.surfaceTracker.maximumActive, 1);
      expect(videoPlayerController.value.isPlaying, isTrue);
      expect(videoPlayerPlatform.playCount, 0);
      expect(videoPlayerPlatform.pauseCount, 0);

      await videoPlayerController.pause();
      videoPlayerPlatform.resetPlaybackCalls();

      chewieController.enterFullScreen();
      await tester.pumpAndSettle();
      chewieController.exitFullScreen();
      await tester.pumpAndSettle();

      expect(videoPlayerPlatform.createCount, 1);
      expect(videoPlayerPlatform.surfaceTracker.active, 1);
      expect(videoPlayerPlatform.surfaceTracker.maximumActive, 1);
      expect(videoPlayerController.value.isPlaying, isFalse);
      expect(videoPlayerPlatform.playCount, 0);
      expect(videoPlayerPlatform.pauseCount, 0);
    },
  );
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final surfaceTracker = _SurfaceTracker();
  final _eventControllers = <int, StreamController<VideoEvent>>{};
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
    return _TrackedVideoSurface(tracker: surfaceTracker);
  }

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> pause(int playerId) async {
    pauseCount++;
  }

  @override
  Future<void> play(int playerId) async {
    playCount++;
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

class _SurfaceTracker {
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
  const _TrackedVideoSurface({required this.tracker});

  final _SurfaceTracker tracker;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}
