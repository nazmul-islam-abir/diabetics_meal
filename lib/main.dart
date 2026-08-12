import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/supabase_service.dart';
import 'screens/home_shell.dart';
import 'screens/auth_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock the chrome to a clean, editorial light surface.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: AppColors.paper,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.paper,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
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
      theme: AppTheme.light(),
      home: SupabaseService.currentUser == null
          ? const AuthScreen()
          : const HomeShell(),
    );
  }
}
