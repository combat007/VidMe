import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';
import 'oauth_age_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  bool _oauthLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final auth = context.read<AuthProvider>();
    final ok = await auth.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (mounted) {
      if (ok) {
        Navigator.pop(context);
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(auth.error ?? 'Login failed'),
          backgroundColor: Colors.red[700],
        ));
      }
    }
  }

  Future<void> _loginWithGoogle() async {
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
    if (mounted && auth.isAuthenticated) Navigator.pop(context);
  }

  Future<void> _loginWithGitHub() async {
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
    if (mounted && auth.isAuthenticated) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    const Icon(Icons.play_circle_filled,
                        size: 72, color: Color(0xFF1E88E5)),
                    const SizedBox(height: 8),
                    const Text('VidMez',
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    const SizedBox(height: 8),
                    Text('Share your world',
                        style: TextStyle(color: Colors.grey[400], fontSize: 16)),
                    const SizedBox(height: 32),

                    // ── OAuth buttons ──────────────────────────────────────
                    _OAuthButton(
                      label: 'Continue with Google',
                      icon: _GoogleIcon(),
                      loading: _oauthLoading,
                      onPressed: _loginWithGoogle,
                    ),
                    const SizedBox(height: 12),
                    _OAuthButton(
                      label: 'Continue with GitHub',
                      icon: _GitHubIcon(),
                      loading: _oauthLoading,
                      onPressed: _loginWithGitHub,
                    ),

                    // ── divider ────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Row(children: [
                        Expanded(child: Divider(color: Colors.grey[700])),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('or sign in with email',
                              style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                        ),
                        Expanded(child: Divider(color: Colors.grey[700])),
                      ]),
                    ),

                    // ── Email / password ───────────────────────────────────
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
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Log In'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Don't have an account?",
                            style: TextStyle(color: Colors.grey[400])),
                        TextButton(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const SignupScreen())),
                          child: const Text('Sign Up'),
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

// ── shared OAuth button widget ─────────────────────────────────────────────────

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

// ── provider brand icons (no extra package needed) ────────────────────────────

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text('G',
              style: TextStyle(
                  color: Color(0xFFDB4437),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  height: 1)),
        ],
      ),
    );
  }
}

class _GitHubIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
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
}
