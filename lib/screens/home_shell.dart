import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import 'meal_plan_screen.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';

/// Main shell with a custom editorial bottom bar.
///
/// The bar uses a morphing pill indicator that travels between the three
/// destinations — far more premium than Material's default NavigationBar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // IndexedStack preserves state so the dashboard doesn't refetch when
  // the user taps "Today" and back.
  static final List<Widget> _pages = <Widget>[
    const MealPlanScreen(initialDay: 1),
    const DashboardScreen(),
    const ProfileScreen(),
  ];

  static const _NavItems = <_NavItem>[
    _NavItem(label: 'আজ', icon: Icons.restaurant_menu, outline: Icons.restaurant_menu_outlined),
    _NavItem(label: 'ড্যাশবোর্ড', icon: Icons.insights, outline: Icons.insights_outlined),
    _NavItem(label: 'প্রোফাইল', icon: Icons.person, outline: Icons.person_outline),
  ];

  void _onTap(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: _EditorialNavBar(
        index: _index,
        items: _NavItems,
        onTap: _onTap,
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData outline;
  const _NavItem({required this.label, required this.icon, required this.outline});
}

class _EditorialNavBar extends StatelessWidget {
  final int index;
  final List<_NavItem> items;
  final ValueChanged<int> onTap;

  const _EditorialNavBar({
    required this.index,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(top: BorderSide(color: AppColors.graphite, width: 1)),
      ),
      padding: EdgeInsets.only(top: 8, bottom: mq.padding.bottom + 8),
      child: SizedBox(
        height: 64,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth / items.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: AppMotion.medium,
                curve: AppMotion.emphasized,
                left: w * index + 12,
                top: 4,
                bottom: 4,
                width: w - 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              Row(
                children: [
                  for (int i = 0; i < items.length; i++)
                    Expanded(
                      child: Pressable(
                        onTap: () => onTap(i),
                        child: SizedBox(
                          height: 56,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedSwitcher(
                                duration: AppMotion.short,
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(scale: anim, child: child),
                                child: Icon(
                                  i == index ? items[i].icon : items[i].outline,
                                  key: ValueKey('$i-$index'),
                                  color: i == index ? AppColors.paper : AppColors.ink,
                                  size: 24,
                                ),
                              ),
                              AnimatedSize(
                                duration: AppMotion.short,
                                curve: AppMotion.standard,
                                child: SizedBox(width: i == index ? 8 : 0),
                              ),
                              AnimatedSize(
                                duration: AppMotion.short,
                                curve: AppMotion.standard,
                                child: i == index
                                    ? Text(
                                        items[i].label,
                                        style: const TextStyle(
                                          color: AppColors.paper,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}
