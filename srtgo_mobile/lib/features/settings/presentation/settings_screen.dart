import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/login_screen.dart';
import '../../auth/presentation/logic/user_provider.dart';
import 'card_management_screen.dart';

import '../../../../core/network/http_client.dart';
import '../../../../core/storage/credential_storage.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: ListView(
        children: [
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.credit_card),
            title: const Text("카드 관리"),
            subtitle: const Text("결제에 사용할 카드를 등록/삭제합니다."),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CardManagementScreen(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("로그아웃", style: TextStyle(color: Colors.red)),
            onTap: () async {
              final railType = ref.read(userProvider).currentRailType;

              // 1. Clear Cookies
              await HttpClient().clearCookies();

              // 2. Clear Credentials for current rail type
              await CredentialStorage().clearCredentials(railType);

              // 3. Update State
              ref.read(userProvider.notifier).logoutCurrent();

              // 4. Navigate
              if (context.mounted) {
                // If other account is still logged in, maybe switch?
                // Or just go to LoginScreen for now to be simple.
                // The LoginScreen will show tabs.
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
