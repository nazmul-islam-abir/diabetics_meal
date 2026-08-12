import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import 'home_shell.dart';

/// Editorial-style auth.
///
/// Visually a single black panel that gently "thickness" itself on the mode
/// toggle, with the right-hand form sliding up underneath.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  bool _signUpMode = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _errorField;

  // Sign-up only
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();

  // Both modes
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  // Animation: drives the right panel "lift" and color crossfade.
  late final AnimationController _entry;
  late final Animation<double> _lift;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(vsync: this, duration: AppMotion.long)..forward();
    _lift = Tween<double>(begin: 28, end: 0).animate(
      CurvedAnimation(parent: _entry, curve: AppMotion.emphasized),
    );
    _fadeIn = CurvedAnimation(parent: _entry, curve: AppMotion.standard);
  }

  @override
  void dispose() {
    _entry.dispose();
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
      _setError('ইমেইল ও পাসওয়ার্ড দিন', field: 'auth');
      return;
    }
    if (_signUpMode) {
      final name = _nameCtrl.text.trim();
      final mobile = _mobileCtrl.text.trim();
      if (name.isEmpty) {
        _setError('আপনার নাম লিখুন', field: 'name');
        return;
      }
      if (mobile.length < 8) {
        _setError('মোবাইল নম্বর সঠিকভাবে দিন', field: 'mobile');
        return;
      }
    }
    setState(() {
      _loading = true;
      _error = null;
      _errorField = null;
    });
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
      if (!mounted) return;
      _goNext();
    } catch (e) {
      _setError(
        '${_signUpMode ? "অ্যাকাউন্ট তৈরি" : "লগইন"} ব্যর্থ: $e',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setError(String msg, {String? field}) {
    HapticFeedback.heavyImpact();
    setState(() {
      _error = msg;
      _errorField = field;
    });
  }

  void _goNext() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeShell(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: AppMotion.medium,
      ),
    );
  }

  void _toggleMode(bool signup) {
    if (_signUpMode == signup || _loading) return;
    HapticFeedback.selectionClick();
    setState(() {
      _signUpMode = signup;
      _error = null;
      _errorField = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final isWide = c.maxWidth > 720;
          if (isWide) {
            return Row(
              children: [
                Expanded(flex: 5, child: _buildHero()),
                Expanded(flex: 6, child: _buildForm()),
              ],
            );
          }
          return Column(
            children: [
              _buildHero(compact: true),
              Expanded(child: _buildForm()),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildHero({bool compact = false}) {
    return AnimatedBuilder(
      animation: _fadeIn,
      builder: (context, _) {
        return Opacity(
          opacity: _fadeIn.value,
          child: Container(
            color: AppColors.ink,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 24 : 56,
              vertical: compact ? 36 : 64,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.paper,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.grain,
                          color: AppColors.ink, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'আমার ডায়েট',
                      style: TextStyle(
                        color: AppColors.paper,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (!compact)
                  Text(
                    'ডায়াবেটিস-সহায়ক\nখাবারের পথে\nআপনার সঙ্গী',
                    style: TextStyle(
                      color: AppColors.paper,
                      fontSize: compact ? 32 : 56,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      letterSpacing: -1.0,
                    ),
                  ),
                if (compact) const SizedBox(height: 12),
                Text(
                  compact
                      ? 'ব্যক্তিগতকৃত পরিকল্পনা, সহজ ট্র্যাকিং।'
                      : 'ব্যক্তিগতকৃত খাবারের পরিকল্পনা, দৈনিক লগ, এবং স্বাস্থ্য-ভিত্তিক সুপারিশ — সব এক জায়গায়।',
                  style: TextStyle(
                    color: AppColors.paper.withValues(alpha: 0.78),
                    fontSize: compact ? 14 : 18,
                    height: 1.4,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    _heroBullet('বাংলাদেশী খাবার'),
                    const SizedBox(width: 18),
                    _heroBullet('বয়স্ক-বান্ধব'),
                    const SizedBox(width: 18),
                    _heroBullet('ফ্রি'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _heroBullet(String text) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.paper,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return AnimatedBuilder(
      animation: _lift,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _lift.value),
          child: child,
        );
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Overline(_signUpMode ? 'নতুন অ্যাকাউন্ট' : 'স্বাগতম ফিরে'),
            Text(
              _signUpMode ? 'অ্যাকাউন্ট তৈরি করুন' : 'লগইন করুন',
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -0.6,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _signUpMode
                  ? 'ব্যক্তিগতকৃত পরিকল্পনা পেতে কয়েকটি তথ্য দিন।'
                  : 'আপনার অ্যাকাউন্টে প্রবেশ করুন।',
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.smoke,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            Center(
              child: MonoSegmented<bool>(
                options: const [
                  (value: false, label: 'লগইন'),
                  (value: true, label: 'সাইন আপ'),
                ],
                selected: _signUpMode,
                onChanged: _toggleMode,
              ),
            ),
            const SizedBox(height: 28),
            AnimatedSize(
              duration: AppMotion.medium,
              curve: AppMotion.standard,
              child: Column(
                children: [
                  if (_signUpMode) ...[
                    _Input(
                      controller: _nameCtrl,
                      label: 'আপনার নাম',
                      hint: 'যেমন: রহিম মিয়া',
                      icon: Icons.person_outline,
                      hasError: _errorField == 'name',
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 14),
                    _Input(
                      controller: _mobileCtrl,
                      label: 'মোবাইল নম্বর',
                      hint: '01XXXXXXXXX',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      hasError: _errorField == 'mobile',
                    ),
                    const SizedBox(height: 14),
                  ],
                  _Input(
                    controller: _emailCtrl,
                    label: 'ইমেইল',
                    hint: 'example@mail.com',
                    icon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                    hasError: _errorField == 'auth',
                  ),
                  const SizedBox(height: 14),
                  _Input(
                    controller: _passCtrl,
                    label: 'পাসওয়ার্ড',
                    hint: 'কমপক্ষে ৬ অক্ষর',
                    icon: Icons.lock_outline,
                    obscureText: _obscure,
                    trailing: IconButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _obscure = !_obscure);
                      },
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      tooltip: _obscure ? 'দেখান' : 'লুকান',
                    ),
                    hasError: _errorField == 'auth',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AnimatedSwitcher(
              duration: AppMotion.short,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SizeTransition(
                  sizeFactor: anim,
                  axisAlignment: -1,
                  child: child,
                ),
              ),
              child: _error == null
                  ? const SizedBox(height: 0, key: ValueKey('no_error'))
                  : Padding(
                      key: ValueKey(_error),
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 18, color: AppColors.ink),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            MonoButton(
              label: _signUpMode ? 'অ্যাকাউন্ট তৈরি করুন' : 'লগইন',
              leading: _signUpMode ? Icons.person_add_alt_1 : Icons.arrow_forward,
              loading: _loading,
              onPressed: _submit,
            ),
            const SizedBox(height: 16),
            Center(
              child: Pressable(
                onTap: _loading ? null : () => _toggleMode(!_signUpMode),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text(
                    _signUpMode
                        ? 'ইতোমধ্যে অ্যাকাউন্ট আছে?  লগইন →'
                        : 'প্রথমবার?  নতুন অ্যাকাউন্ট তৈরি করুন →',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Input extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? trailing;
  final bool hasError;
  final TextCapitalization textCapitalization;

  const _Input({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.trailing,
    this.hasError = false,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.short,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: hasError
            ? [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.06),
                  blurRadius: 0,
                  offset: const Offset(0, 3),
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        textCapitalization: textCapitalization,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        cursorColor: AppColors.ink,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Icon(icon, size: 22),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: trailing,
        ),
      ),
    );
  }
}
