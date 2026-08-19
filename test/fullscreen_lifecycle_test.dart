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
  });

  tearDown(() async {
    chewieController.dispose();
    await videoPlayerController.dispose();
    await videoPlayerPlatform.close();
    VideoPlayerPlatform.instance = originalVideoPlayerPlatform;
  });

  Future<void> pumpChewie(WidgetTester tester, ChewieController controller) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Chewie(controller: controller))),
    );
    await tester.pump();
  }

  testWidgets('pushes and pops the fullscreen route without a new player', (
    tester,
  ) async {
    await pumpChewie(tester, chewieController);
    expect(find.byType(Scaffold), findsOneWidget);

    chewieController.enterFullScreen();
    await tester.pumpAndSettle();
    expect(chewieController.isFullScreen, isTrue);
    // The home Scaffold is offstage below the opaque fullscreen route.
    expect(find.byType(Scaffold, skipOffstage: false), findsNWidgets(2));

    chewieController.exitFullScreen();
    await tester.pumpAndSettle();
    expect(chewieController.isFullScreen, isFalse);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(videoPlayerPlatform.createCount, 1);
  });

  testWidgets('a system back pop syncs the controller out of fullscreen', (
    tester,
  ) async {
    await pumpChewie(tester, chewieController);

    chewieController.enterFullScreen();
    await tester.pumpAndSettle();

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(chewieController.isFullScreen, isFalse);
    expect(find.byType(Scaffold), findsOneWidget);

    // The state machine must not be stuck afterwards.
    chewieController.enterFullScreen();
    await tester.pumpAndSettle();
    expect(chewieController.isFullScreen, isTrue);

    chewieController.exitFullScreen();
    await tester.pumpAndSettle();
    expect(chewieController.isFullScreen, isFalse);
  });

  testWidgets('swapping the controller carries the fullscreen state over', (
    tester,
  ) async {
    await pumpChewie(tester, chewieController);

    chewieController.enterFullScreen();
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold, skipOffstage: false), findsNWidgets(2));

    final replacement = ChewieController(
      videoPlayerController: videoPlayerController,
      showControls: false,
      useNativeFullScreenOnWeb: false,
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Chewie(controller: replacement))),
    );
    await tester.pump();

    expect(replacement.isFullScreen, isTrue);

    // Without the carried-over state this would try to enter fullscreen a
    // second time instead of leaving it.
    replacement.toggleFullScreen();
    await tester.pumpAndSettle();

    expect(replacement.isFullScreen, isFalse);
    expect(find.byType(Scaffold), findsOneWidget);

    replacement.dispose();
  });
}
