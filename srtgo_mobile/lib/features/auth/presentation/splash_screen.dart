import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/storage/credential_storage.dart';
import '../data/srt_auth_repository.dart';
import '../data/ktx_auth_repository.dart';
import '../../home/presentation/home_screen.dart';
import 'login_screen.dart';
import 'logic/user_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  final CredentialStorage _storage = CredentialStorage();
  final SrtAuthRepository _srtRepo = SrtAuthRepository();
  final KtxAuthRepository _ktxRepo = KtxAuthRepository();

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      String? targetType = await _storage.getLastRailType();
      Map<String, String>? creds;

      // 1. Try Last Used
      if (targetType != null) {
        creds = await _storage.getCredentials(targetType);
      }

      // 2. Fallback to other type if last used is not available
      if (creds == null) {
        if (targetType == "SRT") {
          targetType = "KTX";
        } else {
          targetType = "SRT";
        }
        creds = await _storage.getCredentials(targetType);
      }

      // 3. Login Attempt
      if (creds != null && targetType != null) {
        final username = creds['username']!;
        final password = creds['password']!;
        final isKtx = targetType == "KTX";

        Map<String, dynamic> userInfo;

        if (isKtx) {
          userInfo = await _ktxRepo.login(username: username, password: password);
        } else {
          userInfo = await _srtRepo.login(username: username, password: password);
        }

        // Update Global State
        ref.read(userProvider.notifier).setUser(
          userInfo['name'] ?? '사용자', 
          userInfo['membership_number'] ?? username, 
          isKtx ? 'KTX' : 'SRT'
        );

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => HomeScreen(isKtx: isKtx)),
          );
          return;
        }
      }
    } catch (e) {
      print("Auto login failed: $e");
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.train, size: 80, color: Colors.purple[800]),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text("자동 로그인 중...", style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}