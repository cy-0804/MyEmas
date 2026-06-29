import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_settings.dart';
import 'medication_dashboard_view.dart';
import 'package:easy_localization/easy_localization.dart';
import 'session_manager.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  await initMedicationNotifications();
  await AppSettings().init();
  await SessionManager().init();
  _dumpDb();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ms'), Locale('zh')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: const MyApp(),
    ),
  );
}

Future<void> _dumpDb() async {
  try {
    debugPrint('=== DUMPING DATABASE ===');
    final u = Supabase.instance.client.auth.currentUser;
    if (u == null) {
      debugPrint('No current user.');
      return;
    }
    debugPrint('Current user: ${u.id}');
    final scheds = await Supabase.instance.client
        .from('schedule')
        .select()
        .eq('elderly_id', u.id);
    debugPrint('Schedules: ${scheds.length}');
    for (var s in scheds as List) {
      debugPrint(
        ' - Schedule: ${s['schedule_id']} | title: ${s['title']} | notes: ${s['notes']}',
      );
    }

    final meds = await Supabase.instance.client.from('medications').select();
    debugPrint('All Medications in DB: ${meds.length}');
    for (var m in meds as List) {
      debugPrint(' - Med RAW: $m');
      if (m['schedule_id'] == null) {
        debugPrint('CLEANING ORPHANED MEDICATION: ${m['medication_id']}');
        await Supabase.instance.client
            .from('medications')
            .delete()
            .eq('medication_id', m['medication_id']);
      }
    }
    debugPrint('=== END DUMP & CLEANUP ===');
  } catch (e, st) {
    debugPrint('Dump Error: $e\n$st');
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings(),
      builder: (context, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'MyEmas'.tr(),
          debugShowCheckedModeBanner: false,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF53A37A),
            ),
            useMaterial3: true,
          ),
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(AppSettings().textScaleFactor),
              ),
              child: child!,
            );
          },
          home: const LoginScreen(),
        );
      },
    );
  }
}
