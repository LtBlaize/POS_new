// lib/features/admin/admin_placeholder_screen.dart
//
// Phase 3 only. One reusable blank scaffold for every /admin/* route, just
// to prove the routing/gating works before Phase 4 builds the real
// AdminShell (topbar + sidebar) and Phases 5-12 build the real screens.
// Delete this file once Phase 4+ replace every route that uses it.
import 'package:flutter/material.dart';

class AdminPlaceholderScreen extends StatelessWidget {
  final String title;
  const AdminPlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1117),
        title: Text(title),
      ),
      body: Center(
        child: Text(
          '$title\n(placeholder — Phase 4+ builds this)',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ),
    );
  }
}