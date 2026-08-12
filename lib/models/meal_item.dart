/// Lightweight model for a food item, used both by the plan and the log.
class MealItem {
  final String id;
  final String nameBn;
  final String category; // breakfast / carb / protein / vegetable / dal / snack
  final double carbG;
  final double proteinG;
  final double fatG;
  final double fiberG;
  final double sodiumMg;
  final double potassiumMg;
  final double phosphorusMg;
  final String giCategory; // low / medium / high
  final String? portionLabel;
  final double? portionG;
  final String affordability; // low_cost / medium / premium
  final bool commonInBd;
  final String effort; // easy / medium / hard
  final String healthiness; // good / neutral / bad
  final List<String> tags;

  MealItem({
    required this.id,
    required this.nameBn,
    required this.category,
    required this.carbG,
    required this.proteinG,
    required this.fatG,
    required this.fiberG,
    required this.sodiumMg,
    required this.potassiumMg,
    required this.phosphorusMg,
    required this.giCategory,
    this.portionLabel,
    this.portionG,
    this.affordability = 'low_cost',
    this.commonInBd = true,
    this.effort = 'easy',
    this.healthiness = 'good',
    this.tags = const [],
  });

  factory MealItem.fromJson(Map<String, dynamic> json) {
    return MealItem(
      id: (json['id'] ?? '') as String,
      nameBn: (json['name_bn'] ?? '') as String,
      category: (json['category'] ?? 'snack') as String,
      carbG: ((json['carb_g'] ?? 0) as num).toDouble(),
      proteinG: ((json['protein_g'] ?? 0) as num).toDouble(),
      fatG: ((json['fat_g'] ?? 0) as num).toDouble(),
      fiberG: ((json['fiber_g'] ?? 0) as num).toDouble(),
      sodiumMg: ((json['sodium_mg'] ?? 0) as num).toDouble(),
      potassiumMg: ((json['potassium_mg'] ?? 0) as num).toDouble(),
      phosphorusMg: ((json['phosphorus_mg'] ?? 0) as num).toDouble(),
      giCategory: (json['gi_category'] ?? 'low') as String,
      portionLabel: json['portion_label'] as String?,
      portionG: json['portion_g'] != null
          ? ((json['portion_g']) as num).toDouble()
          : null,
      affordability: (json['affordability'] ?? 'low_cost') as String,
      commonInBd: json['common_in_bd'] as bool? ?? true,
      effort: (json['effort'] ?? 'easy') as String,
      healthiness: (json['healthiness'] ?? 'good') as String,
      tags: (json['tags'] as List?)?.cast<String>() ?? const [],
    );
  }

  bool get isCheap => affordability == 'low_cost';
  bool get isLocal => commonInBd;
}

/// A single planned meal slot (e.g. "breakfast/carb", "lunch/protein").
class MealSlotPlan {
  final String slot; // breakfast | morning_snack | lunch | evening_snack | dinner
  final String role; // main | carb | protein | vegetable | dal | snack
  final MealItem food;
  final List<MealItem> alternatives;

  const MealSlotPlan({
    required this.slot,
    required this.role,
    required this.food,
    this.alternatives = const [],
  });
}

/// A single logged entry from `meal_intake_log`.
class MealLogEntry {
  final String id;
  final String mealSlot;
  final String? foodId;
  final String foodNameBn;
  final String status; // eaten | swap | off_plan
  final String impact; // good | neutral | bad
  final String? notes;
  final String? impactReason;
  final int? planDay; // 1..30 — which rotation day this entry belongs to
  final DateTime createdAt;

  const MealLogEntry({
    required this.id,
    required this.mealSlot,
    required this.foodId,
    required this.foodNameBn,
    required this.status,
    required this.impact,
    this.notes,
    this.impactReason,
    this.planDay,
    required this.createdAt,
  });

  factory MealLogEntry.fromJson(Map<String, dynamic> json) {
    return MealLogEntry(
      id: (json['id'] ?? '') as String,
      mealSlot: (json['meal_slot'] ?? '') as String,
      foodId: json['food_id'] as String?,
      foodNameBn: (json['food_name_bn'] ?? '') as String,
      status: (json['status'] ?? 'eaten') as String,
      impact: (json['impact'] ?? 'neutral') as String,
      notes: json['notes'] as String?,
      impactReason: json['impact_reason'] as String?,
      planDay: json['plan_day'] is int
          ? json['plan_day'] as int
          : (json['plan_day'] is num
              ? (json['plan_day'] as num).toInt()
              : null),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
