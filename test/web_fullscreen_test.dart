@TestOn('browser')
library;

import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'helpers/fake_video_player_platform.dart';

void main() {
  late VideoPlayerPlatform originalVideoPlayerPlatform;
  late FakeVideoPlayerPlatform videoPlayerPlatform;
  late VideoPlayerController videoPlayerController;
  late ChewieController chewieController;

  setUp(() async {
    originalVideoPlayerPlatform = VideoPlayerPlatform.instance;
    videoPlayerPlatform = FakeVideoPlayerPlatform();
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

  const homeKey = Key('home');

  Future<void> pumpChewie(WidgetTester tester, ChewieController controller) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(key: homeKey, body: Chewie(controller: controller)),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'reuses one player and one video surface across fullscreen transitions',
    (tester) async {
      await pumpChewie(tester, chewieController);

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

  testWidgets('exiting fullscreen dismisses routes stacked above it', (
    tester,
  ) async {
    const sheetKey = Key('sheet');
    await pumpChewie(tester, chewieController);

    chewieController.enterFullScreen();
    await tester.pumpAndSettle();
    expect(chewieController.isFullScreen, isTrue);
    // The home page sits offstage below the opaque fullscreen route.
    expect(find.byKey(homeKey), findsNothing);

    // Open a sheet on top of the fullscreen route, like the controls'
    // options/playback-speed sheets do.
    unawaited(
      showModalBottomSheet<void>(
        context: tester.element(find.byType(Scaffold).last),
        useRootNavigator: true,
        builder: (_) => const SizedBox(key: sheetKey, height: 100),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(sheetKey), findsOneWidget);

    chewieController.exitFullScreen();
    await tester.pumpAndSettle();

    expect(chewieController.isFullScreen, isFalse);
    expect(find.byKey(sheetKey), findsNothing);
    // The fullscreen route itself must be gone, not just the sheet.
    expect(find.byKey(homeKey), findsOneWidget);
    expect(videoPlayerPlatform.surfaceTracker.active, 1);

    // Regression: fullscreen used to be permanently stuck after this.
    chewieController.enterFullScreen();
    await tester.pumpAndSettle();
    expect(chewieController.isFullScreen, isTrue);
    expect(find.byKey(homeKey), findsNothing);
    expect(videoPlayerPlatform.surfaceTracker.active, 1);

    chewieController.exitFullScreen();
    await tester.pumpAndSettle();
    expect(chewieController.isFullScreen, isFalse);
    expect(find.byKey(homeKey), findsOneWidget);
    expect(videoPlayerPlatform.surfaceTracker.maximumActive, 1);
  });

  testWidgets('an immediately cancelled enter restores the inline player', (
    tester,
  ) async {
    await pumpChewie(tester, chewieController);

    chewieController.enterFullScreen();
    chewieController.exitFullScreen();
    await tester.pumpAndSettle();

    expect(chewieController.isFullScreen, isFalse);
    expect(videoPlayerPlatform.surfaceTracker.active, 1);
    expect(videoPlayerPlatform.surfaceTracker.maximumActive, 1);

    chewieController.enterFullScreen();
    await tester.pumpAndSettle();
    expect(chewieController.isFullScreen, isTrue);
    expect(videoPlayerPlatform.surfaceTracker.active, 1);
  });

  testWidgets('a fullscreen request during exit teardown is honored', (
    tester,
  ) async {
    await pumpChewie(tester, chewieController);

    chewieController.enterFullScreen();
    await tester.pumpAndSettle();

    chewieController.exitFullScreen();
    chewieController.enterFullScreen();
    await tester.pumpAndSettle();

    expect(chewieController.isFullScreen, isTrue);
    expect(videoPlayerPlatform.surfaceTracker.active, 1);
    expect(videoPlayerPlatform.surfaceTracker.maximumActive, 1);

    chewieController.exitFullScreen();
    await tester.pumpAndSettle();
    expect(chewieController.isFullScreen, isFalse);
  });

  testWidgets(
    'a fullscreen request during a custom route reverse transition is honored',
    (tester) async {
      final customController = ChewieController(
        videoPlayerController: videoPlayerController,
        showControls: false,
        useNativeFullScreenOnWeb: false,
        routePageBuilder: (context, animation, secondaryAnimation, provider) =>
            FadeTransition(
              opacity: animation,
              child: Scaffold(body: provider),
            ),
      );
      await pumpChewie(tester, customController);

      customController.enterFullScreen();
      await tester.pumpAndSettle();

      customController.exitFullScreen();
      // Land in the middle of the 300 ms reverse transition.
      await tester.pump(const Duration(milliseconds: 100));
      customController.enterFullScreen();
      await tester.pumpAndSettle();

      expect(customController.isFullScreen, isTrue);
      expect(videoPlayerPlatform.surfaceTracker.active, 1);
      expect(videoPlayerPlatform.surfaceTracker.maximumActive, 1);

      customController.exitFullScreen();
      await tester.pumpAndSettle();
      expect(customController.isFullScreen, isFalse);

      customController.dispose();
    },
  );

  testWidgets('controls survive a fullscreen exit while their sheet is open', (
    tester,
  ) async {
    final controlsController = ChewieController(
      videoPlayerController: videoPlayerController,
      useNativeFullScreenOnWeb: false,
    );
    // The desktop controls are what browsers on desktop platforms get.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          key: homeKey,
          body: Chewie(controller: controlsController),
        ),
      ),
    );
    await tester.pump();

    controlsController.enterFullScreen();
    await tester.pumpAndSettle();
    expect(controlsController.isFullScreen, isTrue);

    // Show the controls, then open the options sheet from the fullscreen
    // controls.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    // Exiting fullscreen force-closes the sheet; the controls' awaited sheet
    // call then resumes after the fullscreen controls have been disposed and
    // starts the hide timer.
    controlsController.exitFullScreen();
    await tester.pumpAndSettle();
    expect(controlsController.isFullScreen, isFalse);
    expect(find.byKey(homeKey), findsOneWidget);

    // Cross that hide timer's duration; without the mounted guard its
    // callback throws setState-after-dispose.
    await tester.pump(const Duration(seconds: 4));
    expect(videoPlayerPlatform.surfaceTracker.active, 1);

    controlsController.dispose();
  });

  testWidgets('disposing the player mid-transition does not throw', (
    tester,
  ) async {
    await pumpChewie(tester, chewieController);

    // Unmount while the enter handoff (end-of-frame wait) is in flight.
    chewieController.enterFullScreen();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(chewieController.isFullScreen, isFalse);

    // And again while an exit is in flight.
    await pumpChewie(tester, chewieController);
    chewieController.enterFullScreen();
    await tester.pumpAndSettle();
    chewieController.exitFullScreen();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
