import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

/// Editorial-style auth.
///
/// Visually a single black panel that gently "thickness" itself on the mode
/// toggle, with the right-hand form sliding up underneath.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
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

  // Focus chain so "Next" jumps between fields and "Done" submits.
  final _nameFocus = FocusNode();
  final _mobileFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();

  // One-shot entry animation — starts at value=1 (i.e. fully visible) so
  // the first frame already shows the form. We briefly fade in only after
  // the layout pass completes, so we never collide with the keyboard or
  // the IME insets ticking.
  late final AnimationController _entry;
  late final Animation<double> _lift;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: AppMotion.medium,
      value: 1.0, // start visible — animation is purely cosmetic
    );
    _lift = Tween<double>(begin: 28, end: 0).animate(
      CurvedAnimation(parent: _entry, curve: AppMotion.emphasized),
    );
    _fadeIn = CurvedAnimation(parent: _entry, curve: AppMotion.standard);
  }

  @override
  void dispose() {
    _entry.dispose();
    _nameFocus.dispose();
    _mobileFocus.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
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
      String msg = e.toString();
      if (msg.contains('YOUR-PROJECT-REF') ||
          msg.contains('Failed host lookup')) {
        msg =
            'Supabase কনফিগারেশন সঠিক নয়। প্রজেক্টের .env ফাইলে আপনার URL ও Key সেট করেছেন কি?';
      }
      _setError(
        '${_signUpMode ? "অ্যাকাউন্ট তৈরি" : "লগইন"} ব্যর্থ: $msg',
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
    // No manual navigation — the root widget subscribes to
    // Supabase auth state changes and rebuilds the tree with HomeShell
    // as soon as the session is established. Manually pushing here
    // would double-mount HomeShell.
    return;
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
      // Transparent — the cosmos backdrop is painted in `main.dart`.
      backgroundColor: Colors.transparent,
      // Disable the keyboard-driven resize so the form doesn't keep relayouting
      // while the IME is animating in (that was the source of the "Skipped
      // 420 frames!" freeze).
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // Computed once per build. We deliberately do NOT call MediaQuery.of
    // inside the body — every IME-inset tick would otherwise rebuild the
    // whole auth screen and cause the Skipped 420 frames crash.
    final mq = MediaQuery.maybeOf(context);
    final width = mq?.size.width ?? 360.0;
    final height = mq?.size.height ?? 720.0;
    final isWide = width > 720;
    final heroHeight = math.max(320.0, height * 0.45);
    if (isWide) {
      return Row(
        children: [
          Expanded(flex: 5, child: _buildHero()),
          Expanded(flex: 6, child: _buildForm()),
        ],
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      // BouncingScrollPhysics lets the user scroll the form back into view
      // even when the keyboard is up (the inner SingleChildScrollView handles
      // the actual text-field overflow).
      physics: const BouncingScrollPhysics(),
      children: [
        // Fixed hero height — it scrolls out of view when the keyboard appears,
        // which is fine. Animating the hero height on every IME tick was the
        // root cause of the layout storm.
        SizedBox(
          height: heroHeight,
          child: _buildHero(compact: true),
        ),
        _buildForm(physics: const NeverScrollableScrollPhysics()),
      ],
    );
  }

  Widget _buildHero({bool compact = false}) {
    // The whole hero fades in once. Wrapping it in an AnimatedBuilder was
    // forcing a full subtree rebuild for every tick of the entry animation;
    // using AnimatedOpacity on the outermost widget is cheaper and quits
    // rebuilding once the tween finishes.
    return AnimatedBuilder(
      animation: _fadeIn,
      builder: (context, child) {
        return Opacity(opacity: _fadeIn.value.clamp(0.0, 1.0), child: child);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Local violet→cyan gradient — feels distinct from the global cosmos.
          const DecoratedBox(
              decoration: BoxDecoration(gradient: AppGradients.cosmos)),
          // Soft radial highlight from the top so the headline reads on top.
          Positioned(
            top: -60,
            left: -40,
            child: Container(
              width: 280,
              height: 280,
              decoration: const BoxDecoration(
                gradient: AppGradients.blobCyan,
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            right: -40,
            child: Container(
              width: 260,
              height: 260,
              decoration: const BoxDecoration(
                gradient: AppGradients.blobViolet,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 24 : 56,
              vertical: compact ? 28 : 56,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: AppGradients.aurora,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.cyan.withValues(alpha: 0.3),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.grain,
                          color: AppColors.void1, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'আমার ডায়েট',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (!compact)
                  const GradientTitle(
                    'ডায়াবেটিস-সহায়ক\nখাবারের পথে\nআপনার সঙ্গী',
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      letterSpacing: -1.0,
                    ),
                  ),
                if (compact)
                  const GradientTitle(
                    'ডায়াবেটিস-সহায়ক\nখাবারের পথে',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: -0.6,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  compact
                      ? 'ব্যক্তিগতকৃত পরিকল্পনা, সহজ ট্র্যাকিং।'
                      : 'ব্যক্তিগতকৃত খাবারের পরিকল্পনা, দৈনিক লগ, এবং স্বাস্থ্য-সম্মত সুপারিশ — সব এক জায়গায়।',
                  style: TextStyle(
                    color: AppColors.textMuted,
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
        ],
      ),
    );
  }

  Widget _heroBullet(String text) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            gradient: AppGradients.aurora,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildForm({ScrollPhysics? physics}) {
    // Wrap the whole form in a single AnimatedBuilder whose `child` is the
    // expensive subtree. Only the Transform itself rebuilds per animation
    // tick; the form below stays put.
    return AnimatedBuilder(
      animation: _lift,
      child: _buildFormBody(physics: physics),
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _lift.value),
          child: child,
        );
      },
    );
  }

  Widget _buildFormBody({ScrollPhysics? physics}) {
    // IMPORTANT: do not call MediaQuery.of(context) here. Doing so would
    // subscribe the form body to every IME-inset tick and rebuild the
    // entire subtree ~10× per keyboard animation, blowing past the 16ms
    // frame budget and producing the "Skipped 420 frames!" crash.
    //
    // The outer ListView already handles keyboard overflow — when the IME
    // pushes the focused field out of view, the user can scroll the outer
    // ListView (BouncingScrollPhysics) to bring it back.
    return SingleChildScrollView(
      physics: physics,
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
                    focusNode: _nameFocus,
                    label: 'আপনার নাম',
                    hint: 'যেমন: রহিম মিয়া',
                    icon: Icons.person_outline,
                    hasError: _errorField == 'name',
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _mobileFocus.requestFocus(),
                  ),
                  const SizedBox(height: 14),
                  _Input(
                    controller: _mobileCtrl,
                    focusNode: _mobileFocus,
                    label: 'মোবাইল নম্বর',
                    hint: '01XXXXXXXXX',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    hasError: _errorField == 'mobile',
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _emailFocus.requestFocus(),
                  ),
                  const SizedBox(height: 14),
                ],
                _Input(
                  controller: _emailCtrl,
                  focusNode: _emailFocus,
                  label: 'ইমেইল',
                  hint: 'example@mail.com',
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  hasError: _errorField == 'auth',
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _passFocus.requestFocus(),
                  autofocus: !_signUpMode,
                ),
                const SizedBox(height: 14),
                _Input(
                  controller: _passCtrl,
                  focusNode: _passFocus,
                  label: 'পাসওয়ার্ড',
                  hint: 'কমপক্ষে ৬ অক্ষর',
                  icon: Icons.lock_outline,
                  obscureText: _obscure,
                  trailing: IconButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _obscure = !_obscure);
                    },
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    tooltip: _obscure ? 'দেখান' : 'লুকান',
                  ),
                  hasError: _errorField == 'auth',
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
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
                        const Icon(Icons.info_outline,
                            size: 18, color: AppColors.ink),
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
  // IME stability additions: explicit focus chain + keyboard action button.
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

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
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    // Static Container — no per-keystroke AnimatedContainer rebuild. The
    // error-state shadow is a decoration, not a transition; we paint it
    // only when `hasError` flips on.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: hasError
            ? const [
                BoxShadow(
                  color: Color(
                      0x1A0F0E14), // AppColors.ink @ 10% (avoid rebuild on alpha lookup)
                  blurRadius: 0,
                  offset: Offset(0, 3),
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        obscureText: obscureText,
        textCapitalization: textCapitalization,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        autofocus: autofocus,
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
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: trailing,
        ),
      ),
    );
  }
}
