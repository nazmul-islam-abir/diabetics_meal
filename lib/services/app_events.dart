import 'package:flutter/foundation.dart';

/// Simple in-process pub/sub. Screens subscribe in `initState` and refresh
/// themselves when the relevant counter changes.
///
/// We keep this intentionally minimal — no streams, no codegen. A single
/// `ValueNotifier<int>` per topic is enough: bumping the value triggers
/// every listener, which can then re-fetch whatever it needs.
class AppEvents {
  AppEvents._();

  /// Bumped whenever the user saves their clinical profile. Listeners
  /// (meal plan, dashboard) should re-fetch and re-classify.
  static final ValueNotifier<int> profileChanged = ValueNotifier<int>(0);

  /// Bumped whenever the user logs a meal (eaten / swap / off-plan).
  /// Listeners can re-pull aggregates.
  static final ValueNotifier<int> mealLogged = ValueNotifier<int>(0);

  /// Bumped whenever a medicine is created / updated / deleted or a
  /// dose is marked taken. The medicine screen and the dashboard
  /// adherence tile both listen and re-fetch.
  static final ValueNotifier<int> medicineChanged = ValueNotifier<int>(0);

  /// Bumped whenever a workout session is started, an item is finished
  /// or the session is wrapped up. The workout screen and dashboard
  /// adherence tile both listen and re-fetch.
  static final ValueNotifier<int> workoutChanged = ValueNotifier<int>(0);

  static void notifyProfileChanged() => profileChanged.value++;
  static void notifyMealLogged() => mealLogged.value++;
  static void notifyMedicineChanged() => medicineChanged.value++;
  static void notifyWorkoutChanged() => workoutChanged.value++;
}
