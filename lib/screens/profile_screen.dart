import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/supabase_service.dart';
import '../services/classification_engine.dart';
import '../services/impact_engine.dart' show ImpactEngine;
import '../services/app_events.dart';
import 'onboarding_screen.dart';
import 'auth_screen.dart';

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
    await SupabaseService.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  Future<void> _editProfile() async {
    final p = _profile;
    if (p == null) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => OnboardingScreen(edit: p)),
    );
    if (result == true) {
      // Tell the rest of the app (meal plan, dashboard) that the profile
      // changed so they re-fetch and re-classify.
      AppEvents.notifyProfileChanged();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('প্রোফাইল'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 26),
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 26),
            tooltip: 'লগ আউট',
            onPressed: _signOut,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text('ত্রুটি: $_error')))
              : _profile == null
                  ? _onboardingNeeded()
                  : _buildContent(user?.email ?? ''),
    );
  }

  Widget _onboardingNeeded() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('আপনার স্বাস্থ্য তথ্য দেওয়া হয়নি',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('ব্যক্তিগতকৃত পরিকল্পনা পেতে প্রোফাইল পূরণ করুন',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('প্রোফাইল পূরণ করুন'),
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _accountCard(email),
        const SizedBox(height: 12),
        _vitalsCard(p, bmi, bmiLabel),
        const SizedBox(height: 12),
        _classificationCard(cls),
        const SizedBox(height: 12),
        _conditionsCard(p),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.edit),
          label: const Text('তথ্য আপডেট করুন'),
          onPressed: _editProfile,
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          label: const Text('লগ আউট'),
          onPressed: _signOut,
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: const Color(0xFF0F6E56),
              child: Text(
                name.characters.first.toUpperCase(),
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.mail_outline, size: 16, color: Colors.black54),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        email.isEmpty ? '—' : email,
                        style: const TextStyle(fontSize: 14, color: Colors.black54),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.phone_outlined, size: 16, color: Colors.black54),
                    const SizedBox(width: 4),
                    Text(mobile,
                        style: const TextStyle(fontSize: 14, color: Colors.black54)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vitalsCard(UserProfile p, double bmi, String bmiLabel) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('শারীরিক তথ্য',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _row('বয়স', '${p.age} বছর'),
            _row('লিঙ্গ', p.sex == 'male' ? 'পুরুষ' : p.sex == 'female' ? 'মহিলা' : 'অন্যান্য'),
            _row('ওজন', '${p.weightKg.toStringAsFixed(1)} কেজি'),
            _row('উচ্চতা', '${p.heightCm.toStringAsFixed(0)} সেমি'),
            _row('BMI', '${bmi.toStringAsFixed(1)} ($bmiLabel)'),
            if (p.systolicBp != null && p.diastolicBp != null)
              _row('রক্তচাপ', '${p.systolicBp}/${p.diastolicBp} mmHg'),
            if (p.hba1cPercent != null)
              _row('HbA1c', '${p.hba1cPercent!.toStringAsFixed(1)}%'),
            if (p.fastingGlucoseMmol != null)
              _row('ফাস্টিং গ্লুকোজ', '${p.fastingGlucoseMmol!.toStringAsFixed(1)} mmol/L'),
            if (p.postMealGlucoseMmol != null)
              _row('খাবার পরের গ্লুকোজ', '${p.postMealGlucoseMmol!.toStringAsFixed(1)} mmol/L'),
            if (p.medication != null && p.medication!.isNotEmpty)
              _row('ওষুধ', p.medication!),
            _row('পরিশ্রম',
                p.activityLevel == 'low' ? 'কম' : p.activityLevel == 'moderate' ? 'মাঝারি' : 'বেশি'),
          ],
        ),
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
    return Card(
      color: const Color(0xFFE3F2FD),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('বর্তমান পরিকল্পনার স্তর',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _row('গ্লুকোজ নিয়ন্ত্রণ', glucoseLabel),
            _row('এক বেলায় সর্বোচ্চ কার্ব', '${cls.maxCarbPerMeal.toInt()} গ্রাম'),
            _row('অনুমোদিত GI', cls.allowedGi.map(ImpactEngine.giLabel).join(', ')),
            if (cls.restrictionFlags.isNotEmpty)
              _row('বিধিনিষেধ', cls.restrictionFlags.join(', ')),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('শারীরিক অবস্থা',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips
                  .map((c) => Chip(
                        label: Text(c, style: const TextStyle(fontSize: 14)),
                        backgroundColor: const Color(0xFFE0F2F1),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              flex: 2,
              child: Text(label,
                  style: const TextStyle(fontSize: 15, color: Colors.black54))),
          Expanded(
            flex: 3,
            child: Text(value,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}