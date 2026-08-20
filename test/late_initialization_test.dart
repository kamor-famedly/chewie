import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'helpers/fake_video_player_platform.dart';

void main() {
  testWidgets(
    'adopts the video aspect ratio when initialization finishes after build',
    (tester) async {
      final originalVideoPlayerPlatform = VideoPlayerPlatform.instance;
      final videoPlayerPlatform = FakeVideoPlayerPlatform(
        initializeOnCreate: false,
      );
      VideoPlayerPlatform.instance = videoPlayerPlatform;
      final videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/video.mp4'),
      );
      final chewieController = ChewieController(
        videoPlayerController: videoPlayerController,
        showControls: false,
      );

      // Kick off initialization without awaiting it, the way a tap handler
      // does on the web.
      final initialization = videoPlayerController.initialize();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Chewie(controller: chewieController))),
      );
      await tester.pump();

      bool hasVideoAspectRatio() => tester
          .widgetList<AspectRatio>(find.byType(AspectRatio))
          .any((widget) => (widget.aspectRatio - 1920 / 1080).abs() < 0.001);

      expect(videoPlayerController.value.isInitialized, isFalse);
      expect(hasVideoAspectRatio(), isFalse);

      videoPlayerPlatform.emitInitialized(0);
      await initialization;
      await tester.pump();

      expect(videoPlayerController.value.isInitialized, isTrue);
      expect(hasVideoAspectRatio(), isTrue);

      await tester.pumpWidget(const SizedBox());
      chewieController.dispose();
      // The controller's event subscription was created inside the fake-async
      // test body, so canceling it must run under real async to complete.
      await tester.runAsync(() => videoPlayerController.dispose());
      await tester.runAsync(() => videoPlayerPlatform.close());
      VideoPlayerPlatform.instance = originalVideoPlayerPlatform;
    },
  );
}
