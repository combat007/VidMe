import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/math_captcha.dart';
import 'oauth_age_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _ageController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  bool _oauthLoading = false;

  String? _captchaId;
  int? _captchaAnswer;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_captchaId == null || _captchaAnswer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please answer the captcha')),
      );
      return;
    }

    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.signup(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      age: int.parse(_ageController.text),
      captchaId: _captchaId!,
      captchaAnswer: _captchaAnswer!,
    );

    if (mounted) {
      if (ok) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(auth.error ?? 'Signup failed'),
          backgroundColor: Colors.red[700],
        ));
      }
    }
  }

  Future<void> _signupWithGoogle() async {
    setState(() => _oauthLoading = true);
    final auth = context.read<AuthProvider>();
    final result = await auth.loginWithGoogle();
    if (!mounted) return;
    setState(() => _oauthLoading = false);

    if (result == null) {
      if (auth.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(auth.error!),
          backgroundColor: Colors.red[700],
        ));
      }
      return;
    }

    if (result.needsAge) {
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => OAuthAgeScreen(
          pendingToken: result.pendingToken!,
          email: result.email ?? '',
        ),
      ));
    }
    if (mounted && auth.isAuthenticated) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _signupWithGitHub() async {
    setState(() => _oauthLoading = true);
    final auth = context.read<AuthProvider>();
    final result = await auth.loginWithGitHub();
    if (!mounted) return;
    setState(() => _oauthLoading = false);

    if (result == null) {
      if (auth.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(auth.error!),
          backgroundColor: Colors.red[700],
        ));
      }
      return;
    }

    if (result.needsAge) {
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => OAuthAgeScreen(
          pendingToken: result.pendingToken!,
          email: result.email ?? '',
        ),
      ));
    }
    if (mounted && auth.isAuthenticated) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
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
                    const Icon(Icons.play_circle_filled,
                        size: 56, color: Color(0xFF1E88E5)),
                    const SizedBox(height: 24),

                    // ── OAuth buttons ────────────────────────────────────
                    _OAuthButton(
                      label: 'Continue with Google',
                      icon: _GoogleIcon(),
                      loading: _oauthLoading,
                      onPressed: _signupWithGoogle,
                    ),
                    const SizedBox(height: 12),
                    _OAuthButton(
                      label: 'Continue with GitHub',
                      icon: _GitHubIcon(),
                      loading: _oauthLoading,
                      onPressed: _signupWithGitHub,
                    ),

                    // ── divider ──────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Row(children: [
                        Expanded(child: Divider(color: Colors.grey[700])),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('or sign up with email',
                              style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                        ),
                        Expanded(child: Divider(color: Colors.grey[700])),
                      ]),
                    ),

                    // ── Email ────────────────────────────────────────────
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Email is required';
                        if (!v.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── Password ─────────────────────────────────────────
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Password is required';
                        if (v.length < 8) return 'Minimum 8 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── Age ──────────────────────────────────────────────
                    TextFormField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Age',
                        prefixIcon: Icon(Icons.cake_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Age is required';
                        final age = int.tryParse(v);
                        if (age == null) return 'Enter a valid age';
                        if (age < 13) return 'You must be at least 13 to sign up';
                        if (age > 120) return 'Enter a valid age';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── Captcha ──────────────────────────────────────────
                    MathCaptcha(
                      onChanged: (id, answer) {
                        _captchaId = id;
                        _captchaAnswer = answer;
                      },
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: _loading ? null : _signup,
                      child: _loading
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Create Account'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Already have an account?',
                            style: TextStyle(color: Colors.grey[400])),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Log In'),
                        ),
                      ],
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

// ── reused widgets (same as login_screen) ─────────────────────────────────────

class _OAuthButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final bool loading;
  final VoidCallback onPressed;

  const _OAuthButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey[700]!),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20,
        height: 20,
        child: Center(
          child: Text('G',
              style: TextStyle(
                  color: Color(0xFFDB4437),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  height: 1)),
        ),
      );
}

class _GitHubIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 20,
        height: 20,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: const Center(
          child: Text('GH',
              style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 7,
                  height: 1)),
        ),
      );
}
