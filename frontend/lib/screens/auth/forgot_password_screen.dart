import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  // Step 1 — email
  final _emailController = TextEditingController();

  // Step 2 — OTP + new password
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _step2 = false; // false = enter email, true = enter OTP + new password
  bool _loading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError('Enter a valid email address');
      return;
    }
    setState(() => _loading = true);
    try {
      await ApiService.forgotPassword(email);
      if (!mounted) return;
      setState(() { _step2 = true; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) { _showError(e.message); setState(() => _loading = false); }
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();
    final newPw = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (otp.length != 6) { _showError('Enter the 6-digit code'); return; }
    if (newPw.length < 8) { _showError('Password must be at least 8 characters'); return; }
    if (newPw != confirm) { _showError('Passwords do not match'); return; }

    setState(() => _loading = true);
    try {
      await ApiService.resetPassword(email: email, otp: otp, newPassword: newPw);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset! You can now log in.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) { _showError(e.message); setState(() => _loading = false); }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                children: [
                  const Icon(Icons.lock_reset, size: 64, color: Color(0xFF1E88E5)),
                  const SizedBox(height: 16),
                  Text(
                    _step2
                        ? 'Check your email'
                        : 'Forgot your password?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _step2
                        ? 'Enter the 6-digit code sent to ${_emailController.text.trim()} and choose a new password.'
                        : 'Enter your account email and we\'ll send you a reset code.',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // ── Step 1: email field (always shown but locked in step 2)
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    readOnly: _step2,
                    style: TextStyle(
                        color: _step2 ? Colors.white54 : Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      suffixIcon: _step2
                          ? IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              tooltip: 'Change email',
                              onPressed: () => setState(() {
                                _step2 = false;
                                _otpController.clear();
                                _newPasswordController.clear();
                                _confirmPasswordController.clear();
                              }),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Step 2: OTP + new password fields
                  if (_step2) ...[
                    TextFormField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          letterSpacing: 8,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: '6-digit code',
                        counterText: '',
                        prefixIcon: Icon(Icons.pin_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: _obscureNew,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'New password',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureNew
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              setState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Confirm new password',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Action button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _loading
                          ? null
                          : (_step2 ? _resetPassword : _sendCode),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_step2 ? 'Reset Password' : 'Send Reset Code'),
                    ),
                  ),

                  if (_step2) ...[
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _loading ? null : _sendCode,
                      child: const Text("Didn't receive a code? Resend"),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
