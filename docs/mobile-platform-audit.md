# Chewie iOS and Android platform audit

Full sweep of the code paths specific to mobile platforms, performed 2026-08-21 on branch `agent/fix-web-fullscreen-controller-reinitialization`. Covers system chrome and orientation handling, wakelock, the fullscreen route on native platforms, lifecycle interplay and the Android buffering workaround. Shared-widget findings from the web platform audit (P1, P2, P4, P6) apply to mobile unchanged and are not repeated; P3 (BackdropFilter cost) applies to iOS as well.

## Probable bugs

### M1 — systemOverlaysOnEnterFullScreen is accepted but dead

`ChewieController.systemOverlaysOnEnterFullScreen` is a documented constructor parameter, yet the code that would apply it in `onEnterFullScreen` (`lib/src/chewie_player.dart`) is commented out; entering fullscreen always hides all system overlays via `SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [])`. Users setting the parameter see no effect. Fix: either honor the parameter or deprecate it; silently ignoring it is the worst option.

### M2 — Fullscreen exit clobbers modern system UI modes on Android

Exiting fullscreen always calls `SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: systemOverlaysAfterFullScreen)`. Apps running `SystemUiMode.edgeToEdge` — which Android 15 enforces by default — get their mode replaced with the legacy manual mode after every fullscreen exit. Fix: restore `edgeToEdge` by default on Android, or skip the call when the app never asked for custom overlays, or expose the restore mode.

### M3 — Orientation decision uses the video size at enter time

`onEnterFullScreen` reads `videoPlayerController.value.size` to choose forced orientations. With lazy initialization (playback started from a user gesture, an increasingly common pattern), the size is still zero at fullscreen entry, so a 16:9 video falls into the square branch and allows all orientations instead of forcing landscape. Fix: fall back to `chewieController.aspectRatio`, or re-evaluate orientations once initialization completes while fullscreen.

## Behavior gotchas

### M4 — Orientation and overlay restore cannot know the app's prior state

`deviceOrientationsAfterFullScreen` defaults to all orientations, so a portrait-locked app becomes rotatable after fullscreen until it re-locks; the equivalent applies to overlays. SystemChrome has no getters, so chewie cannot restore what it never knew. The parameters exist for this; the gotcha belongs in the README.

### M5 — fullScreenByDefault is a fragile flow

`enterFullScreen()` fires inside the `ChewieController` constructor before any `Chewie` widget listens, leaving `isFullScreen == true` with no route. Actual entry happens later via `_fullScreenListener` when the video reports playing. Consequences: without autoplay, fullscreen engages only when playback starts; a `Chewie` widget mounted for a controller already in the fullscreen state does not reconcile (inline player, controller claims fullscreen). Worth an explicit reconcile in `initState` or documentation.

### M6 — enterFullScreen during build throws

Calling `enterFullScreen()`/`toggleFullScreen()` from a build callback runs `Navigator.push` during build and throws. Applies to all platforms; a post-frame deferral in `listener()` would make it safe, at the cost of a frame.

## Observations, verified sound

- While fullscreen on native platforms, the inline player stays mounted offstage below the opaque route, so two texture widgets of the same player exist; textures are cheap to duplicate and this is harmless, unlike on web where it would be illegal — the reason the web path reparents instead.
- The Android buffering workaround `getIsBuffering` (`lib/src/helpers/utils.dart`) correctly special-cases the flutter#165149 stuck-buffering bug by comparing position against the buffered ranges; per-tick cost is negligible.
- Wakelock scope is fullscreen-only, matching the `allowedScreenSleep` documentation; enable on route push, disable in the exit path, including on aborted entries.
- System back on Android pops the fullscreen route and the exit path re-synchronizes `isFullScreen`; covered by tests.
- The controller-swap flow detaches the old controller's listener and carries the fullscreen state over; covered by tests.
- `AppLifecycleState` pausing is handled by video_player's own lifecycle observer; chewie adds no conflicting behavior.
