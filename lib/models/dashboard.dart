import 'meal_item.dart';
import 'medicine.dart';

class DashboardSummary {
  final int streakDays;
  final int totalItems;
  final int good;
  final int neutral;
  final int bad;

  DashboardSummary({
    this.streakDays = 0,
    this.totalItems = 0,
    this.good = 0,
    this.neutral = 0,
    this.bad = 0,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      streakDays: (json['streak_days'] ?? 0) as int,
      totalItems: (json['total_items'] ?? 0) as int,
      good: (json['good'] ?? 0) as int,
      neutral: (json['neutral'] ?? 0) as int,
      bad: (json['bad'] ?? 0) as int,
    );
  }
}

class DailyNutrition {
  final DateTime date;
  final int calories;
  final int carbs;
  final int protein;
  final int fat;

  DailyNutrition({
    required this.date,
    this.calories = 0,
    this.carbs = 0,
    this.protein = 0,
    this.fat = 0,
  });

  factory DailyNutrition.fromJson(Map<String, dynamic> json) {
    return DailyNutrition(
      date: DateTime.parse(json['date'] as String),
      calories: (json['calories'] ?? 0) as int,
      carbs: (json['carbs'] ?? 0) as int,
      protein: (json['protein'] ?? 0) as int,
      fat: (json['fat'] ?? 0) as int,
    );
  }
}

class DailyMealLog {
  final DateTime date;
  final List<MealSlotGroup> slots;

  DailyMealLog({required this.date, this.slots = const []});
}

class MealSlotGroup {
  final String slot;
  final List<MealLogEntry> items;

  MealSlotGroup({required this.slot, this.items = const []});
}

class DailyMedicines {
  final DateTime date;
  final List<MedicineDose> doses;

  DailyMedicines({required this.date, this.doses = const []});
}
