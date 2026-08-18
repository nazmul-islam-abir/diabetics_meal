import '../models/meal_item.dart';

/// Client-side impact classifier.
///
/// Produces a [MealImpact] (good / neutral / bad + a Bengali reason) for a food
/// given the user's classification from the server. This is the same logic
/// the SQL `classify_user()` function uses, just surfaced for the UI so the
/// user immediately sees whether a swap is good or bad.
///
/// The authoritative answer still comes from the server via `record_meal_intake`,
/// but this lets the UI show feedback offline / instantly.
class ImpactEngine {
  static MealImpact judge({
    required MealItem food,
    required MealItem? original,
    required Classification cls,
  }) {
    final restrictions = cls.restrictionFlags.toSet();
    final gi = food.giCategory;
    final carb = food.carbG;
    final reasons = <String>[];

    // CKD — too much potassium / phosphorus → bad
    if (restrictions.contains('ckd_restricted_high_k') && food.potassiumMg > 200) {
      return const MealImpact(
        level: 'bad',
        reason: 'উচ্চ পটাশিয়াম — কিডনি রোগে সীমিত রাখুন',
      );
    }
    if (restrictions.contains('ckd_restricted_high_phos') && food.phosphorusMg > 150) {
      return const MealImpact(
        level: 'bad',
        reason: 'উচ্চ ফসফরাস — কিডনি রোগে সীমিত রাখুন',
      );
    }

    // BP — high sodium → bad
    if (restrictions.contains('low_sodium_required') && food.sodiumMg > 250) {
      return const MealImpact(
        level: 'bad',
        reason: 'উচ্চ সোডিয়াম — উচ্চ রক্তচাপে এড়িয়ে চলুন',
      );
    }

    // Heart disease — high fat → bad
    if (restrictions.contains('heart_moderate_restricted') && food.fatG > 12) {
      return const MealImpact(
        level: 'bad',
        reason: 'উচ্চ চর্বি — হৃদরোগে সীমিত রাখুন',
      );
    }

    // Glucose tier — high GI or too much carb → bad
    if (cls.glucoseTier == 'poor' && gi == 'high') {
      return const MealImpact(
        level: 'bad',
        reason: 'উচ্চ GI — গ্লুকোজ দ্রুত বাড়াবে',
      );
    }
    if (carb > cls.maxCarbPerMeal) {
      return MealImpact(
        level: 'bad',
        reason: 'এক বেলায় সর্বোচ্চ ${cls.maxCarbPerMeal.toInt()} গ্রাম কার্ব সুপারিশ — এটি বেশি',
      );
    }

    // Compare against the original plan if the user swapped
    if (original != null && original.id != food.id) {
      if (food.healthiness == 'good' && original.healthiness != 'good') {
        return const MealImpact(
          level: 'good',
          reason: 'ভালো বিকল্প — মূল পরিকল্পনার চেয়ে স্বাস্থ্যকর',
        );
      }
      if (food.healthiness == 'bad' && original.healthiness != 'bad') {
        return const MealImpact(
          level: 'bad',
          reason: 'এই বিকল্পটি কম উপকারী — অন্য বিকল্প বিবেচনা করুন',
        );
      }
    }

    // Default: good for "good" healthiness, neutral otherwise
    if (food.healthiness == 'good') {
      reasons.add('GI: ${giLabel(gi)} · পরিকল্পনা অনুযায়ী গ্রহণযোগ্য');
      return MealImpact(level: 'good', reason: reasons.join(' · '));
    }
    if (food.healthiness == 'bad') {
      return const MealImpact(
        level: 'bad',
        reason: 'এই খাবারটি ডায়াবেটিস-বান্ধব নয় — এড়িয়ে চলুন',
      );
    }
    return const MealImpact(
      level: 'neutral',
      reason: 'মাঝারি প্রভাব — পরিমাণ সীমিত রাখুন',
    );
  }

  static String giLabel(String gi) {
    switch (gi) {
      case 'low':
        return 'কম GI';
      case 'medium':
        return 'মাঝারি GI';
      case 'high':
        return 'উচ্চ GI';
      default:
        return gi;
    }
  }
}

class MealImpact {
  final String level; // 'good' | 'neutral' | 'bad'
  final String reason;
  const MealImpact({required this.level, required this.reason});
}

/// Mirror of the SQL `classify_user()` return shape.
class Classification {
  final String glucoseTier;
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

  factory Classification.fromJson(Map<String, dynamic> json) {
    return Classification(
      glucoseTier: (json['glucose_tier'] ?? 'unknown') as String,
      bmiTier: (json['bmi_tier'] ?? 'unknown') as String,
      bpTier: (json['bp_tier'] ?? 'unknown') as String,
      maxCarbPerMeal: ((json['max_carb_per_meal'] ?? 35) as num).toDouble(),
      allowedGi: (json['allowed_gi'] as List?)?.cast<String>() ?? const [],
      restrictionFlags:
          (json['restriction_flags'] as List?)?.cast<String>() ?? const [],
      warnings: (json['warnings'] as List?)?.cast<String>() ?? const [],
    );
  }
}
