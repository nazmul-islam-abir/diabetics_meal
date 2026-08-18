import '../models/user_profile.dart';

/// Client-side mirror of public.classify_user() in the SQL schema.
/// Used for instant UI feedback (e.g. showing warnings during onboarding)
/// before the authoritative server-side call runs via Supabase RPC.
/// Keep this logic in sync with the SQL function if you change either one.
class Classification {
  final String glucoseTier; // good / moderate / poor / unknown
  final String bmiTier;
  final String bpTier;
  final double maxCarbPerMeal;
  final List<String> allowedGi;
  final List<String> restrictionFlags;
  final List<String> warnings;

  Classification({
    required this.glucoseTier,
    required this.bmiTier,
    required this.bpTier,
    required this.maxCarbPerMeal,
    required this.allowedGi,
    required this.restrictionFlags,
    required this.warnings,
  });
}

class ClassificationEngine {
  static Classification classify(UserProfile p) {
    final warnings = <String>[];
    final flags = <String>[];

    // Glucose control tier — HbA1c preferred, fasting glucose as fallback.
    String glucoseTier;
    if (p.hba1cPercent != null) {
      final a1c = p.hba1cPercent!;
      glucoseTier = a1c < 7.0 ? 'good' : (a1c <= 8.5 ? 'moderate' : 'poor');
    } else if (p.fastingGlucoseMmol != null) {
      final fg = p.fastingGlucoseMmol!;
      glucoseTier = fg < 7.0 ? 'good' : (fg <= 10.0 ? 'moderate' : 'poor');
    } else {
      glucoseTier = 'unknown';
      warnings.add('গ্লুকোজ বা HbA1c তথ্য দেওয়া হয়নি — সাধারণ মধ্যম-কার্ব পরিকল্পনা দেখানো হচ্ছে');
    }

    double maxCarb = switch (glucoseTier) {
      'good' => 45,
      'moderate' => 35,
      'poor' => 25,
      _ => 35,
    };
    if (p.mealSizePref == 'small') maxCarb -= 5;
    if (p.mealSizePref == 'large') maxCarb += 5;

    final allowedGi = switch (glucoseTier) {
      'poor' => ['low'],
      _ => ['low', 'medium'],
    };

    // BMI tier — Bangladesh/Asian cutoffs.
    final bmi = p.bmi;
    final bmiTier = bmi < 18.5
        ? 'underweight'
        : (bmi < 23 ? 'normal' : (bmi < 25 ? 'overweight' : 'obese'));

    // BP tier — ACC/AHA staging.
    String bpTier = 'unknown';
    if (p.systolicBp != null && p.diastolicBp != null) {
      final s = p.systolicBp!, d = p.diastolicBp!;
      if (s >= 140 || d >= 90) {
        bpTier = 'stage2';
      } else if (s >= 130 || d >= 80) {
        bpTier = 'stage1';
      } else if (s >= 120) {
        bpTier = 'elevated';
      } else {
        bpTier = 'normal';
      }
    }
    if (bpTier == 'stage1' || bpTier == 'stage2') {
      flags.add('low_sodium_required');
    }

    if (p.hasCkd) {
      flags.addAll(['ckd_restricted_high_k', 'ckd_restricted_high_phos']);
      warnings.add('কিডনি রোগের কারণে পটাশিয়াম/ফসফরাসযুক্ত খাবার সীমিত করা হয়েছে — নেফ্রোলজিস্টের পরামর্শ অনুসরণ করুন');
    }
    if (p.hasHeartDisease) {
      flags.add('heart_moderate_restricted');
    }
    if (p.onInsulin) {
      warnings.add('আপনি ইনসুলিন গ্রহণ করছেন — খাবারের সময় ও পরিমাণ ধারাবাহিক রাখা জরুরি। কোনো বেলা বাদ দেওয়ার আগে ডাক্তারের পরামর্শ নিন।');
    }
    if (p.hasAnemia) {
      warnings.add('রক্তস্বল্পতা থাকায় আয়রন সমৃদ্ধ খাবার (শিং মাছ, কচু শাক) অগ্রাধিকার দেওয়া হচ্ছে');
    }

    return Classification(
      glucoseTier: glucoseTier,
      bmiTier: bmiTier,
      bpTier: bpTier,
      maxCarbPerMeal: maxCarb,
      allowedGi: allowedGi,
      restrictionFlags: flags,
      warnings: warnings,
    );
  }
}
