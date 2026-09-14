import 'package:flutter/material.dart';
import 'package:raillog/src/pages/auth_page.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

class LoginRequiredView extends StatelessWidget {
  const LoginRequiredView({
    super.key,
    required this.message,
    required this.icon,
    this.onSignedIn,
  });

  final String message;
  final IconData icon;
  final VoidCallback? onSignedIn;

  Future<void> _openLogin(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(m3PageRoute(builder: (_) => const AuthPage()));
    if (!context.mounted || !SessionService.instance.isSignedIn) return;
    onSignedIn?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 16),
            Text(message),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openLogin(context),
              icon: const Icon(Icons.login),
              label: const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }
}
