import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/srt_auth_repository.dart';
import '../data/ktx_auth_repository.dart';
import '../../home/presentation/home_screen.dart';
import '../../../../core/storage/credential_storage.dart';
import 'logic/user_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final String? initialRailType; // "SRT" or "KTX"
  final String? initialId;
  final String? errorMessage;
  const LoginScreen({super.key, this.initialRailType, this.initialId, this.errorMessage});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // UI State
  late bool _isKtxSelected;
  bool _isLoading = false;
  
  // Controllers
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final SrtAuthRepository _srtAuthRepository = SrtAuthRepository();
  final KtxAuthRepository _ktxAuthRepository = KtxAuthRepository();
  final CredentialStorage _credentialStorage = CredentialStorage();

  @override
  void initState() {
    super.initState();
    // Initialize tab based on passed argument
    if (widget.initialRailType == "KTX") {
      _isKtxSelected = true;
    } else if (widget.initialRailType == "SRT") {
      _isKtxSelected = false;
    } else {
      _isKtxSelected = false; // Default
    }
    
    if (widget.initialId != null) {
      _idController.text = widget.initialId!;
    }
    
    if (widget.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.errorMessage!),
            backgroundColor: Colors.red,
            duration: const Duration(days: 365), // Persistent
            action: SnackBarAction(
              label: '닫기',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final id = _idController.text.trim();
    final password = _passwordController.text;

    if (id.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('아이디와 비밀번호를 입력해주세요.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      Map<String, dynamic> userInfo;
      
      if (_isKtxSelected) {
        userInfo = await _ktxAuthRepository.login(
          username: id, 
          password: password
        );
      } else {
        userInfo = await _srtAuthRepository.login(
          username: id, 
          password: password
        );
      }
      
      await _credentialStorage.saveCredentials(
        railType: _isKtxSelected ? "KTX" : "SRT",
        username: id,
        password: password
      );

      ref.read(userProvider.notifier).setUser(
        userInfo['name'] ?? '사용자', 
        userInfo['membership_number'] ?? id, 
        _isKtxSelected ? 'KTX' : 'SRT'
      );
      
      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context); // Return to previous screen
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => HomeScreen(isKtx: _isKtxSelected)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll("Exception: ", "")),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = _isKtxSelected ? Colors.blue[800]! : Colors.purple[800]!;

    return Scaffold(
      appBar: AppBar(
        title: const Text("로그인"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        // Back button is automatically added if Navigator.canPop is true
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.train,
                  size: 80,
                  color: primaryColor,
                ),
                const SizedBox(height: 24),
                Text(
                  'SRTgo',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                ),
                const SizedBox(height: 48),

                // Rail Type Toggle (Locked if initialRailType is provided)
                IgnorePointer(
                  ignoring: widget.initialRailType != null,
                  child: Opacity(
                    opacity: widget.initialRailType != null ? 0.6 : 1.0,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('SRT'),
                          icon: Icon(Icons.directions_railway),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('KTX'),
                          icon: Icon(Icons.directions_subway),
                        ),
                      ],
                      selected: {_isKtxSelected},
                      onSelectionChanged: (Set<bool> newSelection) {
                        setState(() {
                          _isKtxSelected = newSelection.first;
                        });
                      },
                      style: ButtonStyle(
                        backgroundColor: MaterialStateProperty.resolveWith<Color?>(
                          (states) {
                            if (states.contains(MaterialState.selected)) {
                              return primaryColor.withOpacity(0.2);
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.initialRailType != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      "${_isKtxSelected ? 'KTX' : 'SRT'} 로그인 추가 중",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
                    ),
                  ),
                const SizedBox(height: 32),

                TextField(
                  controller: _idController,
                  decoration: InputDecoration(
                    labelText: '${_isKtxSelected ? "KTX" : "SRT"} 아이디 (멤버십번호/이메일/전화번호)',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: '비밀번호',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 32),

                FilledButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '로그인',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}