import 'package:flutter/material.dart';

import '../../models/client_user.dart';

class TemporaryPage extends StatelessWidget {
  const TemporaryPage({super.key, required this.user, required this.spanish});

  final ClientUser user;
  final bool spanish;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircleAvatar(
                    radius: 42,
                    backgroundColor: Color(0xFFE8EDF2),
                    child: Icon(
                      Icons.restaurant_menu_rounded,
                      size: 38,
                      color: Color(0xFF71859B),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    spanish
                        ? '¡Hola, ${user.fullName}!'
                        : 'Hello, ${user.fullName}!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Live View',
                    style: const TextStyle(
                      fontSize: 17,
                      color: Color(0xFF68727E),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Chip(label: Text(user.role)),
                  const SizedBox(height: 12),
                  Text(
                    spanish
                        ? 'La operación del salón se implementará próximamente.'
                        : 'Room operations will be implemented soon.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF8A9097)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
