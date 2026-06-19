import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:uni_track/config/app_config.dart';
import 'package:uni_track/splashPage/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  } on AuthException catch (e) {
    // Handle authentication errors
  } on PostgrestException catch (e) {
    switch (e.code) {
      case 'PGRST301':
        break;
      case 'PGRST116':
        break;
      default:
    }
  } on TimeoutException catch (e) {
    // Handle timeout errors
  } on SocketException catch (e) {
  } on FormatException catch (e) {
    // Handle format errors
  } catch (e) {
    // Handle any other unexpected errors
  }

  // Run your app regardless of connection status
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: SplashScreen(),
    );
  }
}
