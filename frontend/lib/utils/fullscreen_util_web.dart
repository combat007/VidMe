// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Asks the browser to enter fullscreen mode for the whole page.
void enterBrowserFullscreen() {
  try {
    html.document.documentElement?.requestFullscreen();
  } catch (_) {}
}

/// Exits browser fullscreen (also triggered when user presses Esc).
void exitBrowserFullscreen() {
  try {
    if (html.document.fullscreenElement != null) {
      html.document.exitFullscreen();
    }
  } catch (_) {}
}

/// Emits [true] when entering fullscreen, [false] when leaving.
/// Used to sync our _sizeMode when user presses Esc in the browser.
Stream<bool> get browserFullscreenChanges =>
    html.document.onFullscreenChange
        .map((_) => html.document.fullscreenElement != null);
