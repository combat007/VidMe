import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:intl/intl.dart';
import '../../config/api_config.dart';
import '../../models/video.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/comment_section.dart';
import '../../utils/fullscreen_util.dart';
import '../../utils/web_video_util.dart';

enum _SizeMode { tile, theater, fullscreen }

class VideoPlayerScreen extends StatefulWidget {
  final String videoId;
  const VideoPlayerScreen({super.key, required this.videoId});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  // ── metadata
  Video? _video;
  bool _loadingVideo = true;
  String? _videoError;

  // ── player — controller lives in State; never recreated on mode switch
  VideoPlayerController? _controller;
  bool _playerInitialized = false;

  // ── auto-hiding play controls (centre buttons + seek bar + volume)
  bool _showControls = true;
  Timer? _hideTimer;

  // ── seek
  bool _seeking = false;
  double _seekRatio = 0;

  // ── volume
  double _volume = 1.0;
  bool _muted = false;
  bool _autoMuted = false; // true when muted automatically for browser autoplay

  // ── display mode
  _SizeMode _sizeMode = _SizeMode.tile;

  // ── browser-fullscreen change listener (handles Esc key exit)
  StreamSubscription<bool>? _fsChangeSub;

  // ── likes
  int _likeCount = 0;
  bool _liked = false;
  bool _likingInProgress = false;

  // ── bookmarks
  bool _bookmarked = false;
  bool _bookmarkingInProgress = false;

  // ─────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadVideo();
    // Sync _sizeMode when user exits browser fullscreen via Esc
    _fsChangeSub = browserFullscreenChanges.listen((isBrowserFs) {
      if (!isBrowserFs && mounted && _sizeMode == _SizeMode.fullscreen) {
        setState(() => _sizeMode = _SizeMode.theater);
      }
    });
  }

  @override
  void dispose() {
    _fsChangeSub?.cancel();
    _hideTimer?.cancel();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    exitBrowserFullscreen();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    // Keep screen awake while playing; release lock when paused/ended
    if (_controller != null) {
      if (_controller!.value.isPlaying) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    }
    setState(() {});
  }

  // ─────────────────────────────────────────────────────────────
  // Data loading
  // ─────────────────────────────────────────────────────────────
  Future<void> _loadVideo() async {
    try {
      final video = await ApiService.getVideo(widget.videoId);
      if (!mounted) return;
      setState(() { _video = video; _loadingVideo = false; });
      _initPlayer(ApiConfig.videoUrl(video.ipfsCid));
      _loadLikes();
      _loadBookmarkStatus();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _videoError = e.message; _loadingVideo = false; });
    }
  }

  void _initPlayer(String url) {
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller!.addListener(_onControllerUpdate);
    _controller!.initialize().then((_) {
      if (!mounted) return;
      setState(() => _playerInitialized = true);
      _resetHideTimer();
      // Wait for the VideoPlayer widget to be rendered (and the <video> DOM
      // element to be mounted by video_player_web) before attempting autoplay.
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoplay());
    }).catchError((e) => debugPrint('Player init error: $e'));
  }

  /// Starts playback immediately after the controller is ready.
  ///
  /// On web, browsers block unmuted autoplay on direct page load (e.g. opening
  /// a shared link). We work around this by starting muted, which is always
  /// allowed, and showing a "Tap to unmute" badge. If even muted autoplay fails
  /// (very rare), we reset state so the user can tap play manually.
  ///
  /// On native Android/iOS there is no autoplay restriction, so we play with
  /// sound right away.
  /// YouTube-style autoplay: start muted so the browser allows it,
  /// show a "Tap to unmute" badge, let the user choose to restore sound.
  ///
  /// We call [autoplayMuted()] which:
  ///  1. Polls the DOM (with shadow-DOM traversal) until the <video> element
  ///     appears — video_player_web mounts the element asynchronously after
  ///     controller.initialize() resolves, so we cannot call setVolume/play
  ///     immediately; we would be operating on a non-existent element.
  ///  2. Sets muted=true + the HTML `muted` attribute on the element (browsers
  ///     check the DOM property, not Flutter's volume state).
  ///  3. Calls videoElement.play() directly — video_player_web's event
  ///     listeners pick up the `playing` event and update
  ///     controller.value.isPlaying automatically.
  Future<void> _tryAutoplay() async {
    if (!mounted) return;
    if (kIsWeb) {
      // Optimistically show muted state in the UI while we search for the element.
      setState(() { _muted = true; _autoMuted = true; });

      final played = await autoplayMuted(maxMs: 2000);
      if (!mounted) return;

      if (played) {
        // Keep Flutter's volume model in sync with the DOM muted state.
        await _controller?.setVolume(0);
      } else {
        // Element not found or play() rejected — reset so user can tap play.
        setVideoElementMuted(false);
        setState(() { _muted = false; _autoMuted = false; });
      }
    } else {
      // Native Android/iOS: no browser autoplay policy — play with sound.
      _controller!.play();
    }
  }

  Future<void> _loadLikes() async {
    try {
      final r = await ApiService.getLikes(widget.videoId);
      if (!mounted) return;
      setState(() {
        _likeCount = r['count'] as int;
        _liked = r['liked'] as bool? ?? false;
      });
    } catch (_) {}
  }

  Future<void> _loadBookmarkStatus() async {
    if (!context.read<AuthProvider>().isAuthenticated) return;
    try {
      final r = await ApiService.getBookmarkStatus(widget.videoId);
      if (!mounted) return;
      setState(() => _bookmarked = r['bookmarked'] as bool? ?? false);
    } catch (_) {}
  }

  Future<void> _toggleBookmark() async {
    if (!context.read<AuthProvider>().isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to bookmark videos')));
      return;
    }
    setState(() => _bookmarkingInProgress = true);
    try {
      final r = await ApiService.toggleBookmark(widget.videoId);
      if (!mounted) return;
      setState(() => _bookmarked = r['bookmarked'] as bool);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_bookmarked ? 'Bookmarked' : 'Bookmark removed'),
        duration: const Duration(seconds: 1),
      ));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _bookmarkingInProgress = false);
    }
  }

  String _buildShareUrl() {
    if (kIsWeb) {
      final uri = Uri.base;
      final isDefaultPort = (uri.scheme == 'http' && uri.port == 80) ||
          (uri.scheme == 'https' && uri.port == 443);
      final origin = '${uri.scheme}://${uri.host}${isDefaultPort ? '' : ':${uri.port}'}';
      return '$origin/watch/${widget.videoId}';
    }
    return '${ApiConfig.baseUrl}/watch/${widget.videoId}';
  }

  Future<void> _shareVideo() async {
    final url = _buildShareUrl();
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Link copied to clipboard')));
      }
    } else {
      final title = _video?.title ?? 'Check out this video on VidMez';
      await Share.share('$title\n$url');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Play controls
  // ─────────────────────────────────────────────────────────────
  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _togglePlayPause() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
      _hideTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      c.play();
      _resetHideTimer();
    }
  }

  void _skip(int seconds) {
    final c = _controller;
    if (c == null) return;
    final next = c.value.position + Duration(seconds: seconds);
    final clamped = next < Duration.zero
        ? Duration.zero
        : (next > c.value.duration ? c.value.duration : next);
    c.seekTo(clamped);
    _resetHideTimer();
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null) return;
    if (_muted) {
      final v = _volume > 0 ? _volume : 1.0;
      c.setVolume(v);
      // Also clear _autoMuted so the "Tap to unmute" badge disappears.
      setVideoElementMuted(false); // restore DOM muted state
      setState(() { _muted = false; _autoMuted = false; _volume = v; });
    } else {
      c.setVolume(0);
      setState(() => _muted = true);
    }
    _resetHideTimer();
  }

  void _setVolume(double v) {
    _controller?.setVolume(v);
    setState(() { _volume = v; _muted = v == 0; if (v > 0) _autoMuted = false; });
    _resetHideTimer();
  }

  // ─────────────────────────────────────────────────────────────
  // Mode switching
  // Only the SizedBox height around VideoPlayer changes — the
  // VideoPlayer widget stays at the same tree position → no pause.
  // ─────────────────────────────────────────────────────────────
  void _setSizeMode(_SizeMode mode) {
    setState(() => _sizeMode = mode);
    if (mode == _SizeMode.fullscreen) {
      // Mobile: hide status/nav bars
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      // Web: ask browser to go fullscreen (hides address bar, tabs, etc.)
      enterBrowserFullscreen();
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      exitBrowserFullscreen();
    }
    _resetHideTimer();
  }

  Future<void> _toggleLike() async {
    if (!context.read<AuthProvider>().isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to like videos')));
      return;
    }
    setState(() => _likingInProgress = true);
    try {
      final r = await ApiService.toggleLike(widget.videoId);
      if (!mounted) return;
      setState(() {
        _liked = r['liked'] as bool;
        _likeCount = r['count'] as int;
      });
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _likingInProgress = false);
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ─────────────────────────────────────────────────────────────
  // Build — always PopScope > Scaffold so VideoPlayer stays at
  // an identical position in the element tree on every mode change.
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _sizeMode == _SizeMode.tile,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _setSizeMode(
            _sizeMode == _SizeMode.fullscreen ? _SizeMode.theater : _SizeMode.tile);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // AppBar visible in tile AND theater (stretch).
        // Hidden only in fullscreen so the two expanded modes look different.
        appBar: _sizeMode == _SizeMode.fullscreen
            ? null
            : AppBar(
                title: _loadingVideo
                    ? const Text('Loading...')
                    : (_videoError != null
                        ? const Text('Error')
                        : Text(_video?.title ?? '',
                            overflow: TextOverflow.ellipsis)),
              ),
        body: _loadingVideo
            ? const Center(child: CircularProgressIndicator())
            : _videoError != null
                ? _buildError()
                : _buildBody(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Body
  // ─────────────────────────────────────────────────────────────
  Widget _buildBody() {
    return LayoutBuilder(builder: (context, constraints) {
      final double w = constraints.maxWidth;
      final double h = constraints.maxHeight;

      final double playerH = switch (_sizeMode) {
        // Tile: compact 16:9 box
        _SizeMode.tile => (w * 9 / 16).clamp(180.0, h * 0.5),
        // Theater: fills body below the AppBar (AppBar still visible)
        _SizeMode.theater => h,
        // Fullscreen: fills entire body (AppBar removed, browser fullscreen)
        _SizeMode.fullscreen => h,
      };

      return Column(
        // Stretch ensures the player SizedBox fills the full width
        // and is flush to the left edge — not centred by the Column.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Player — always child[0], only its SizedBox height changes
          SizedBox(
            width: double.infinity,
            height: playerH,
            child: _buildPlayerArea(),
          ),

          // ── Metadata + comments — tile mode only
          if (_sizeMode == _SizeMode.tile)
            Expanded(child: SingleChildScrollView(child: _buildMeta())),
        ],
      );
    });
  }

  // ─────────────────────────────────────────────────────────────
  // Player area
  // Layering:
  //   1. black background
  //   2. thumbnail (before ready)
  //   3. VideoPlayer widget
  //   4. buffering / init spinners
  //   5. TOP BAR  — ALWAYS VISIBLE  (mode buttons + back/title in expanded)
  //   6. PLAY CONTROLS — AUTO-HIDING (centre buttons + seek + volume)
  // ─────────────────────────────────────────────────────────────
  Widget _buildPlayerArea() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _resetHideTimer,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Black bg
          Container(color: Colors.black),

          // 2. Thumbnail
          if (_video?.thumbnailUrl != null && !_playerInitialized)
            Positioned.fill(
              child: Image.network(
                _video!.thumbnailUrl!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),

          // 3. Video frame
          if (_playerInitialized && _controller != null)
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),

          // 4a. Mid-playback buffering spinner
          if (_playerInitialized &&
              _controller != null &&
              _controller!.value.isBuffering)
            const Center(
              child: CircularProgressIndicator(
                  color: Colors.white54, strokeWidth: 2),
            ),

          // 4b. Init spinner (no thumbnail)
          if (!_playerInitialized && _video?.thumbnailUrl == null)
            const Center(
                child: CircularProgressIndicator(color: Colors.white54)),

          // 5. TOP BAR — always visible, not inside AnimatedOpacity
          Positioned(
            top: 0, left: 0, right: 0,
            child: _buildTopBar(),
          ),

          // 6. PLAY CONTROLS — auto-hide after 3 s while playing
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: _buildPlayControls(),
          ),

          // 7. "Tap to unmute" badge — visible while browser auto-muted the video
          if (_autoMuted && _playerInitialized && (_controller?.value.isPlaying ?? false))
            Positioned(
              bottom: 72,
              left: 12,
              child: GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.volume_off, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text('Tap to unmute',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Top bar — ALWAYS VISIBLE
  // Contains: back arrow + title (expanded modes) + 3 mode buttons
  // ─────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xDD000000), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Row(
        children: [
          // Back arrow + title (theater / fullscreen only)
          if (_sizeMode != _SizeMode.tile) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              tooltip: 'Exit',
              onPressed: () => _setSizeMode(
                _sizeMode == _SizeMode.fullscreen
                    ? _SizeMode.theater
                    : _SizeMode.tile,
              ),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _video?.title ?? '',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else
            const Spacer(),

          // ── Mode buttons (always visible) ──────────────────
          _modeBtn(Icons.crop_square, _SizeMode.tile, 'Tile'),
          _modeBtn(Icons.fit_screen, _SizeMode.theater, 'Stretch'),
          _modeBtn(Icons.fullscreen, _SizeMode.fullscreen, 'Full Screen'),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _modeBtn(IconData icon, _SizeMode mode, String tooltip) {
    final active = _sizeMode == mode;
    return IconButton(
      icon: Icon(icon,
          color: active ? const Color(0xFF1E88E5) : Colors.white70, size: 20),
      tooltip: tooltip,
      onPressed: () => _setSizeMode(mode),
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Play controls — AUTO-HIDING
  // Contains: centre skip/play + bottom seek bar + volume
  // Does NOT contain the top bar (that's always visible above).
  // ─────────────────────────────────────────────────────────────
  Widget _buildPlayControls() {
    return Stack(
      children: [
        // Centre: skip-back | play-pause | skip-forward
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ctrlBtn(Icons.replay_10, () => _skip(-10), 30),
              const SizedBox(width: 20),
              _ctrlBtn(
                _controller?.value.isPlaying ?? false
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                _playerInitialized ? _togglePlayPause : null,
                52,
              ),
              const SizedBox(width: 20),
              _ctrlBtn(Icons.forward_10, () => _skip(10), 30),
            ],
          ),
        ),

        // Bottom gradient + seek bar + volume
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 28, 12, 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xCC000000), Colors.transparent],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSeekRow(),
                const SizedBox(height: 6),
                _buildBottomBar(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Seek row
  // ─────────────────────────────────────────────────────────────
  Widget _buildSeekRow() {
    if (!_playerInitialized || _controller == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0:00',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
              Text('--:--',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: const LinearProgressIndicator(
              backgroundColor: Colors.white12,
              color: Color(0xFF1E88E5),
              minHeight: 3,
            ),
          ),
        ],
      );
    }

    final dur = _controller!.value.duration;
    final durMs = dur.inMilliseconds.toDouble();
    final posMs = _seeking
        ? _seekRatio * durMs
        : _controller!.value.position.inMilliseconds.toDouble();
    final ratio = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

    final buffered = _controller!.value.buffered;
    final buffRatio = (durMs > 0 && buffered.isNotEmpty)
        ? (buffered.last.end.inMilliseconds / durMs).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_fmt(Duration(milliseconds: posMs.round())),
                style: const TextStyle(color: Colors.white, fontSize: 11)),
            Text(_fmt(dur),
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (ctx, box) {
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 3,
                decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Container(
                height: 3,
                width: box.maxWidth * buffRatio,
                decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Container(
                height: 3,
                width: box.maxWidth * ratio,
                decoration: BoxDecoration(
                    color: const Color(0xFF1E88E5),
                    borderRadius: BorderRadius.circular(2)),
              ),
              SliderTheme(
                data: SliderTheme.of(ctx).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 16),
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white24,
                ),
                child: Slider(
                  value: ratio,
                  onChangeStart: (_) {
                    _hideTimer?.cancel();
                    setState(() => _seeking = true);
                  },
                  onChanged: (v) => setState(() => _seekRatio = v),
                  onChangeEnd: (v) {
                    final target =
                        Duration(milliseconds: (v * durMs).round());
                    _controller!.seekTo(target);
                    setState(() { _seeking = false; _seekRatio = 0; });
                    _resetHideTimer();
                  },
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Bottom bar: volume icon + slider
  // ─────────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    final vol =
        _muted ? 0.0 : (_controller?.value.volume ?? _volume).clamp(0.0, 1.0);
    final volIcon = vol == 0
        ? Icons.volume_off
        : (vol < 0.5 ? Icons.volume_down : Icons.volume_up);

    return Row(
      children: [
        GestureDetector(
          onTap: _toggleMute,
          child: Icon(volIcon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 80,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white30,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
            ),
            child: Slider(value: vol, onChanged: _setVolume),
          ),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _ctrlBtn(IconData icon, VoidCallback? onTap, double size) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
            color: Colors.black38, shape: BoxShape.circle),
        padding: EdgeInsets.all(size > 40 ? 10 : 7),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_videoError!,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Metadata + comments (tile mode only)
  // ─────────────────────────────────────────────────────────────
  Widget _buildMeta() {
    final v = _video!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(v.title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.visibility, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text('${v.viewCount} views',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(DateFormat('MMM d, y').format(v.createdAt),
                    style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              ]),
              if (v.is18Plus)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.red[700],
                      borderRadius: BorderRadius.circular(4)),
                  child: const Text('18+',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF1E88E5),
                child: Text(v.user.email[0].toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(v.user.email.split('@').first,
                    style: const TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w500)),
              ),
              if (v.likesEnabled)
                InkWell(
                  onTap: _likingInProgress ? null : _toggleLike,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _liked
                          ? const Color(0xFF1E88E5)
                          : const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                            _liked
                                ? Icons.thumb_up
                                : Icons.thumb_up_outlined,
                            size: 16,
                            color: Colors.white),
                        const SizedBox(width: 6),
                        Text('$_likeCount',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _bookmarkingInProgress ? null : _toggleBookmark,
                tooltip: _bookmarked ? 'Remove bookmark' : 'Bookmark',
                icon: Icon(
                  _bookmarked ? Icons.bookmark : Icons.bookmark_border,
                  color: _bookmarked ? const Color(0xFF1E88E5) : Colors.white70,
                ),
              ),
              IconButton(
                onPressed: _shareVideo,
                tooltip: 'Share',
                icon: const Icon(Icons.share, color: Colors.white70),
              ),
            ],
          ),
          if (v.description != null && v.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF2A2A2A)),
            const SizedBox(height: 8),
            Text(v.description!,
                style: TextStyle(color: Colors.grey[300], fontSize: 14)),
          ],
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF2A2A2A)),
          CommentSection(
            videoId: widget.videoId,
            commentsEnabled: v.commentsEnabled,
          ),
        ],
      ),
    );
  }
}
