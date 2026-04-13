import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/providers/providers.dart';
import 'presentation/screens/attendance_kiosk_screen.dart';
import 'presentation/screens/attendance_logs_screen.dart';
import 'presentation/screens/review_queue_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/screens/student_enrollment_screen.dart';
import 'presentation/screens/student_management_screen.dart';

class FaceAttendanceApp extends ConsumerStatefulWidget {
  const FaceAttendanceApp({super.key});

  @override
  ConsumerState<FaceAttendanceApp> createState() => _FaceAttendanceAppState();
}

class _FaceAttendanceAppState extends ConsumerState<FaceAttendanceApp> {
  int _selectedIndex = 0;

  static const _screens = [
    StudentEnrollmentScreen(),
    AttendanceKioskScreen(),
    StudentManagementScreen(),
    AttendanceLogsScreen(),
    ReviewQueueScreen(),
    SettingsScreen(),
  ];

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.person_add_alt_1), label: 'Enroll'),
    NavigationDestination(icon: Icon(Icons.videocam), label: 'Kiosk'),
    NavigationDestination(icon: Icon(Icons.people), label: 'Students'),
    NavigationDestination(icon: Icon(Icons.history), label: 'Logs'),
    NavigationDestination(icon: Icon(Icons.fact_check), label: 'Review'),
    NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(appBootstrapProvider);
    return MaterialApp(
      title: 'Face Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan, brightness: Brightness.dark),
      ),
      home: bootstrap.when(
        data: (_) => Scaffold(
          body: _screens[_selectedIndex],
          bottomNavigationBar: NavigationBar(
            destinations: _destinations,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) => setState(() => _selectedIndex = index),
          ),
        ),
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Backend auth bootstrap failed: $error'),
            ),
          ),
        ),
      ),
    );
  }
}
