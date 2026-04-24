import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uni_track/landingPage/landing_page.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: 'https://mjlxofeciyxbagygyxrc.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1qbHhvZmVjaXl4YmFneWd5eHJjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3OTE0MzAsImV4cCI6MjA5MjM2NzQzMH0.08h8LNzoTFVE2EpfSo-7M8MytoMtM83vvnXTGCDF_1E',
    );
  } on AuthException catch (e) {
    // Handle authentication errors
    debugPrint('❌ Auth Error: ${e.message}');
    debugPrint('   This usually means your anon key is invalid or expired');
  } on PostgrestException catch (e) {
    // Handle database errors
    debugPrint('❌ Database Error: Code ${e.code} - ${e.message}');
    switch (e.code) {
      case 'PGRST301':
        debugPrint(
          '   → Connection failed. Check your internet and Supabase URL',
        );
        break;
      case 'PGRST116':
        debugPrint('   → Invalid request format');
        break;
      default:
        debugPrint('   → Unknown database error');
    }
  } on TimeoutException catch (e) {
    // Handle timeout errors
    debugPrint('❌ Timeout Error: ${e.message}');
    debugPrint('   → Connection took too long. Check your internet speed');
  } on SocketException catch (e) {
    // Handle network errors
    debugPrint('❌ Network Error: ${e.message}');
    debugPrint('   → No internet connection or Supabase is unreachable');
  } on FormatException catch (e) {
    // Handle format errors
    debugPrint('❌ Format Error: ${e.message}');
    debugPrint('   → Invalid URL or key format');
  } catch (e) {
    // Handle any other unexpected errors
    debugPrint('❌ Unexpected Error: $e');
    debugPrint('   → Please check your Supabase configuration');
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
      home: LandingPage(),
    );
  }
}
