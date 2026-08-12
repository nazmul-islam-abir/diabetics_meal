import 'package:flutter/material.dart';
import 'meal_plan_screen.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';

/// Main shell with bottom navbar — three destinations:
///   • আজ (Today)   — daily meal plan as a todo list
///   • ড্যাশবোর্ড   — analytics dashboard
///   • প্রোফাইল     — clinical profile + sign-out
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // IndexedStack preserves state so the dashboard doesn't refetch when
  // the user taps "Today" and back.
  final List<Widget> _pages = const [
    MealPlanScreen(initialDay: 1),
    DashboardScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        height: 76,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined, size: 30),
            selectedIcon: Icon(Icons.restaurant_menu, size: 30),
            label: 'আজ',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined, size: 30),
            selectedIcon: Icon(Icons.bar_chart, size: 30),
            label: 'ড্যাশবোর্ড',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline, size: 30),
            selectedIcon: Icon(Icons.person, size: 30),
            label: 'প্রোফাইল',
          ),
        ],
      ),
    );
  }
}
