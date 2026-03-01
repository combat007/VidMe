import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class OAuthAgeScreen extends StatefulWidget {
  final String pendingToken;
  final String email;

  const OAuthAgeScreen({
    super.key,
    required this.pendingToken,
    required this.email,
  });

  @override
  State<OAuthAgeScreen> createState() => _OAuthAgeScreenState();
}

class _OAuthAgeScreenState extends State<OAuthAgeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ageController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final auth = context.read<AuthProvider>();
    final ok = await auth.completeOAuth(
      pendingToken: widget.pendingToken,
      age: int.parse(_ageController.text),
    );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(auth.error ?? 'Failed to complete sign-up'),
        backgroundColor: Colors.red[700],
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('One Last Step')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const Icon(Icons.cake_outlined,
                        size: 56, color: Color(0xFF1E88E5)),
                    const SizedBox(height: 24),
                    Text(
                      'Welcome, ${widget.email}',
                      style: const TextStyle(
                          fontSize: 16, color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'We need your age to complete sign-up.',
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Age',
                        prefixIcon: Icon(Icons.cake_outlined),
                      ),
                      autofocus: true,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Age is required';
                        final age = int.tryParse(v);
                        if (age == null) return 'Enter a valid age';
                        if (age < 13) return 'You must be at least 13 to sign up';
                        if (age > 120) return 'Enter a valid age';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Continue'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
