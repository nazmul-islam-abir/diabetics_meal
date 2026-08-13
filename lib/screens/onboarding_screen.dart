import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user_profile.dart';
import '../services/supabase_service.dart';
import '../services/classification_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

/// Onboarding / profile editor — 4-step clinical intake with custom editorial UI.
class OnboardingScreen extends StatefulWidget {
  final UserProfile? edit;
  const OnboardingScreen({super.key, this.edit});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0;

  // Controllers
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _age = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _fasting = TextEditingController();
  final _postMeal = TextEditingController();
  final _hba1c = TextEditingController();
  final _medication = TextEditingController();
  final _systolic = TextEditingController();
  final _diastolic = TextEditingController();
  final _other = TextEditingController();

  // Selectors
  String _sex = 'male';
  bool _onInsulin = false;
  bool _hasCkd = false;
  bool _hasHeart = false;
  bool _hasAnemia = false;
  String _activity = 'low';
  String _mealSize = 'medium';
  String _foodPref = 'omnivore';

  bool _saving = false;

  static const _stepTitles = ['মৌলিক তথ্য', 'গ্লুকোজ', 'অবস্থা', 'জীবনযাত্রা'];
  static const _stepOverlines = ['ধাপ ১ / ৪', 'ধাপ ২ / ৪', 'ধাপ ৩ / ৪', 'ধাপ ৪ / ৪'];
  static const _stepBlurbs = [
    'আপনার সম্পর্কে প্রাথমিক তথ্য',
    'রক্তের গ্লুকোজ ও ওষুধ সম্পর্কে',
    'দীর্ঘস্থায়ী রোগ ও অবস্থা',
    'পরিশ্রম ও খাবারের অভ্যাস',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    if (e != null) {
      _name.text = e.fullName ?? '';
      _mobile.text = e.mobile ?? '';
      _age.text = e.age.toString();
      _sex = e.sex;
      _weight.text = e.weightKg.toString();
      _height.text = e.heightCm.toString();
      _fasting.text = e.fastingGlucoseMmol?.toString() ?? '';
      _postMeal.text = e.postMealGlucoseMmol?.toString() ?? '';
      _hba1c.text = e.hba1cPercent?.toString() ?? '';
      _medication.text = e.medication ?? '';
      _systolic.text = e.systolicBp?.toString() ?? '';
      _diastolic.text = e.diastolicBp?.toString() ?? '';
      _other.text = e.otherConditions ?? '';
      _onInsulin = e.onInsulin;
      _hasCkd = e.hasCkd;
      _hasHeart = e.hasHeartDisease;
      _hasAnemia = e.hasAnemia;
      _activity = e.activityLevel;
      _mealSize = e.mealSizePref;
      _foodPref = e.foodPreference;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _age.dispose();
    _weight.dispose();
    _height.dispose();
    _fasting.dispose();
    _postMeal.dispose();
    _hba1c.dispose();
    _medication.dispose();
    _systolic.dispose();
    _diastolic.dispose();
    _other.dispose();
    super.dispose();
  }

  String? _number(String? v) {
    if (v == null || v.trim().isEmpty) return 'আবশ্যক';
    if (double.tryParse(v.trim()) == null) return 'সংখ্যা দিন';
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Hard-check required fields before any I/O so we never hit a parse error
    // in the middle of an async save.
    final age = int.tryParse(_age.text.trim());
    final weight = double.tryParse(_weight.text.trim());
    final height = double.tryParse(_height.text.trim());
    if (age == null || age < 1 || age > 120) {
      _toast('বয়স ১ থেকে ১২০ এর মধ্যে হতে হবে');
      return;
    }
    if (weight == null || weight < 10 || weight > 400) {
      _toast('ওজন সঠিক নয়');
      return;
    }
    if (height == null || height < 30 || height > 250) {
      _toast('উচ্চতা সঠিক নয়');
      return;
    }

    setState(() => _saving = true);

    try {
      // Safe parsing: ensure we never crash on invalid input that slipped
      // past the basic validators (e.g. decimals in int fields).
      final fasting = double.tryParse(_fasting.text.trim());
      final postMeal = double.tryParse(_postMeal.text.trim());
      final hba1c = double.tryParse(_hba1c.text.trim());
      
      final systolic = int.tryParse(_systolic.text.trim()) ?? 
          (double.tryParse(_systolic.text.trim())?.round());
      final diastolic = int.tryParse(_diastolic.text.trim()) ?? 
          (double.tryParse(_diastolic.text.trim())?.round());

      final profile = UserProfile(
        fullName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        mobile: _mobile.text.trim().isEmpty ? null : _mobile.text.trim(),
        age: age,
        sex: _sex,
        weightKg: weight,
        heightCm: height,
        fastingGlucoseMmol: fasting,
        postMealGlucoseMmol: postMeal,
        hba1cPercent: hba1c,
        onInsulin: _onInsulin,
        medication: _medication.text.trim().isEmpty ? null : _medication.text.trim(),
        systolicBp: systolic,
        diastolicBp: diastolic,
        hasCkd: _hasCkd,
        hasHeartDisease: _hasHeart,
        hasAnemia: _hasAnemia,
        otherConditions: _other.text.trim().isEmpty ? null : _other.text.trim(),
        activityLevel: _activity,
        mealSizePref: _mealSize,
        foodPreference: _foodPref,
      );

      await SupabaseService.saveProfile(profile);

      // Mirror identity on auth metadata so header/cards stay consistent.
      // Failure here must not crash the whole save.
      try {
        await SupabaseService.updateAccountMeta(
          fullName: profile.fullName,
          mobile: profile.mobile,
        );
      } catch (_) {
        // Silent — profile is already saved. Identity mirror is best-effort.
      }

      if (!mounted) return;

      // Capture the navigator BEFORE any further awaits so we don't hit
      // "looking up a deactivated widget" if the user navigates away during
      // the warnings dialog.
      final navigator = Navigator.of(context);

      final cls = ClassificationEngine.classify(profile);
      if (cls.warnings.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (_) => _WarningsDialog(warnings: cls.warnings),
        );
      }
      if (!mounted) return;
      navigator.pop(true);
    } catch (e, st) {
      // Surface error and keep the user on the screen instead of tearing the
      // app down. Log the stack for debugging.
      debugPrint('saveProfile failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'সংরক্ষণ ব্যর্থ: ${_friendlyError(e)}',
            style: const TextStyle(color: AppColors.paper),
          ),
          backgroundColor: AppColors.ink,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(msg, style: const TextStyle(color: AppColors.paper)),
        backgroundColor: AppColors.ink,
      ),
    );
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return 'ইন্টারনেট সংযোগ নেই';
    }
    if (s.contains('42501') || s.toLowerCase().contains('row-level security')) {
      return 'অনুমতি নেই — সেশন রিফ্রেশ করুন';
    }
    if (s.contains('23514') || s.contains('check constraint')) {
      return 'তথ্য সীমার বাইরে';
    }
    return 'আবার চেষ্টা করুন';
  }

  void _next() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_step < 3) {
      setState(() => _step++);
    } else {
      _save();
    }
  }

  void _back() {
    if (_step == 0) {
      Navigator.pop(context);
    } else {
      setState(() => _step--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(),
            _progressRail(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Form(
                  key: _formKey,
                  child: AnimatedSwitcher(
                    duration: AppMotion.medium,
                    switchInCurve: AppMotion.emphasized,
                    switchOutCurve: AppMotion.emphasized,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.04, 0),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: _buildStep(_step),
                    ),
                  ),
                ),
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 20, 0),
      child: Row(
        children: [
          Pressable(
            onTap: _back,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.chalk,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.graphite),
              ),
              child: const Icon(Icons.arrow_back, size: 20, color: AppColors.ink),
            ),
          ),
          const Spacer(),
          Text(
            widget.edit != null ? 'প্রোফাইল আপডেট' : 'নতুন প্রোফাইল',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.smoke,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressRail() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Overline(_stepOverlines[_step], padding: EdgeInsets.zero),
          const SizedBox(height: 10),
          Text(
            _stepTitles[_step],
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              height: 1.05,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _stepBlurbs[_step],
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.smoke,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(4, (i) {
              final filled = i <= _step;
              return Expanded(
                child: AnimatedContainer(
                  duration: AppMotion.short,
                  curve: AppMotion.emphasized,
                  margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                  height: 5,
                  decoration: BoxDecoration(
                    color: filled ? AppColors.ink : AppColors.graphite,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final isLast = _step == 3;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border(top: BorderSide(color: AppColors.graphite.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          if (_step > 0)
            Expanded(
              flex: 2,
              child: MonoButton(
                label: 'পূর্বে',
                leading: Icons.arrow_back,
                variant: MonoButtonVariant.outline,
                onPressed: _saving ? null : () => setState(() => _step--),
              ),
            ),
          if (_step > 0) const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: MonoButton(
              label: isLast ? 'পরিকল্পনা তৈরি করুন' : 'পরবর্তী',
              trailing: isLast ? null : Icons.arrow_forward,
              loading: _saving,
              onPressed: _next,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- STEP BUILDERS ----------------

  Widget _buildStep(int step) {
    switch (step) {
      case 0:
        return _basic();
      case 1:
        return _glucose();
      case 2:
        return _conditions();
      case 3:
      default:
        return _lifestyle();
    }
  }

  Widget _basic() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labeled('পূর্ণ নাম', 'ঐচ্ছিক'),
        TextFormField(
          controller: _name,
          decoration: const InputDecoration(hintText: 'নাম লিখুন'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink),
        ),
        const SizedBox(height: 18),
        _labeled('মোবাইল নম্বর', 'ঐচ্ছিক'),
        TextFormField(
          controller: _mobile,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: '01XXXXXXXXX'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _field(_age, 'বয়স', validator: _number, numeric: true)),
            const SizedBox(width: 12),
            Expanded(child: _field(_weight, 'ওজন (কেজি)', validator: _number, numeric: true)),
            const SizedBox(width: 12),
            Expanded(child: _field(_height, 'উচ্চতা (সেমি)', validator: _number, numeric: true)),
          ],
        ),
        const SizedBox(height: 18),
        _labeled('লিঙ্গ'),
        MonoSegmented<String>(
          selected: _sex,
          options: const [
            (label: 'পুরুষ', value: 'male'),
            (label: 'মহিলা', value: 'female'),
            (label: 'অন্যান্য', value: 'other'),
          ],
          onChanged: (v) => setState(() => _sex = v),
        ),
      ],
    );
  }

  Widget _glucose() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _field(_fasting, 'ফাস্টিং গ্লুকোজ', suffix: 'mmol/L', validator: _number, numeric: true)),
            const SizedBox(width: 12),
            Expanded(child: _field(_postMeal, 'খাবার-পর গ্লুকোজ', suffix: 'mmol/L', validator: _number, numeric: true)),
          ],
        ),
        const SizedBox(height: 18),
        _field(_hba1c, 'HbA1c', suffix: '%', validator: _number, numeric: true),
        const SizedBox(height: 18),
        _labeled('ওষুধ / ইনসুলিন'),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            color: AppColors.chalk,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.graphite),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'ইনসুলিন গ্রহণ করছি',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ),
              Switch.adaptive(
                value: _onInsulin,
                activeTrackColor: AppColors.ink,
                activeColor: AppColors.paper,
                inactiveTrackColor: AppColors.graphite,
                onChanged: (v) => setState(() => _onInsulin = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _medication,
          decoration: const InputDecoration(hintText: 'ওষুধের নাম লিখুন (ঐচ্ছিক)'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
        ),
      ],
    );
  }

  Widget _conditions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labeled('রক্তচাপ (mmHg)', 'ঐচ্ছিক'),
        Row(
          children: [
            Expanded(child: _field(_systolic, 'সিস্টোলিক', optional: true, numeric: true)),
            const SizedBox(width: 12),
            Expanded(child: _field(_diastolic, 'ডায়াস্টোলিক', optional: true, numeric: true)),
          ],
        ),
        const SizedBox(height: 18),
        _labeled('দীর্ঘস্থায়ী অবস্থা'),
        _switchTile(
          label: 'কিডনি রোগ (CKD)',
          sub: 'কিডনি সংক্রান্ত খাবার সীমিত হবে',
          value: _hasCkd,
          onChanged: (v) => setState(() => _hasCkd = v),
        ),
        const SizedBox(height: 10),
        _switchTile(
          label: 'হৃদরোগ',
          sub: 'কম সোডিয়াম ও কম চর্বির পরামর্শ',
          value: _hasHeart,
          onChanged: (v) => setState(() => _hasHeart = v),
        ),
        const SizedBox(height: 10),
        _switchTile(
          label: 'রক্তস্বল্পতা',
          sub: 'আয়রন-সমৃদ্ধ খাবার বেশি দেখানো হবে',
          value: _hasAnemia,
          onChanged: (v) => setState(() => _hasAnemia = v),
        ),
        const SizedBox(height: 18),
        _labeled('অন্যান্য অবস্থা', 'ঐচ্ছিক'),
        TextFormField(
          controller: _other,
          maxLines: 2,
          decoration: const InputDecoration(hintText: 'যেমন: থাইরয়েড, গর্ভাবস্থা…'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
        ),
      ],
    );
  }

  Widget _lifestyle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labeled('শারীরিক পরিশ্রম'),
        MonoSegmented<String>(
          selected: _activity,
          options: const [
            (label: 'কম', value: 'low'),
            (label: 'মাঝারি', value: 'moderate'),
            (label: 'বেশি', value: 'high'),
          ],
          onChanged: (v) => setState(() => _activity = v),
        ),
        const SizedBox(height: 18),
        _labeled('খাবারের পরিমাণ'),
        MonoSegmented<String>(
          selected: _mealSize,
          options: const [
            (label: 'অল্প', value: 'small'),
            (label: 'মাঝারি', value: 'medium'),
            (label: 'বেশি', value: 'large'),
          ],
          onChanged: (v) => setState(() => _mealSize = v),
        ),
        const SizedBox(height: 18),
        _labeled('খাবারের ধরন'),
        MonoSegmented<String>(
          selected: _foodPref,
          options: const [
            (label: 'সর্বভুক', value: 'omnivore'),
            (label: 'নিরামিষ', value: 'vegetarian'),
            (label: 'শুধু মাছ', value: 'fish_only'),
            (label: 'গরু ছাড়া', value: 'no_beef'),
          ],
          onChanged: (v) => setState(() => _foodPref = v),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.chalk,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.graphite),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.info_outline, color: AppColors.paper, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'এই তথ্য শুধু পরামর্শের জন্য। যেকোনো পরিবর্তনের আগে আপনার চিকিৎসকের সাথে কথা বলুন।',
                  style: TextStyle(fontSize: 13, color: AppColors.ink, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------- FORM PIECES ----------------

  Widget _labeled(String label, [String? hint]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: 0.2,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Text(
              hint,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.smoke,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? suffix,
    String? Function(String?)? validator,
    bool numeric = false,
    bool optional = false,
  }) {
    // Tight, width-safe layout — label above, compact field below. The suffix
    // sits inside the input and is allowed to wrap so two side-by-side fields
    // never overflow on narrow phones.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labeled(label, optional ? 'ঐচ্ছিক' : null),
        TextFormField(
          controller: ctrl,
          validator: optional
              ? (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (double.tryParse(v.trim()) == null) return 'সংখ্যা দিন';
                  return null;
                }
              : validator,
          keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          inputFormatters: numeric ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
          decoration: suffix != null
              ? InputDecoration(
                  hintText: '0',
                  suffixText: suffix,
                  suffixStyle: const TextStyle(fontSize: 13, color: AppColors.smoke, fontWeight: FontWeight.w600),
                  isDense: true,
                )
              : const InputDecoration(isDense: true),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
      ],
    );
  }

  Widget _switchTile({required String label, required String sub, required bool value, required ValueChanged<bool> onChanged}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.chalk,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.graphite),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.smoke, height: 1.35)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: AppColors.ink,
            activeColor: AppColors.paper,
            inactiveTrackColor: AppColors.graphite,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _WarningsDialog extends StatelessWidget {
  final List<String> warnings;
  const _WarningsDialog({required this.warnings});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.paper,
      surfaceTintColor: AppColors.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.priority_high, color: AppColors.paper, size: 18),
                ),
                const SizedBox(width: 10),
                const Text(
                  'গুরুত্বপূর্ণ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink, letterSpacing: -0.2),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(w, style: const TextStyle(fontSize: 15, color: AppColors.ink, height: 1.4)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: MonoButton(label: 'বুঝেছি', onPressed: () => Navigator.pop(context)),
            ),
          ],
        ),
      ),
    ));
  }
}
