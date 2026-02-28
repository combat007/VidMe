import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/comment.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class CommentSection extends StatefulWidget {
  final String videoId;
  final bool commentsEnabled;

  const CommentSection({
    super.key,
    required this.videoId,
    required this.commentsEnabled,
  });

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  final List<Comment> _comments = [];
  bool _loading = true;
  bool _hasMore = true;
  int _page = 1;
  final _commentController = TextEditingController();
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _comments.clear();
        _page = 1;
        _hasMore = true;
      });
    }
    if (!_hasMore) return;

    setState(() => _loading = true);
    try {
      final result = await ApiService.getComments(widget.videoId, page: _page);
      final raw = result['comments'] as List<dynamic>;
      final pagination = result['pagination'] as Map<String, dynamic>;
      final newComments = raw.map((c) => Comment.fromJson(c as Map<String, dynamic>)).toList();
      setState(() {
        _comments.addAll(newComments);
        _page++;
        _hasMore = _page <= (pagination['totalPages'] as int);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);
    try {
      final comment = await ApiService.addComment(widget.videoId, text);
      _commentController.clear();
      setState(() => _comments.insert(0, comment));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      setState(() => _posting = false);
    }
  }

  Future<void> _deleteComment(Comment comment) async {
    try {
      await ApiService.deleteComment(widget.videoId, comment.id);
      setState(() => _comments.remove(comment));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Comments',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),

        // Disabled notice
        if (!widget.commentsEnabled)
          const Text('Comments are disabled for this video.',
              style: TextStyle(color: Colors.grey)),

        // Input
        if (widget.commentsEnabled && auth.isAuthenticated)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  decoration: const InputDecoration(
                    hintText: 'Add a comment...',
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                  style: const TextStyle(color: Colors.white),
                  maxLines: null,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _posting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, color: Color(0xFF1E88E5)),
                onPressed: _posting ? null : _postComment,
              ),
            ],
          ),

        if (widget.commentsEnabled && !auth.isAuthenticated)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Log in to comment.', style: TextStyle(color: Colors.grey)),
          ),

        const SizedBox(height: 12),

        // Comments list
        ..._comments.map((comment) => _CommentTile(
              comment: comment,
              currentUserId: auth.user?.id,
              onDelete: () => _deleteComment(comment),
            )),

        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),

        if (_hasMore && !_loading && _comments.isNotEmpty)
          TextButton(
            onPressed: _loadComments,
            child: const Text('Load more comments'),
          ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final String? currentUserId;
  final VoidCallback onDelete;

  const _CommentTile({
    required this.comment,
    required this.currentUserId,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isOwn = comment.userId == currentUserId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF2A2A2A),
            child: Text(
              comment.user.email[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.user.email.split('@').first,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (isOwn)
                      GestureDetector(
                        onTap: onDelete,
                        child: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.content,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
