import 'dart:js_util' as js_util;

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Mutes or unmutes every <video> element on the page, piercing Shadow DOM.
void setVideoElementMuted(bool muted) {
  final m = muted ? 'true' : 'false';
  final attr = muted ? "v.setAttribute('muted','');" : "v.removeAttribute('muted');";
  js_util.callMethod(js_util.globalThis, 'eval', ['''
(function(){
  function walk(root) {
    root.querySelectorAll('video').forEach(function(v){
      v.muted = $m; $attr
    });
    root.querySelectorAll('*').forEach(function(el){
      if (el.shadowRoot) walk(el.shadowRoot);
    });
  }
  walk(document);
})();
''']);
}

/// Finds the first <video> element (piercing Shadow DOM), sets it muted,
/// and calls play() directly on the DOM element.
///
/// Retries every 100 ms up to [maxMs] ms because video_player_web registers
/// the platform-view lazily — the <video> element may not be in the DOM yet
/// when controller.initialize() resolves.
///
/// Returns true if a video was found and play() was attempted,
/// false if the element never appeared or play() was rejected.
Future<bool> autoplayMuted({int maxMs = 2000}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: maxMs));
  while (DateTime.now().isBefore(deadline)) {
    final dynamic result = js_util.callMethod(js_util.globalThis, 'eval', [r'''
(function(){
  function find(root) {
    var vs = root.querySelectorAll('video');
    if (vs.length > 0) return vs[0];
    var all = root.querySelectorAll('*');
    for (var i = 0; i < all.length; i++) {
      if (all[i].shadowRoot) {
        var v = find(all[i].shadowRoot);
        if (v) return v;
      }
    }
    return null;
  }
  var v = find(document);
  if (!v) {
    console.log('[VidMez] no <video> found yet');
    return false;
  }
  v.muted = true;
  v.setAttribute('muted', '');
  v.volume = 0;
  console.log('[VidMez] found <video>, calling play()');
  v.play()
    .then(function(){ console.log('[VidMez] autoplay OK'); })
    .catch(function(e){ console.log('[VidMez] play() rejected:', e.message); });
  return true;
})()
''']);
    if (result == true) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}
