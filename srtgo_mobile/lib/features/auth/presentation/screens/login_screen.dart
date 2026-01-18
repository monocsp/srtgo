import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/auth_repository_impl.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _idController = TextEditingController();
  final _pwController = TextEditingController();
  
  final ValueNotifier<bool> _isLoading = ValueNotifier(false);
  final ValueNotifier<String?> _error = ValueNotifier(null);

  @override
  void dispose() {
    _idController.dispose();
    _pwController.dispose();
    _isLoading.dispose();
    _error.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_idController.text.isEmpty || _pwController.text.isEmpty) {
      _error.value = "아이디와 비밀번호를 입력해주세요.";
      return;
    }

    _isLoading.value = true;
    _error.value = null;

    try {
      final repository = ref.read(authRepositoryProvider);
      final user = await repository.login(
        _idController.text,
        _pwController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("로그인 성공: ${user.name}님 환영합니다.")),
        );
        // Navigate to next screen (Home/Search)
        // Navigator.of(context).pushReplacement(...)
      }
    } catch (e) {
      if (mounted) {
        _error.value = e.toString().replaceAll("Exception: ", "");
      }
    } finally {
      if (mounted) {
        _isLoading.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("SRTGo Login")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _idController,
              decoration: const InputDecoration(
                labelText: "아이디 (멤버십번호/이메일/전화번호)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pwController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "비밀번호",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ValueListenableBuilder<String?>(
              valueListenable: _error,
              builder: (context, error, child) {
                if (error == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    error,
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _isLoading,
              builder: (context, isLoading, child) {
                if (isLoading) {
                  return const CircularProgressIndicator();
                }
                return SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _handleLogin,
                    child: const Text("로그인"),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
