import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

/// Shown instead of a blank white screen when the Supabase client can't
/// initialise — most commonly because `.env` is missing or the keys are
/// blank. The screen gives the developer a precise Bangla + English
/// remediation path so they don't have to read a Flutter crash log to
/// figure out what to do.
class SetupErrorScreen extends StatelessWidget {
  const SetupErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final msg = SupabaseService.initError ??
        'অজানা সেটআপ ত্রুটি — লগ দেখুন।';
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Overline('সেটআপ সমস্যা'),
              const SizedBox(height: 6),
              Text(
                'Supabase সংযোগ হয়নি',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text(
                  msg,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'কী করবেন',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 10),
              const _Step(
                n: '১',
                title: '.env ফাইল তৈরি করুন',
                body:
                    'প্রজেক্টের রুটে .env.example কপি করে .env নামে সেভ করুন।',
              ),
              const SizedBox(height: 10),
              const _Step(
                n: '২',
                title: 'Supabase কী বসান',
                body:
                    'SUPABASE_URL ও SUPABASE_ANON_KEY পূরণ করুন (Supabase Dashboard → Project Settings → API)।',
              ),
              const SizedBox(height: 10),
              const _Step(
                n: '৩',
                title: 'অ্যাপ পুনরায় চালু করুন',
                body:
                    'flutter run আবার চালালে সেটআপ স্ক্রিন আর দেখাবে না।',
              ),
              const Spacer(),
              MonoButton(
                label: 'কপি: SUPABASE_URL দরকার',
                leading: Icons.copy_rounded,
                onPressed: () async {
                  await Clipboard.setData(const ClipboardData(
                      text: 'SUPABASE_URL / SUPABASE_ANON_KEY'));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('ক্লিপবোর্ডে কপি হয়েছে।'),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String title;
  final String body;
  const _Step({
    required this.n,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.cyan,
            shape: BoxShape.circle,
          ),
          child: Text(
            n,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.void1,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.smoke,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
