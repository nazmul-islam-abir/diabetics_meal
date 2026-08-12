import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'home_shell.dart';

/// Combined login + signup screen.
///
/// Signup collects full name, mobile, email and password.
/// Login only needs email + password.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _signUpMode = false;
  bool _loading = false;
  String? _error;

  // Sign-up only
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();

  // Both modes
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'ইমেইল ও পাসওয়ার্ড দিন');
      return;
    }
    if (_signUpMode) {
      final name = _nameCtrl.text.trim();
      final mobile = _mobileCtrl.text.trim();
      if (name.isEmpty) {
        setState(() => _error = 'আপনার নাম লিখুন');
        return;
      }
      if (mobile.length < 8) {
        setState(() => _error = 'মোবাইল নম্বর সঠিকভাবে দিন');
        return;
      }
    }
    setState(() { _loading = true; _error = null; });
    try {
      if (_signUpMode) {
        await SupabaseService.signUp(
          email: email,
          password: pass,
          fullName: _nameCtrl.text.trim(),
          mobile: _mobileCtrl.text.trim(),
        );
      } else {
        await SupabaseService.signIn(email, pass);
      }
      _goNext();
    } catch (e) {
      setState(() => _error = '${_signUpMode ? "অ্যাকাউন্ট তৈরি" : "লগইন"} ব্যর্থ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goNext() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('আমার ডায়েট')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 8),
              const Icon(Icons.restaurant_menu, size: 56, color: Color(0xFF0F6E56)),
              const SizedBox(height: 8),
              const Text('স্বাগতম',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                _signUpMode ? 'নতুন অ্যাকাউন্ট তৈরি করুন' : 'আপনার অ্যাকাউন্টে লগইন করুন',
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 20),
              if (_signUpMode) ...[
                _field(
                  ctrl: _nameCtrl,
                  label: 'আপনার নাম',
                  icon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                _field(
                  ctrl: _mobileCtrl,
                  label: 'মোবাইল নম্বর',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  hint: '01XXXXXXXXX',
                ),
                const SizedBox(height: 12),
              ],
              _field(
                ctrl: _emailCtrl,
                label: 'ইমেইল',
                icon: Icons.mail_outline,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _field(
                ctrl: _passCtrl,
                label: 'পাসওয়ার্ড',
                icon: Icons.lock_outline,
                obscureText: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 14)),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_signUpMode ? 'অ্যাকাউন্ট তৈরি করুন' : 'লগইন'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => setState(() {
                          _signUpMode = !_signUpMode;
                          _error = null;
                        }),
                child: Text(
                  _signUpMode
                      ? 'ইতোমধ্যে অ্যাকাউন্ট আছে? লগইন করুন'
                      : 'প্রথমবার? নতুন অ্যাকাউন্ট তৈরি করুন',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? hint,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
