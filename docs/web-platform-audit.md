# Chewie web platform audit

Full sweep of every code path that executes on Flutter web, performed 2026-08-21 on branch `agent/fix-web-fullscreen-controller-reinitialization`. Covers `chewie_player.dart`, `web_fullscreen_impl.dart`, `player_with_controls.dart`, all three control skins, `progress_bar.dart`, subtitles, helpers and notifiers.

## Context: the fullscreen redesign this branch ships

On web the fullscreen surface handoff was redesigned: the live player subtree carries a `GlobalKey` and is reparented between the inline widget and the fullscreen route, so the underlying video element never leaves the DOM and playback continues uninterrupted. This replaced the old controller re-initialization. The findings below are what remains on top of that work.

## Probable bugs

### B1 — Fullscreen entry crashes on iPhone Safari

`requestBrowserFullscreen` (`lib/src/web_fullscreen_impl.dart`) calls `documentElement.requestFullscreen()` unconditionally. iOS Safari on iPhone does not implement element fullscreen, so the js_interop call throws a synchronous `TypeError` before the `try` block in `_pushFullScreenWidget`, aborting fullscreen entry before the route is pushed. Fix: guard on `document.fullscreenEnabled` and wrap the call in try/catch, degrading to in-page fullscreen.

### B2 — VideoProgressBar loses its controller listener on reparent

`VideoProgressBar` (`lib/src/progress_bar.dart`) removes its `VideoPlayerController` listener in `deactivate()` but never re-adds it in `activate()`. The web fullscreen reparenting deactivates/reactivates the subtree on every fullscreen toggle, after which the bar no longer repaints on controller ticks. Currently masked by finding P1 (the parent controls rebuild everything each tick); fixing P1 without fixing B2 freezes the progress bar after the first fullscreen toggle. Fix: re-subscribe in `activate()`.

### B3 — Fullscreen listener errors vanish silently

`ChewieState.listener()` (`lib/src/chewie_player.dart`) is an async function invoked fire-and-forget from `notifyListeners`; exceptions in the push/pop path become unhandled zone errors with no context. Fix: catch and report through `FlutterError.reportError`.

### B4 — Two Chewie widgets on one controller break on web

Mounting two `Chewie` widgets that share one `VideoPlayerController` mounts the same DOM element as two platform views, which the web engine rejects. Pre-existing limitation; deserves an assert or a documentation note instead of a silent engine exception.

## Performance

### P1 — Controls rebuild the whole stack on every controller tick

`_updateState` in `MaterialControls`, `MaterialDesktopControls` and `CupertinoControls` calls `setState` unconditionally on every `VideoPlayerController` notification, several times per second during playback, rebuilding the entire controls stack even while the controls are hidden. The progress bar adds a second rebuild chain via its own listener. This is the largest steady-state cost on web. Fix: rebuild only when displayed state actually changed (play state, buffering flag, visible position text, active subtitle cue).

### P2 — Mouse hover causes rebuild and timer churn per pointer event

`MouseRegion.onHover` in all skins calls `_cancelAndRestartTimer()` on every pointer movement: an unconditional `setState` plus cancel-and-recreate of the hide `Timer`; `MaterialDesktopControls` additionally re-requests focus each event. Moving the mouse across the player produces dozens of rebuilds per second. Fix: skip the `setState` when controls are already visible and throttle the timer restart.

### P3 — CupertinoControls layers three to four live BackdropFilter blurs

The bottom bar, expand button and mute button each wrap in `ClipRRect` + `BackdropFilter` blur. On CanvasKit each blur is a saveLayer readback, making this the most expensive paint work in the package while controls are visible. Any change is visual, so this is flagged rather than fixed; an option is web-conditional solid translucency.

### P4 — additionalOptions user callback invoked every rebuild

`chewieController.additionalOptions!(context)` is called during build to decide button visibility (cupertino bottom bar) and to assemble options (material skins), which with P1 means a user callback runs several times per second. Fix: cache per dependencies change.

### P5 — StaticProgressBar sizes itself from MediaQuery

`StaticProgressBar` (`lib/src/progress_bar.dart`) builds a `Container` sized to `MediaQuery.of(context).size`, adding a MediaQuery dependency (rebuild on every window resize) for a widget that is layout-clamped anyway. `SizedBox.expand` semantics without MediaQuery are equivalent.

### P6 — Subtitle cues re-parse per tick

With subtitles enabled, `SubtitleOverlay` re-parses cue markup every rebuild although the cue changes only every few seconds, and `Subtitles.getByPosition` linear-scans all cues per tick. Cache the parsed span per cue; consider binary search for large cue lists.

## Code health

### C1 — didUpdateWidget writes controller state silently

`ChewieState.didUpdateWidget` assigns `controller._isFullScreen` without notifying, an implicit contract with the swap flow.

### C2 — route.completed await only matters for custom route builders

The default web route uses zero-duration transitions plus same-frame reparenting; the `route.completed` wait remains only for custom `routePageBuilder` transitions.

### C3 — PlayerNotifier misdocumented

The class comment calls it a singleton; it is instantiated per `ChewieState`, and `hideStuff` notifies even when the value did not change.

## Verified sound during this audit

The `route.completed` surface-handoff contract against the Flutter SDK; exit-time targeted route popping with sheets above the fullscreen route; the queued re-enter path; browser-fullscreen exit chaining onto a pending request; dispose-mid-transition; system-back synchronization; controller swap detach.
