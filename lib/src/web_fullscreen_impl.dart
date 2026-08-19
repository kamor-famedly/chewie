import 'dart:js_interop';

import 'package:web/web.dart' as web;

final _handlers = <void Function(), JSFunction>{};

/// The fullscreen request the browser is still processing, if any. While it is
/// pending, `document.fullscreenElement` is not set yet, so an exit request
/// arriving in that window has to be chained onto it instead of being checked
/// against `fullscreenElement` directly.
Future<void>? _pendingRequest;

/// Incremented on every fullscreen request so an exit chained onto an older
/// request never cancels a newer one.
int _requestGeneration = 0;

void requestBrowserFullscreen() {
  final promise = web.document.documentElement?.requestFullscreen();
  if (promise == null) {
    return;
  }
  _requestGeneration++;
  // The browser may refuse the request (e.g. missing user activation);
  // Chewie's fullscreen then simply stays within the page.
  final request = promise.toDart.then((_) {}).catchError((_) {});
  _pendingRequest = request;
  request.whenComplete(() {
    if (_pendingRequest == request) {
      _pendingRequest = null;
    }
  });
}

void exitBrowserFullscreen() {
  final pending = _pendingRequest;
  if (pending != null) {
    // Entering has not finished yet; exit once it has, unless fullscreen has
    // been requested again in the meantime.
    final generation = _requestGeneration;
    pending.whenComplete(() {
      if (_requestGeneration == generation) {
        _exitIfInFullscreen();
      }
    });
    return;
  }
  _exitIfInFullscreen();
}

void _exitIfInFullscreen() {
  if (web.document.fullscreenElement != null) {
    web.document.exitFullscreen();
  }
}

bool get browserInFullscreen => web.document.fullscreenElement != null;

void addBrowserFullscreenChangeListener(void Function() callback) {
  final jsHandler = ((JSAny? _) => callback()).toJS;
  _handlers[callback] = jsHandler;
  web.document.addEventListener('fullscreenchange', jsHandler);
}

void removeBrowserFullscreenChangeListener(void Function() callback) {
  final jsHandler = _handlers.remove(callback);
  if (jsHandler != null) {
    web.document.removeEventListener('fullscreenchange', jsHandler);
  }
}
