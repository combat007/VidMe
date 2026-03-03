// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Sets [videoElement.muted] on every <video> element in the DOM.
///
/// Browsers enforce autoplay policy by checking [videoElement.muted], NOT
/// [videoElement.volume]. Setting volume=0 via setVolume() is not sufficient
/// to bypass the autoplay restriction — only muted=true does.
/// After controller.initialize() the <video> element always exists in the DOM.
void setVideoElementMuted(bool muted) {
  try {
    final videos = html.document.querySelectorAll('video');
    for (final v in videos) {
      (v as html.VideoElement).muted = muted;
    }
  } catch (_) {}
}
