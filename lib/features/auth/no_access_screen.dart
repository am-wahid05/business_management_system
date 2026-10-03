import 'package:flutter/material.dart';

import '../../app/app_routes.dart';

class NoAccessScreen extends StatelessWidget {
  const NoAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Access restricted')),
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 56),
                const SizedBox(height: 16),
                Text('You do not have permission to open this area.', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(onPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.login), child: const Text('Return to Login')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}