import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/supabase_service.dart';
import '../services/classification_engine.dart';
import '../services/impact_engine.dart' show ImpactEngine;
import '../services/app_events.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import 'onboarding_screen.dart';

/// Profile screen — clinical details, edit, and sign-out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  Classification? _cls;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await SupabaseService.fetchProfile();
      if (!mounted) return;
      if (p == null) {
        setState(() {
          _loading = false;
          _profile = null;
        });
        return;
      }
      setState(() {
        _profile = p;
        _cls = ClassificationEngine.classify(p);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _signOut() async {
    // The root widget listens to Supabase auth state changes and
    // automatically swaps HomeShell for AuthScreen once the session
    // is cleared — no manual navigation needed.
    await SupabaseService.signOut();
  }

  Future<void> _editProfile() async {
    final p = _profile;
    if (p == null) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => OnboardingScreen(edit: p)),
    );
    if (result == true) {
      AppEvents.notifyProfileChanged();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.currentUser;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: LoadingMark(size: 36))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('ত্রুটি: $_error',
                          style: Theme.of(context).textTheme.bodyLarge),
                    ),
                  )
                : _profile == null
                    ? _onboardingNeeded()
                    : _buildContent(user?.email ?? ''),
      ),
    );
  }

  Widget _onboardingNeeded() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.chalk,
                borderRadius: BorderRadius.circular(44),
                border: Border.all(color: AppColors.graphite),
              ),
              child: const Icon(Icons.assignment_outlined, size: 38, color: AppColors.ink),
            ),
            const SizedBox(height: 20),
            const Text(
              'আপনার স্বাস্থ্য তথ্য দেওয়া হয়নি',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'ব্যক্তিগতকৃত পরিকল্পনা পেতে প্রোফাইল পূরণ করুন',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppColors.smoke, height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: MonoButton(
                label: 'প্রোফাইল পূরণ করুন',
                leading: Icons.add,
                onPressed: () async {
                  final res = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                  );
                  if (res == true) {
                    AppEvents.notifyProfileChanged();
                    await _load();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(String email) {
    final p = _profile!;
    final cls = _cls!;
    final bmi = p.bmi;
    final bmiLabel = bmi < 18.5
        ? 'কম ওজন'
        : bmi < 23
            ? 'স্বাভাবিক'
            : bmi < 25
                ? 'সামান্য বেশি'
                : 'বেশি';

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
          sliver: SliverList.list(children: [
            _accountCard(email),
            const SizedBox(height: 14),
            _vitalsCard(p, bmi, bmiLabel),
            const SizedBox(height: 14),
            _classificationCard(cls),
            const SizedBox(height: 14),
            _conditionsCard(p),
            const SizedBox(height: 20),
            MonoButton(
              label: 'তথ্য আপডেট করুন',
              leading: Icons.edit_outlined,
              onPressed: _editProfile,
            ),
            const SizedBox(height: 10),
            MonoButton(
              label: 'লগ আউট',
              leading: Icons.logout,
              variant: MonoButtonVariant.outline,
              onPressed: _signOut,
            ),
          ]),
        ),
      ],
    );
  }

  Widget _accountCard(String email) {
    final p = _profile!;
    final name = (p.fullName != null && p.fullName!.isNotEmpty)
        ? p.fullName!
        : (email.isEmpty ? 'ব্যবহারকারী' : email);
    final mobile = (p.mobile != null && p.mobile!.isNotEmpty) ? p.mobile! : '—';
    final monogram = name.characters.first.toUpperCase();

    return RevealOnEnter(
      child: SplitHeroCard(
        blockGradient: AppGradients.aurora,
        blockContent: MonoPattern(
          kind: MonoPatternKind.arcs,
          color: AppColors.paper,
          opacity: 0.10,
          spacing: 18,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AccentTag(label: 'সক্রিয়', icon: Icons.bolt),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    monogram,
                    style: const TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.w800,
                      color: AppColors.paper,
                      letterSpacing: -2,
                      height: 1,
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'আমার\nডায়েট',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.paper.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.2,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 14),
            _rowLight('ইমেইল', email.isEmpty ? '—' : email),
            const SizedBox(height: 8),
            _rowLight('মোবাইল', mobile),
          ],
        ),
      ),
    );
  }

  Widget _rowLight(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.smoke,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
            textAlign: TextAlign.right,
            softWrap: true,
          ),
        ),
      ],
    );
  }

  Widget _vitalsCard(UserProfile p, double bmi, String bmiLabel) {
    return RevealOnEnter(
      delay: const Duration(milliseconds: 80),
      child: MonoCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('শারীরিক তথ্য', padding: EdgeInsets.only(top: 0, bottom: 14)),
            Row(
              children: [
                Expanded(child: _statTile('বয়স', '${p.age}', 'বছর')),
                const SizedBox(width: 10),
                Expanded(
                  child: _statTile(
                    'লিঙ্গ',
                    p.sex == 'male' ? 'পুরুষ' : p.sex == 'female' ? 'মহিলা' : 'অন্যান্য',
                    '',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _statTile('ওজন', p.weightKg.toStringAsFixed(1), 'কেজি')),
                const SizedBox(width: 10),
                Expanded(child: _statTile('উচ্চতা', p.heightCm.toStringAsFixed(0), 'সেমি')),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
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
                        const Text(
                          'BMI',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.smoke,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            bmi.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              height: 1,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          bmiLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.smoke,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (p.systolicBp != null && p.diastolicBp != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'রক্তচাপ',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.smoke,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${p.systolicBp}/${p.diastolicBp}',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                                height: 1,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'mmHg',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.smoke,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (p.hba1cPercent != null || p.fastingGlucoseMmol != null || p.postMealGlucoseMmol != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.chalk,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.graphite),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'গ্লুকোজ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.smoke,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (p.hba1cPercent != null)
                        _miniRow('HbA1c', '${p.hba1cPercent!.toStringAsFixed(1)}%'),
                      if (p.fastingGlucoseMmol != null)
                        _miniRow('ফাস্টিং', '${p.fastingGlucoseMmol!.toStringAsFixed(1)} mmol/L'),
                      if (p.postMealGlucoseMmol != null)
                        _miniRow('খাবার পরে', '${p.postMealGlucoseMmol!.toStringAsFixed(1)} mmol/L'),
                    ],
                  ),
                ),
              ),
            if (p.medication != null && p.medication!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _miniRow('ওষুধ', p.medication!),
            ],
            const SizedBox(height: 10),
            _miniRow(
              'পরিশ্রম',
              p.activityLevel == 'low'
                  ? 'কম'
                  : p.activityLevel == 'moderate'
                      ? 'মাঝারি'
                      : 'বেশি',
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String label, String value, String unit) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.chalk,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.graphite),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.smoke,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  letterSpacing: -0.4,
                  height: 1.1,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    unit,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.smoke,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.smoke,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _classificationCard(Classification cls) {
    final glucoseLabel = {
      'good': 'ভালো',
      'moderate': 'মাঝারি',
      'poor': 'খারাপ',
      'unknown': 'অজানা',
    }[cls.glucoseTier] ?? cls.glucoseTier;

    return RevealOnEnter(
      delay: const Duration(milliseconds: 160),
      child: MonoCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('বর্তমান ক্লাসিফিকেশন', padding: EdgeInsets.only(top: 0, bottom: 14)),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'গ্লুকোজ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.smoke,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        glucoseLabel,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'এক বেলায় কার্ব',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.smoke,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            cls.maxCarbPerMeal.toInt().toString(),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              'গ্রাম',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.smoke.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.chalk,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.graphite),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _miniRow('অনুমোদিত GI', cls.allowedGi.map(ImpactEngine.giLabel).join(', ')),
                  if (cls.restrictionFlags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _miniRow('বিধিনিষেধ', cls.restrictionFlags.join(', ')),
                  ],
                ],
              ),
            ),
            if (cls.warnings.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: AppGradients.aurora,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.paper,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.priority_high, size: 14, color: AppColors.ink),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'গুরুত্বপূর্ণ তথ্য',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.paper,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final w in cls.warnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '• $w',
                          style: const TextStyle(
                            color: AppColors.paper,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _conditionsCard(UserProfile p) {
    final chips = <String>[];
    if (p.onInsulin) chips.add('ইনসুলিন');
    if (p.hasCkd) chips.add('কিডনি রোগ (CKD)');
    if (p.hasHeartDisease) chips.add('হৃদরোগ');
    if (p.hasAnemia) chips.add('রক্তস্বল্পতা');
    if (p.otherConditions != null && p.otherConditions!.isNotEmpty) {
      chips.add(p.otherConditions!);
    }
    if (chips.isEmpty) chips.add('কোনো বিশেষ শারীরিক অবস্থা নেই');

    return RevealOnEnter(
      delay: const Duration(milliseconds: 220),
      child: MonoCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('শারীরিক অবস্থা', padding: EdgeInsets.only(top: 0, bottom: 14)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < chips.length; i++)
                  MonoBadge(
                    text: chips[i],
                    icon: chips[i] == 'কোনো বিশেষ শারীরিক অবস্থা নেই' ? Icons.check : Icons.fiber_manual_record,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}