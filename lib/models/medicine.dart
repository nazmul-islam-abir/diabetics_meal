/// Models for the medicine tracker.
///
/// Mirrors the public.medicines and public.medicine_doses tables
/// in `supabasesql/12_medicine.sql`. The helpers in this file are
/// shared by the editor sheet (preview / bucket classification),
/// the screen (today's timeline), and the dashboard tile (summary).


import 'package:flutter/material.dart';

/// Auto-classified time-of-day bucket. We store this on the server too
/// so editing a schedule later doesn't reclassify history.
enum TimeBucket { morning, noon, afternoon, night }

extension TimeBucketX on TimeBucket {
  String get code {
    switch (this) {
      case TimeBucket.morning:
        return 'morning';
      case TimeBucket.noon:
        return 'noon';
      case TimeBucket.afternoon:
        return 'afternoon';
      case TimeBucket.night:
        return 'night';
    }
  }

  String get labelBn {
    switch (this) {
      case TimeBucket.morning:
        return 'সকাল';
      case TimeBucket.noon:
        return 'দুপুর';
      case TimeBucket.afternoon:
        return 'বিকেল';
      case TimeBucket.night:
        return 'রাত';
    }
  }

  IconData get icon {
    switch (this) {
      case TimeBucket.morning:
        return Icons.wb_sunny_outlined;
      case TimeBucket.noon:
        return Icons.lunch_dining_outlined;
      case TimeBucket.afternoon:
        return Icons.coffee_outlined;
      case TimeBucket.night:
        return Icons.nightlight_outlined;
    }
  }
}

/// Convert the 4 server codes to enum, with a safe fallback.
TimeBucket bucketFromCode(String? code) {
  switch (code) {
    case 'morning':
      return TimeBucket.morning;
    case 'noon':
      return TimeBucket.noon;
    case 'afternoon':
      return TimeBucket.afternoon;
    case 'night':
      return TimeBucket.night;
    default:
      return TimeBucket.morning;
  }
}

/// Classify an HH:mm time into a bucket using the SAME thresholds as
/// the SQL `classify_time_bucket` function so the UI matches the DB.
///   5-11 morning, 11-15 noon, 15-19 afternoon, 19-5 night.
TimeBucket bucketForTime(int hour, int minute) {
  final h = hour;
  final m = minute;
  final minutes = h * 60 + m;
  if (minutes >= 5 * 60 && minutes < 11 * 60) return TimeBucket.morning;
  if (minutes >= 11 * 60 && minutes < 15 * 60) return TimeBucket.noon;
  if (minutes >= 15 * 60 && minutes < 19 * 60) return TimeBucket.afternoon;
  return TimeBucket.night;
}

/// Built-in form options. Order matters — it's the order the picker shows.
const List<String> kMedicineForms = [
  'tablet',
  'capsule',
  'drop',
  'syrup',
  'injection',
  'inhaler',
  'cream',
  'other',
];

String medicineFormBn(String form) {
  switch (form) {
    case 'tablet':
      return 'ট্যাবলেট';
    case 'capsule':
      return 'ক্যাপসুল';
    case 'drop':
      return 'ফোঁটা';
    case 'syrup':
      return 'সিরাপ';
    case 'injection':
      return 'ইনজেকশন';
    case 'inhaler':
      return 'ইনহেলার';
    case 'cream':
      return 'ক্রিম';
    case 'other':
      return 'অন্যান্য';
    default:
      return form;
  }
}

IconData medicineFormIcon(String form) {
  switch (form) {
    case 'tablet':
      return Icons.medication_outlined;
    case 'capsule':
      return Icons.medication_liquid_outlined;
    case 'drop':
      return Icons.water_drop_outlined;
    case 'syrup':
      return Icons.local_drink_outlined;
    case 'injection':
      return Icons.colorize_outlined;
    case 'inhaler':
      return Icons.air_outlined;
    case 'cream':
      return Icons.healing_outlined;
    default:
      return Icons.medical_services_outlined;
  }
}

const List<String> kMealRelations = [
  'empty_stomach',
  'before_food',
  'with_food',
  'after_food',
  'any',
];

String mealRelationBn(String relation) {
  switch (relation) {
    case 'empty_stomach':
      return 'খালি পেটে';
    case 'before_food':
      return 'খাবারের আগে';
    case 'with_food':
      return 'খাবারের সঙ্গে';
    case 'after_food':
      return 'খাবারের পরে';
    case 'any':
      return 'যেকোনো সময়';
    default:
      return relation;
  }
}

/// One scheduled intake time within a medicine's schedule.
class MedicineScheduleSlot {
  /// "HH:mm" — 24h, no seconds.
  final String time;
  final TimeBucket bucket;

  const MedicineScheduleSlot({required this.time, required this.bucket});

  factory MedicineScheduleSlot.fromJson(Map<String, dynamic> json) {
    return MedicineScheduleSlot(
      time: (json['time'] ?? '') as String,
      bucket: bucketFromCode(json['bucket'] as String?),
    );
  }

  Map<String, dynamic> toJson() =>
      {'time': time, 'bucket': bucket.code};

  factory MedicineScheduleSlot.fromTime(int hour, int minute) {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return MedicineScheduleSlot(
      time: '$h:$m',
      bucket: bucketForTime(hour, minute),
    );
  }
}

/// Catalogue row for a single medicine.
class Medicine {
  final String id;
  final String nameBn;
  final String? nameEn;
  final String form; // see kMedicineForms
  final String? strength;
  final double doseAmount;
  final String doseUnit;
  final String mealRelation; // see kMealRelations
  final List<MedicineScheduleSlot> schedule;
  final DateTime startDate;
  final DateTime? endDate;
  final String? color;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Medicine({
    required this.id,
    required this.nameBn,
    this.nameEn,
    required this.form,
    this.strength,
    required this.doseAmount,
    required this.doseUnit,
    required this.mealRelation,
    this.schedule = const [],
    required this.startDate,
    this.endDate,
    this.color,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Medicine.fromJson(Map<String, dynamic> json) {
    final sched = (json['schedule'] as List?)
            ?.map((e) => MedicineScheduleSlot.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList() ??
        const <MedicineScheduleSlot>[];
    return Medicine(
      id: (json['id'] ?? '') as String,
      nameBn: (json['name_bn'] ?? '') as String,
      nameEn: json['name_en'] as String?,
      form: (json['form'] ?? 'tablet') as String,
      strength: json['strength'] as String?,
      doseAmount:
          json['dose_amount'] != null ? ((json['dose_amount']) as num).toDouble() : 1.0,
      doseUnit: (json['dose_unit'] ?? 'unit') as String,
      mealRelation: (json['meal_relation'] ?? 'any') as String,
      schedule: sched,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: json['end_date'] != null
          ? DateTime.parse(json['end_date'] as String)
          : null,
      color: json['color'] as String?,
      notes: json['notes'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Pretty dose label: "১ ট্যাবলেট", "০.৫ ফোঁটা", etc.
  String get doseLabel {
    final amt = _banglaAmount(doseAmount);
    final unit = doseUnit.isEmpty || doseUnit == 'unit'
        ? medicineFormBn(form)
        : doseUnit;
    return '$amt $unit';
  }

  String get scheduleSummary {
    if (schedule.isEmpty) return '';
    final times = schedule.map((s) => s.time).join(', ');
    return times;
  }

  bool get isOngoing => endDate == null;

  Medicine copyWith({
    String? nameBn,
    String? nameEn,
    bool clearNameEn = false,
    String? form,
    String? strength,
    bool clearStrength = false,
    double? doseAmount,
    String? doseUnit,
    String? mealRelation,
    List<MedicineScheduleSlot>? schedule,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    String? color,
    bool clearColor = false,
    String? notes,
    bool clearNotes = false,
    bool? isActive,
  }) {
    return Medicine(
      id: id,
      nameBn: nameBn ?? this.nameBn,
      nameEn: clearNameEn ? null : (nameEn ?? this.nameEn),
      form: form ?? this.form,
      strength: clearStrength ? null : (strength ?? this.strength),
      doseAmount: doseAmount ?? this.doseAmount,
      doseUnit: doseUnit ?? this.doseUnit,
      mealRelation: mealRelation ?? this.mealRelation,
      schedule: schedule ?? this.schedule,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      color: clearColor ? null : (color ?? this.color),
      notes: clearNotes ? null : (notes ?? this.notes),
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// One dose row from the today's-timeline RPC.
class MedicineDose {
  final String? doseId; // null when not yet logged
  final String medicineId;
  final String nameBn;
  final String? nameEn;
  final String form;
  final String? strength;
  final double doseAmount;
  final String doseUnit;
  final String mealRelation;
  final String? color;
  final String? medicineNotes;
  final String scheduledTime; // HH:mm
  final TimeBucket bucket;
  final String? status; // taken | skipped | missed
  final DateTime? takenAt;
  final String? note;
  final bool isOverdue;

  const MedicineDose({
    this.doseId,
    required this.medicineId,
    required this.nameBn,
    this.nameEn,
    required this.form,
    this.strength,
    required this.doseAmount,
    required this.doseUnit,
    required this.mealRelation,
    this.color,
    this.medicineNotes,
    required this.scheduledTime,
    required this.bucket,
    this.status,
    this.takenAt,
    this.note,
    this.isOverdue = false,
  });

  factory MedicineDose.fromJson(Map<String, dynamic> json) {
    return MedicineDose(
      doseId: json['dose_id'] as String?,
      medicineId: (json['medicine_id'] ?? '') as String,
      nameBn: (json['name_bn'] ?? '') as String,
      nameEn: json['name_en'] as String?,
      form: (json['form'] ?? 'tablet') as String,
      strength: json['strength'] as String?,
      doseAmount:
          json['dose_amount'] != null ? ((json['dose_amount']) as num).toDouble() : 1.0,
      doseUnit: (json['dose_unit'] ?? 'unit') as String,
      mealRelation: (json['meal_relation'] ?? 'any') as String,
      color: json['color'] as String?,
      medicineNotes: json['medicine_notes'] as String?,
      scheduledTime: (json['scheduled_time'] ?? '') as String,
      bucket: bucketFromCode(json['bucket'] as String?),
      status: json['status'] as String?,
      takenAt: json['taken_at'] != null
          ? DateTime.parse(json['taken_at'] as String)
          : null,
      note: json['note'] as String?,
      isOverdue: json['is_overdue'] as bool? ?? false,
    );
  }

  bool get isTaken => status == 'taken';
  bool get isSkipped => status == 'skipped';
  bool get isMissed => status == 'missed';
  bool get isPending => doseId == null && !isMissed;

  String get doseLabel {
    final amt = _banglaAmount(doseAmount);
    final unit = doseUnit.isEmpty || doseUnit == 'unit'
        ? medicineFormBn(form)
        : doseUnit;
    return '$amt $unit';
  }
}

/// Adherence summary from `get_medicine_adherence`.
class MedicineAdherence {
  final int totalDoses;
  final int taken;
  final int skipped;
  final int missed;
  final double takenPct;
  final int currentStreakDays;
  final int windowDays;

  const MedicineAdherence({
    required this.totalDoses,
    required this.taken,
    required this.skipped,
    required this.missed,
    required this.takenPct,
    required this.currentStreakDays,
    required this.windowDays,
  });

  // Aliases used by the dashboard for a uniform "% X" tile.
  double get takenPercent => takenPct;
  int get total => totalDoses;

  factory MedicineAdherence.fromJson(Map<String, dynamic> json) {
    return MedicineAdherence(
      totalDoses: (json['total_doses'] ?? 0) as int,
      taken: (json['taken'] ?? 0) as int,
      skipped: (json['skipped'] ?? 0) as int,
      missed: (json['missed'] ?? 0) as int,
      takenPct: ((json['taken_pct'] ?? 0) as num).toDouble(),
      currentStreakDays: (json['current_streak_days'] ?? 0) as int,
      windowDays: (json['window_days'] ?? 7) as int,
    );
  }

  static const empty = MedicineAdherence(
    totalDoses: 0,
    taken: 0,
    skipped: 0,
    missed: 0,
    takenPct: 0,
    currentStreakDays: 0,
    windowDays: 7,
  );
}

/// Format a dose amount in Bangla numerals so it reads naturally.
///   1.0  -> '১'
///   0.5  -> '০.৫'
String _banglaAmount(double v) {
  final s = v == v.toInt() ? v.toInt().toString() : v.toString();
  return s.replaceAllMapped(
      RegExp(r'[0-9]'), (m) => String.fromCharCode(0x09E6 + int.parse(m[0]!)));
}

/// Public re-export so widgets don't need to import a hidden helper.
String formatBanglaDouble(double v) => _banglaAmount(v);