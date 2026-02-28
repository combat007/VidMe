import 'package:flutter/material.dart';
import '../services/api_service.dart';

class MathCaptcha extends StatefulWidget {
  final void Function(String captchaId, int answer) onChanged;

  const MathCaptcha({super.key, required this.onChanged});

  @override
  State<MathCaptcha> createState() => _MathCaptchaState();
}

class _MathCaptchaState extends State<MathCaptcha> {
  String? _captchaId;
  String? _question;
  bool _loading = true;
  String? _error;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCaptcha();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadCaptcha() async {
    setState(() {
      _loading = true;
      _error = null;
      _controller.clear();
    });
    try {
      final data = await ApiService.getCaptcha();
      setState(() {
        _captchaId = data['id'] as String;
        _question = data['question'] as String;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load captcha';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 56,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Row(
        children: [
          Text(_error!, style: const TextStyle(color: Colors.red)),
          TextButton(onPressed: _loadCaptcha, child: const Text('Retry')),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Captcha: $_question = ?',
                  hintText: 'Enter the answer',
                ),
                onChanged: (val) {
                  final answer = int.tryParse(val);
                  if (answer != null && _captchaId != null) {
                    widget.onChanged(_captchaId!, answer);
                  }
                },
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Please answer the captcha';
                  if (int.tryParse(val) == null) return 'Enter a number';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh captcha',
              icon: const Icon(Icons.refresh),
              onPressed: _loadCaptcha,
            ),
          ],
        ),
      ],
    );
  }
}
