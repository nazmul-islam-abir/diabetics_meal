import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/supabase_service.dart';
import 'screens/home_shell.dart';
import 'screens/auth_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load 'bn' locale data so DateFormat(_, 'bn') in screens can render
  // Bangla month / weekday names without throwing LocaleDataException.
  await initializeDateFormatting('bn');
  await SupabaseService.init();
  runApp(const AmarDietApp());
}

class AmarDietApp extends StatelessWidget {
  const AmarDietApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'আমার ডায়েট',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0F6E56),
        useMaterial3: true,
        fontFamily: 'NotoSansBengali',
        // Elderly-friendly defaults: large body text, generous touch targets.
        textTheme: const TextTheme(
          headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(fontSize: 18, height: 1.35),
          bodyMedium: TextStyle(fontSize: 17, height: 1.35),
          labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, 56),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(64, 56),
            textStyle: const TextStyle(fontSize: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          labelStyle: const TextStyle(fontSize: 18),
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: SupabaseService.currentUser == null
          ? const AuthScreen()
          : const HomeShell(),
    );
  }
}
