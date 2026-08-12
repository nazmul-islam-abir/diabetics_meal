import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/supabase_service.dart';
import '../services/classification_engine.dart';
import 'home_shell.dart';

class OnboardingScreen extends StatefulWidget {
  /// Pass an existing profile to prefill the form (edit flow from Profile screen).
  final UserProfile? edit;
  const OnboardingScreen({super.key, this.edit});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0;

  // Basic
  final _ageCtrl = TextEditingController();
  String _sex = 'male';
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  // Glucose
  final _fastingCtrl = TextEditingController();
  final _postMealCtrl = TextEditingController();
  final _hba1cCtrl = TextEditingController();
  bool _onInsulin = false;
  final _medicationCtrl = TextEditingController();

  // BP / conditions
  final _systolicCtrl = TextEditingController();
  final _diastolicCtrl = TextEditingController();
  bool _hasCkd = false;
  bool _hasHeart = false;
  bool _hasAnemia = false;
  final _otherCtrl = TextEditingController();

  // Lifestyle
  String _activity = 'low';
  String _mealSize = 'medium';
  String _foodPref = 'omnivore';

  bool _saving = false;
  bool get _isEdit => widget.edit != null;

  // Identity (sign-up collected these; editable here too)
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final p = widget.edit;
    if (p != null) {
      _nameCtrl.text = p.fullName ?? '';
      _mobileCtrl.text = p.mobile ?? '';
      _ageCtrl.text = p.age.toString();
      _sex = p.sex;
      _weightCtrl.text = p.weightKg.toString();
      _heightCtrl.text = p.heightCm.toString();
      if (p.fastingGlucoseMmol != null) _fastingCtrl.text = p.fastingGlucoseMmol!.toString();
      if (p.postMealGlucoseMmol != null) _postMealCtrl.text = p.postMealGlucoseMmol!.toString();
      if (p.hba1cPercent != null) _hba1cCtrl.text = p.hba1cPercent!.toString();
      _onInsulin = p.onInsulin;
      _medicationCtrl.text = p.medication ?? '';
      if (p.systolicBp != null) _systolicCtrl.text = p.systolicBp!.toString();
      if (p.diastolicBp != null) _diastolicCtrl.text = p.diastolicBp!.toString();
      _hasCkd = p.hasCkd;
      _hasHeart = p.hasHeartDisease;
      _hasAnemia = p.hasAnemia;
      _otherCtrl.text = p.otherConditions ?? '';
      _activity = p.activityLevel;
      _mealSize = p.mealSizePref;
      _foodPref = p.foodPreference;
    } else {
      // Fresh onboarding — pull name/mobile from auth metadata if present.
      final meta = SupabaseService.currentUser?.userMetadata ?? const {};
      _nameCtrl.text = (meta['full_name'] as String?) ?? '';
      _mobileCtrl.text = (meta['mobile'] as String?) ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _mobileCtrl,
      _ageCtrl, _weightCtrl, _heightCtrl, _fastingCtrl, _postMealCtrl,
      _hba1cCtrl, _medicationCtrl, _systolicCtrl, _diastolicCtrl, _otherCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _d(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim());
  int? _i(String s) => s.trim().isEmpty ? null : int.tryParse(s.trim());

  UserProfile _buildProfile() {
    return UserProfile(
      fullName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      mobile: _mobileCtrl.text.trim().isEmpty ? null : _mobileCtrl.text.trim(),
      age: int.parse(_ageCtrl.text.trim()),
      sex: _sex,
      weightKg: double.parse(_weightCtrl.text.trim()),
      heightCm: double.parse(_heightCtrl.text.trim()),
      fastingGlucoseMmol: _d(_fastingCtrl.text),
      postMealGlucoseMmol: _d(_postMealCtrl.text),
      hba1cPercent: _d(_hba1cCtrl.text),
      onInsulin: _onInsulin,
      medication: _medicationCtrl.text.trim().isEmpty ? null : _medicationCtrl.text.trim(),
      systolicBp: _i(_systolicCtrl.text),
      diastolicBp: _i(_diastolicCtrl.text),
      hasCkd: _hasCkd,
      hasHeartDisease: _hasHeart,
      hasAnemia: _hasAnemia,
      otherConditions: _otherCtrl.text.trim().isEmpty ? null : _otherCtrl.text.trim(),
      activityLevel: _activity,
      mealSizePref: _mealSize,
      foodPreference: _foodPref,
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final profile = _buildProfile();
    try {
      await SupabaseService.saveProfile(profile);
      // Keep auth metadata in sync if name/mobile were edited.
      final prevMeta = SupabaseService.currentUser?.userMetadata ?? const {};
      if ((prevMeta['full_name'] ?? '') != (_nameCtrl.text.trim()) ||
          (prevMeta['mobile'] ?? '') != (_mobileCtrl.text.trim())) {
        try {
          await SupabaseService.updateAccountMeta(
            fullName: _nameCtrl.text.trim(),
            mobile: _mobileCtrl.text.trim(),
          );
        } catch (_) {/* non-fatal */}
      }
      if (!mounted) return;
      final cls = ClassificationEngine.classify(profile);
      if (cls.warnings.isNotEmpty) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('গুরুত্বপূর্ণ তথ্য'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: cls.warnings
                    .map((w) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('• $w'),
                        ))
                    .toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('বুঝেছি'),
              ),
            ],
          ),
        );
      }
      if (!mounted) return;
      if (_isEdit) {
        // Came from Profile — just pop back with success.
        Navigator.pop(context, true);
      } else {
        // First-time onboarding — go to the main shell.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeShell()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('সংরক্ষণ ব্যর্থ হয়েছে: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      _basicStep(),
      _glucoseStep(),
      _conditionsStep(),
      _lifestyleStep(),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'তথ্য আপডেট করুন' : 'আপনার তথ্য দিন')),
      body: Form(
        key: _formKey,
        child: Stepper(
          currentStep: _step,
          onStepContinue: () {
            if (_step < steps.length - 1) {
              setState(() => _step++);
            } else {
              _submit();
            }
          },
          onStepCancel: () {
            if (_step > 0) setState(() => _step--);
          },
          controlsBuilder: (context, details) => Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: _saving ? null : details.onStepContinue,
                  child: _saving && _step == steps.length - 1
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_step == steps.length - 1 ? 'পরিকল্পনা তৈরি করুন' : 'পরবর্তী'),
                ),
                if (_step > 0) ...[
                  const SizedBox(width: 12),
                  TextButton(onPressed: details.onStepCancel, child: const Text('পেছনে')),
                ],
              ],
            ),
          ),
          steps: [
            Step(
              title: const Text('মৌলিক তথ্য'),
              content: steps[0],
              isActive: _step >= 0,
            ),
            Step(
              title: const Text('গ্লুকোজ ও ওষুধ'),
              content: steps[1],
              isActive: _step >= 1,
            ),
            Step(
              title: const Text('অন্যান্য শারীরিক অবস্থা'),
              content: steps[2],
              isActive: _step >= 2,
            ),
            Step(
              title: const Text('জীবনযাত্রা ও পছন্দ'),
              content: steps[3],
              isActive: _step >= 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label, {bool required = true, String? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder()),
        validator: (v) {
          if (!required) return null;
          if (v == null || v.trim().isEmpty) return 'আবশ্যক';
          if (double.tryParse(v.trim()) == null) return 'সঠিক সংখ্যা লিখুন';
          return null;
        },
      ),
    );
  }

  Widget _basicStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'আপনার নাম',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _mobileCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'মোবাইল নম্বর',
              prefixIcon: Icon(Icons.phone_outlined),
              hintText: '01XXXXXXXXX',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _numField(_ageCtrl, 'বয়স (বছর)'),
          DropdownButtonFormField<String>(
            value: _sex,
            decoration: const InputDecoration(labelText: 'লিঙ্গ', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'male', child: Text('পুরুষ')),
              DropdownMenuItem(value: 'female', child: Text('মহিলা')),
              DropdownMenuItem(value: 'other', child: Text('অন্যান্য')),
            ],
            onChanged: (v) => setState(() => _sex = v!),
          ),
          const SizedBox(height: 12),
          _numField(_weightCtrl, 'ওজন', suffix: 'কেজি'),
          _numField(_heightCtrl, 'উচ্চতা', suffix: 'সেমি'),
          const Text(
            'BMI স্বয়ংকরিয়ভাবে হিসাব করা হবে (ওজন ও উচ্চতা থেকে)।',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      );

  Widget _glucoseStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _numField(_fastingCtrl, 'ফাস্টিং গ্লুকোজ', required: false, suffix: 'mmol/L'),
          _numField(_postMealCtrl, 'খাবার পরের গ্লুকোজ (২ ঘণ্টা)', required: false, suffix: 'mmol/L'),
          _numField(_hba1cCtrl, 'HbA1c', required: false, suffix: '%'),
          const Text(
            'HbA1c জানা থাকলে সেটিই মূল সূচক হিসেবে ব্যবহৃত হয়।',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _onInsulin,
            onChanged: (v) => setState(() => _onInsulin = v),
            title: const Text('আপনি কি ইনসুলিন গ্রহণ করেন?'),
          ),
          TextFormField(
            controller: _medicationCtrl,
            decoration: const InputDecoration(
              labelText: 'ওষুধের নাম (ঐচ্ছিক)',
              hintText: 'যেমন: Metformin',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      );

  Widget _conditionsStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _numField(_systolicCtrl, 'সিস্টোলিক BP', required: false)),
              const SizedBox(width: 12),
              Expanded(child: _numField(_diastolicCtrl, 'ডায়াস্টোলিক BP', required: false)),
            ],
          ),
          SwitchListTile(
            value: _hasCkd,
            onChanged: (v) => setState(() => _hasCkd = v),
            title: const Text('কিডনি রোগ (CKD) আছে?'),
          ),
          SwitchListTile(
            value: _hasHeart,
            onChanged: (v) => setState(() => _hasHeart = v),
            title: const Text('হৃদরোগ আছে?'),
          ),
          SwitchListTile(
            value: _hasAnemia,
            onChanged: (v) => setState(() => _hasAnemia = v),
            title: const Text('রক্তস্বল্পতা (Anemia) আছে?'),
          ),
          TextFormField(
            controller: _otherCtrl,
            decoration: const InputDecoration(
              labelText: 'অন্যান্য শারীরিক অবস্থা (ঐচ্ছিক)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
        ],
      );

  Widget _lifestyleStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _activity,
            decoration: const InputDecoration(labelText: 'শারীরিক পরিশ্রম', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'low', child: Text('কম')),
              DropdownMenuItem(value: 'moderate', child: Text('মাঝারি')),
              DropdownMenuItem(value: 'high', child: Text('বেশি')),
            ],
            onChanged: (v) => setState(() => _activity = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _mealSize,
            decoration: const InputDecoration(labelText: 'সাধারণ খাবারের পরিমাণ', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'small', child: Text('অল্প')),
              DropdownMenuItem(value: 'medium', child: Text('মাঝারি')),
              DropdownMenuItem(value: 'large', child: Text('বেশি')),
            ],
            onChanged: (v) => setState(() => _mealSize = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _foodPref,
            decoration: const InputDecoration(labelText: 'খাদ্যাভ্যাস পছন্দ', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'omnivore', child: Text('সব ধরনের খাবার')),
              DropdownMenuItem(value: 'vegetarian', child: Text('নিরামিষ')),
              DropdownMenuItem(value: 'fish_only', child: Text('শুধু মাছ (আমিষ)')),
              DropdownMenuItem(value: 'no_beef', child: Text('গরুর মাংস ছাড়া')),
            ],
            onChanged: (v) => setState(() => _foodPref = v!),
          ),
          const SizedBox(height: 16),
          const Card(
            color: Color(0xFFFFF4E5),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'এই তথ্য একটি সাধারণ খাদ্য পরিকল্পনা তৈরিতে সাহায্য করে। '
                'এটি ডাক্তারের পরামর্শের বিকল্প নয়। ইনসুলিন বা ওষুধের সময়সূচি পরিবর্তনের আগে সবসময় চিকিৎসকের সাথে কথা বলুন।',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      );
}
