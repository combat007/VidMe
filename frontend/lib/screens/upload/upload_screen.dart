import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/api_service.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  // Step 0 = pick file, 1 = uploading, 2 = fill metadata, 3 = publishing
  int _step = 0;

  PlatformFile? _pickedFile;
  VideoPlayerController? _previewController;
  bool _previewInitialized = false;

  // Upload result
  String? _ipfsCid;
  String? _gatewayUrl;
  int? _duration;
  double _uploadProgress = 0;
  String? _uploadError;

  // Thumbnail
  String? _thumbnailCid;
  String? _thumbnailUrl;
  String? _customThumbnailCid;
  String? _customThumbnailUrl;
  bool _uploadingThumbnail = false;

  // Form fields
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _is18Plus = false;
  bool _likesEnabled = true;
  bool _commentsEnabled = true;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _previewController?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: true, // required on web; bytes always populated
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      _pickedFile = result.files.first;
      _step = 0;
      _uploadError = null;
    });
    await _uploadVideo();
  }

  Future<void> _uploadVideo() async {
    if (_pickedFile == null) return;

    final bytes = _pickedFile!.bytes;
    if (bytes == null) {
      setState(() {
        _uploadError = 'Could not read file data. Please try again.';
        _step = 0;
      });
      return;
    }

    setState(() {
      _step = 1;
      _uploadProgress = 0;
      _uploadError = null;
    });

    try {
      final result = await ApiService.uploadVideoBytes(
        bytes,
        _pickedFile!.name,
        onProgress: (sent, total) {
          if (total > 0) {
            setState(() => _uploadProgress = sent / total);
          }
        },
      );

      _ipfsCid = result['cid'] as String;
      _gatewayUrl = result['gatewayUrl'] as String;
      _duration = result['duration'] as int;
      _thumbnailCid = result['thumbnailCid'] as String?;
      _thumbnailUrl = result['thumbnailUrl'] as String?;

      // Initialize preview player
      _previewController = VideoPlayerController.networkUrl(Uri.parse(_gatewayUrl!));
      await _previewController!.initialize();
      setState(() {
        _previewInitialized = true;
        _step = 2;
      });
    } on ApiException catch (e) {
      setState(() {
        _uploadError = e.message;
        _step = 0;
      });
    } catch (e) {
      setState(() {
        _uploadError = 'Upload failed: $e';
        _step = 0;
      });
    }
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    if (_ipfsCid == null || _duration == null) return;

    setState(() => _step = 3);
    try {
      await ApiService.createVideo(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        ipfsCid: _ipfsCid!,
        thumbnailCid: _customThumbnailCid ?? _thumbnailCid,
        duration: _duration!,
        is18Plus: _is18Plus,
        likesEnabled: _likesEnabled,
        commentsEnabled: _commentsEnabled,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video published successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      setState(() => _step = 2);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red[700]),
        );
      }
    }
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Video'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_step == 0) _buildPickStep(),
                if (_step == 1) _buildUploadingStep(),
                if (_step == 2 || _step == 3) _buildMetadataStep(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPickStep() {
    return Column(
      children: [
        GestureDetector(
          onTap: _pickVideo,
          child: Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3A3A3A), width: 2),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.upload_file, size: 64, color: Color(0xFF1E88E5)),
                SizedBox(height: 12),
                Text(
                  'Tap to select a video',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'MP4, WebM, MOV — 1 min to 6 hours',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        if (_uploadError != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[900]!.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[700]!),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_uploadError!,
                      style: const TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUploadingStep() {
    return Column(
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.cloud_upload, size: 64, color: Color(0xFF1E88E5)),
        const SizedBox(height: 24),
        const Text(
          'Uploading to IPFS...',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        const SizedBox(height: 24),
        LinearProgressIndicator(
          value: _uploadProgress > 0 ? _uploadProgress : null,
          backgroundColor: const Color(0xFF2A2A2A),
          valueColor: const AlwaysStoppedAnimation(Color(0xFF1E88E5)),
        ),
        const SizedBox(height: 12),
        Text(
          _uploadProgress > 0
              ? '${(_uploadProgress * 100).toStringAsFixed(0)}%'
              : 'Processing...',
          style: const TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildMetadataStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Preview
          if (_previewInitialized && _previewController != null)
            Column(
              children: [
                AspectRatio(
                  aspectRatio: _previewController!.value.aspectRatio,
                  child: VideoPlayer(_previewController!),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        _previewController!.value.isPlaying
                            ? Icons.pause_circle
                            : Icons.play_circle,
                        color: Colors.white,
                        size: 36,
                      ),
                      onPressed: () {
                        setState(() {
                          _previewController!.value.isPlaying
                              ? _previewController!.pause()
                              : _previewController!.play();
                        });
                      },
                    ),
                    if (_duration != null)
                      Text(
                        'Duration: ${_formatDuration(_duration!)}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),

          // Thumbnail
          _buildThumbnailSection(),
          const SizedBox(height: 16),

          // Title
          TextFormField(
            controller: _titleController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Title *',
              prefixIcon: Icon(Icons.title),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Title is required';
              if (v.trim().length > 200) return 'Title too long (max 200 chars)';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Description
          TextFormField(
            controller: _descriptionController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              prefixIcon: Icon(Icons.description_outlined),
              alignLabelWithHint: true,
            ),
            maxLines: 4,
          ),
          const SizedBox(height: 20),

          // Toggles
          const Text('Settings',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          _buildToggle(
            icon: Icons.eighteen_up_rating,
            label: '18+ Content',
            sublabel: 'Only users aged 18+ can watch',
            value: _is18Plus,
            onChanged: (v) => setState(() => _is18Plus = v),
          ),
          _buildToggle(
            icon: Icons.thumb_up_outlined,
            label: 'Enable Likes',
            value: _likesEnabled,
            onChanged: (v) => setState(() => _likesEnabled = v),
          ),
          _buildToggle(
            icon: Icons.comment_outlined,
            label: 'Enable Comments',
            value: _commentsEnabled,
            onChanged: (v) => setState(() => _commentsEnabled = v),
          ),

          const SizedBox(height: 32),

          // Publish button
          ElevatedButton.icon(
            onPressed: _step == 3 ? null : _publish,
            icon: _step == 3
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.publish),
            label: Text(_step == 3 ? 'Publishing...' : 'Publish Video'),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailSection() {
    final thumbUrl = _customThumbnailUrl ?? _thumbnailUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Thumbnail',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: thumbUrl != null
                ? CachedNetworkImage(
                    imageUrl: thumbUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: const Color(0xFF2A2A2A)),
                    errorWidget: (_, __, ___) => _thumbPlaceholder(),
                  )
                : _thumbPlaceholder(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _uploadingThumbnail ? null : _pickThumbnail,
          icon: _uploadingThumbnail
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.image_outlined, size: 16),
          label: const Text('Change Thumbnail'),
        ),
      ],
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: const Center(
        child: Icon(Icons.image_outlined, size: 40, color: Colors.white54),
      ),
    );
  }

  Future<void> _pickThumbnail() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read image file.')),
        );
      }
      return;
    }

    if (bytes.length > 200 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image too large (max 200 KB)'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _uploadingThumbnail = true);
    try {
      final res = await ApiService.uploadThumbnailBytes(bytes, file.name);
      setState(() {
        _customThumbnailCid = res['cid'] as String;
        _customThumbnailUrl = res['thumbnailUrl'] as String;
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      setState(() => _uploadingThumbnail = false);
    }
  }

  Widget _buildToggle({
    required IconData icon,
    required String label,
    String? sublabel,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SwitchListTile(
        secondary: Icon(icon, color: Colors.grey),
        title: Text(label, style: const TextStyle(color: Colors.white)),
        subtitle:
            sublabel != null ? Text(sublabel, style: const TextStyle(color: Colors.grey, fontSize: 12)) : null,
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF1E88E5),
      ),
    );
  }
}
