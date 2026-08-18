// ignore_for_file: implementation_imports
// We import the package's src/* files directly because the package's
// public entry file (`package:animated_notch_bottom_bar/animated_notch_bottom_bar.dart`)
// is malformed in this toolchain. The src files compile fine.
import 'package:animated_notch_bottom_bar/src/models/bottom_bar_item_model.dart';
import 'package:animated_notch_bottom_bar/src/notch_bottom_bar.dart';
import 'package:animated_notch_bottom_bar/src/notch_bottom_bar_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'meal_plan_screen.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'medicine_screen.dart';
import 'workout_screen.dart';

/// Main shell with an `AnimatedNotchBottomBar` icons-only bottom bar.
///
/// The bar uses the package's morphing circular notch indicator — far
/// more premium than Material's default NavigationBar — and only shows
/// the icon for each tab (no text labels).
///
/// "আজ" (Today) now contains the full CRUD for the user's own meal
/// setup, so the separate "পরিকল্পনা" tab has been folded in.
/// A fourth tab — "ওষুধ" — was added for the medicine tracker so
/// elderly users have their pill schedule alongside their meal plan.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// Each screen is built on demand the first time its tab is opened
  /// and then kept alive in [_cache] so it doesn't refetch when the
  /// user navigates away and back. This replaces the previous
  /// IndexedStack which mounted all 5 tabs at once and caused every
  /// screen's `_load()` to fire in parallel during cold start (the
  /// dominant source of the "app crashes on launch" symptom).
  late final List<Widget?> _cache =
      List<Widget?>.filled(5, null, growable: false);

  final NotchBottomBarController _notchCtrl =
      NotchBottomBarController(index: 0);

  /// 5 entries — one per tab. The package throws if you go beyond 5.
  static const List<_NavItem> _NavItems = <_NavItem>[
    _NavItem(
      label: 'আজ',
      icon: Icons.restaurant_menu,
      outline: Icons.restaurant_menu_outlined,
    ),
    _NavItem(
      label: 'ওষুধ',
      icon: Icons.medication,
      outline: Icons.medication_outlined,
    ),
    _NavItem(
      label: 'ব্যায়াম',
      icon: Icons.fitness_center,
      outline: Icons.fitness_center_outlined,
    ),
    _NavItem(
      label: 'ড্যাশবোর্ড',
      icon: Icons.insights,
      outline: Icons.insights_outlined,
    ),
    _NavItem(
      label: 'প্রোফাইল',
      icon: Icons.person,
      outline: Icons.person_outline,
    ),
  ];

  Widget _pageAt(int i) {
    return _cache[i] ??= _buildPage(i);
  }

  Widget _buildPage(int i) {
    switch (i) {
      case 0:
        return const MealPlanScreen();
      case 1:
        return const MedicineScreen();
      case 2:
        return const WorkoutScreen();
      case 3:
        return const DashboardScreen();
      case 4:
        return const ProfileScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  void _onTap(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
    _notchCtrl.jumpTo(i);
  }

  @override
  void dispose() {
    _notchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Transparent so the cosmos backdrop drifts behind the pages.
      backgroundColor: Colors.transparent,
      extendBody: true,
      // IndexedStack with a single pre-built child keeps the active tab's
      // state (scroll position, animations) alive when the user swaps tabs,
      // and previously-visited tabs are kept alive in [_cache] so they
      // don't refetch either. Only the active tab's `initState` runs
      // each time it is selected for the first time — that's what kills
      // the cold-start RPC storm.
      body: IndexedStack(
        index: _index,
        children: List<Widget>.generate(5, _pageAt),
      ),
      bottomNavigationBar: AnimatedNotchBottomBar(
        notchBottomBarController: _notchCtrl,
        bottomBarItems: List<BottomBarItem>.generate(
          _NavItems.length,
          (i) => BottomBarItem(
            inActiveItem: Icon(
              _NavItems[i].outline,
              size: 24,
              color: AppColors.smoke,
            ),
            activeItem: Icon(
              _NavItems[i].icon,
              size: 24,
              color: AppColors.void1,
            ),
            itemLabel: _NavItems[i].label, // tooltip when showLabel: false
          ),
        ),
        onTap: _onTap,
        kIconSize: 24,
        kBottomRadius: 28,
        // Icons only — no text labels under each tab.
        showLabel: false,
        // Match the editorial dark notch from the previous custom bar.
        notchColor: AppColors.ink,
        color: AppColors.paper,
        showShadow: true,
        elevation: 6,
        shadowElevation: 8,
      ),
    );
  }
}

/// Internal nav-item descriptor kept private to this file.
class _NavItem {
  final String label;
  final IconData icon;
  final IconData outline;
  const _NavItem({
    required this.label,
    required this.icon,
    required this.outline,
  });
}
