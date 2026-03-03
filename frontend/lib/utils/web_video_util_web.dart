// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Mutes or unmutes every <video> element visible to this page,
/// including those inside Shadow DOM (Flutter HTML renderer wraps platform
/// views in <flt-platform-view> which uses a Shadow Root).
void setVideoElementMuted(bool muted) {
  _walkVideos((v) {
    v.muted = muted;
    if (muted) {
      v.setAttribute('muted', '');
    } else {
      v.removeAttribute('muted');
    }
  });
}

/// Finds the first <video> element, sets it muted, and calls play() on it
/// directly via the DOM (not through Flutter's VideoPlayerController).
///
/// Retries every 100 ms up to [maxMs] ms because video_player_web registers
/// the platform-view lazily — the <video> element may not be in the DOM yet
/// when controller.initialize() resolves.
///
/// Calling play() on the element directly instead of controller.play()
/// bypasses any intermediate Flutter layer that might reset the muted flag.
/// video_player_web listens to the element's `playing` event and will update
/// controller.value.isPlaying automatically.
///
/// Returns true if a video was found and the browser accepted play(),
/// false if the element was never found or the browser rejected autoplay.
Future<bool> autoplayMuted({int maxMs = 2000}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: maxMs));
  while (DateTime.now().isBefore(deadline)) {
    final videos = _collectVideos();
    if (videos.isNotEmpty) {
      final v = videos.first;
      // Set BOTH the property and the HTML attribute — some browsers check
      // the attribute, others the property.
      v.muted = true;
      v.setAttribute('muted', '');
      v.volume = 0;
      try {
        await v.play();
        return true;
      } catch (_) {
        // play() was rejected even with muted=true (extremely rare).
        return false;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false; // element never appeared in the DOM
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

List<html.VideoElement> _collectVideos() {
  final result = <html.VideoElement>[];
  _walkVideos(result.add);
  return result;
}

/// Walks every <video> element reachable from the document, including those
/// inside Shadow Roots (Flutter HTML renderer uses them for platform views).
void _walkVideos(void Function(html.VideoElement) fn) {
  // 1. Regular DOM
  for (final el in html.document.querySelectorAll('video')) {
    fn(el as html.VideoElement);
  }
  // 2. Shadow DOM — check elements that Flutter typically uses as platform-view
  //    host elements.  Using '*' is thorough but slow; limit to known tags first,
  //    then fall back to a broader scan if nothing was found yet.
  const flutterHosts = [
    'flt-platform-view',
    'flutter-view',
    'flt-html-slot',
    'flt-scene',
  ];
  for (final tag in flutterHosts) {
    for (final host in html.document.querySelectorAll(tag)) {
      final shadow = (host as html.Element).shadowRoot;
      if (shadow != null) {
        for (final el in shadow.querySelectorAll('video')) {
          fn(el as html.VideoElement);
        }
      }
    }
  }
  // 3. Broad scan: any element with a shadow root (covers unexpected nesting)
  for (final host in html.document.querySelectorAll('*')) {
    final shadow = (host as html.Element).shadowRoot;
    if (shadow != null) {
      for (final el in shadow.querySelectorAll('video')) {
        fn(el as html.VideoElement);
      }
    }
  }
}
