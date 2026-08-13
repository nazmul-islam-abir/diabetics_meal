import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/user_profile.dart';
import '../models/meal_item.dart';

/// Thin wrapper around the Supabase client used by Amar Diet.
///
/// Setup:
///   1. Create a Supabase project.
///   2. Run the SQL files in `supabasesql/` in order (01 → 07).
///   3. Copy `.env.example` to `.env` and fill in SUPABASE_URL + SUPABASE_ANON_KEY.
///   4. Call SupabaseService.init() once in main().
class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> init() async {
    await dotenv.load(fileName: '.env');
    final url = dotenv.env['SUPABASE_URL'];
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'];
    if (url == null || anonKey == null || url.isEmpty || anonKey.isEmpty) {
      throw Exception(
        'Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env — copy .env.example.',
      );
    }
    await Supabase.initialize(url: url, anonKey: anonKey);
  }

  static User? get currentUser => client.auth.currentUser;

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String mobile,
  }) {
    return client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName.trim(),
        'mobile': mobile.trim(),
      },
    );
  }

  static Future<AuthResponse> signIn(String email, String password) {
    return client.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() => client.auth.signOut();

  /// Updates the auth user's user_metadata (used to edit name/mobile after signup).
  static Future<void> updateAccountMeta({String? fullName, String? mobile}) async {
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user.');
    final meta = Map<String, dynamic>.from(user.userMetadata ?? {});
    if (fullName != null) meta['full_name'] = fullName.trim();
    if (mobile != null) meta['mobile'] = mobile.trim();
    await client.auth.updateUser(UserAttributes(data: meta));
  }

  // ----------- PROFILE -----------

  /// Reads the user's profile row. Returns null if they haven't onboarded yet.
  static Future<UserProfile?> fetchProfile() async {
    final userId = currentUser?.id;
    if (userId == null) return null;
    final resp = await client
        .from('user_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (resp == null) return null;
    final m = Map<String, dynamic>.from(resp);
    final meta = currentUser?.userMetadata ?? const {};
    return UserProfile(
      fullName: (m['full_name'] as String?) ?? (meta['full_name'] as String?),
      mobile: (m['mobile'] as String?) ?? (meta['mobile'] as String?),
      age: (m['age'] ?? 0) as int,
      sex: (m['sex'] ?? 'male') as String,
      weightKg: ((m['weight_kg'] ?? 0) as num).toDouble(),
      heightCm: ((m['height_cm'] ?? 0) as num).toDouble(),
      fastingGlucoseMmol: m['fasting_glucose_mmol'] != null
          ? ((m['fasting_glucose_mmol']) as num).toDouble()
          : null,
      postMealGlucoseMmol: m['post_meal_glucose_mmol'] != null
          ? ((m['post_meal_glucose_mmol']) as num).toDouble()
          : null,
      randomGlucoseMmol: m['random_glucose_mmol'] != null
          ? ((m['random_glucose_mmol']) as num).toDouble()
          : null,
      hba1cPercent: m['hba1c_percent'] != null
          ? ((m['hba1c_percent']) as num).toDouble()
          : null,
      onInsulin: (m['on_insulin'] ?? false) as bool,
      medication: m['medication'] as String?,
      systolicBp: m['systolic_bp'] as int?,
      diastolicBp: m['diastolic_bp'] as int?,
      hasCkd: (m['has_ckd'] ?? false) as bool,
      ckdStage: m['ckd_stage'] as int?,
      hasHeartDisease: (m['has_heart_disease'] ?? false) as bool,
      hasAnemia: (m['has_anemia'] ?? false) as bool,
      otherConditions: m['other_conditions'] as String?,
      activityLevel: (m['activity_level'] ?? 'low') as String,
      mealSizePref: (m['meal_size_pref'] ?? 'medium') as String,
      foodPreference: (m['food_preference'] ?? 'omnivore') as String,
    );
  }

  /// Upserts the user's clinical profile (public.user_profiles).
  ///
  /// We pass `onConflict: 'user_id'` so Postgres knows the merge target and
  /// doesn't silently fail on update. Without it, an upsert of an existing
  /// row can throw a 400 that bubbles up and crashes the app.
  static Future<void> saveProfile(UserProfile profile) async {
    final userId = currentUser?.id;
    if (userId == null) {
      throw StateError('No authenticated user — sign in before saving a profile.');
    }
    await client
        .from('user_profiles')
        .upsert(
          profile.toSupabaseRow(userId),
          onConflict: 'user_id',
        );
  }

  // ----------- DAY PLAN + LOG -----------

  /// Calls `get_daily_recommendation(user_id, day)` server-side.
  static Future<Map<String, dynamic>> getDailyRecommendation(int day) async {
    final userId = currentUser?.id;
    if (userId == null) throw StateError('No authenticated user.');
    final result = await client.rpc('get_daily_recommendation', params: {
      'p_user_id': userId,
      'p_day': day,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  /// Calls `food_alternatives_for(food_id, limit)` server-side.
  static Future<List<MealItem>> getAlternatives(String foodId,
      {int limit = 4}) async {
    final result = await client.rpc('food_alternatives_for', params: {
      'p_food_id': foodId,
      'p_limit': limit,
    });
    final list = (result as List?) ?? [];
    return list
        .map((e) => MealItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Calls `record_meal_intake(...)` — returns the log id.
  static Future<String> logMeal({
    required String mealSlot,
    required String? foodId,
    required String foodNameBn,
    required String status, // eaten | swap | off_plan
    required String impact, // good | neutral | bad
    int? planDay,
    String? reason,
    String? notes,
  }) async {
    final id = await client.rpc('record_meal_intake', params: {
      'p_meal_slot': mealSlot,
      'p_food_id': foodId,
      'p_food_name_bn': foodNameBn,
      'p_status': status,
      'p_impact': impact,
      'p_plan_day': planDay,
      'p_reason': reason,
      'p_notes': notes,
    });
    return id.toString();
  }

  static Future<void> hideMeal(String id) async {
    await client.rpc('hide_meal_intake', params: {'p_id': id});
  }

  /// Calls `get_daily_log(date, plan_day)` — returns the meal log for one
  /// day. When [planDay] (1..30) is supplied, only entries logged against
  /// that rotation day are returned. Pass [date] to override the calendar
  /// date (defaults to today in Asia/Dhaka on the server).
  static Future<List<MealLogEntry>> getDailyLog({
    DateTime? date,
    int? planDay,
  }) async {
    final params = <String, dynamic>{};
    if (date != null) {
      params['p_date'] = date.toIso8601String().substring(0, 10);
    }
    if (planDay != null) {
      params['p_plan_day'] = planDay;
    }
    final result = await client.rpc('get_daily_log', params: params);
    final m = Map<String, dynamic>.from(result as Map);
    final items = (m['items'] as List?) ?? [];
    return items
        .map((e) => MealLogEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Calls `get_dashboard_summary(days)` — streak, totals, daily breakdown.
  static Future<Map<String, dynamic>> getDashboardSummary({int days = 7}) async {
    final result = await client.rpc('get_dashboard_summary', params: {
      'p_days': days,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  static Future<Map<String, dynamic>> getWeeklyNutrition({int days = 7}) async {
    final result = await client.rpc('get_weekly_nutrition', params: {
      'p_days': days,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  // ----------- FAVORITES -----------

  static Future<List<String>> listFavorites() async {
    final userId = currentUser?.id;
    if (userId == null) return [];
    final resp = await client
        .from('user_favorites')
        .select('food_id')
        .eq('user_id', userId);
    final list = (resp as List?) ?? [];
    return list.map((e) => (e as Map)['food_id'] as String).toList();
  }

  static Future<void> addFavorite(String foodId) async {
    final userId = currentUser?.id;
    if (userId == null) return;
    await client.from('user_favorites').upsert({
      'user_id': userId,
      'food_id': foodId,
    });
  }

  static Future<void> removeFavorite(String foodId) async {
    final userId = currentUser?.id;
    if (userId == null) return;
    await client
        .from('user_favorites')
        .delete()
        .eq('user_id', userId)
        .eq('food_id', foodId);
  }
}
