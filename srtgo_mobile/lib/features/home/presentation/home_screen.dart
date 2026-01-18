import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../reservation/presentation/reservation_screen.dart';
import '../../tickets/presentation/tickets_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import 'logic/home_providers.dart';
import '../../auth/presentation/logic/user_provider.dart';
import '../../auth/presentation/login_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final bool isKtx;
  const HomeScreen({super.key, required this.isKtx});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    // Initialize screens based on initial rail type from constructor?
    // Actually, screens should react to provider state change.
    // But for now, let's just stick to the simple structure.
    _screens = [
      _buildReservationScreen(), // Dynamic builder
      _buildTicketsScreen(),     // Dynamic builder
      const SettingsScreen(),
    ];
  }

  // Wrapper to inject current rail type from provider
  Widget _buildReservationScreen() {
    return Consumer(
      builder: (context, ref, _) {
        final multiUser = ref.watch(userProvider);
        final isKtx = multiUser.currentRailType == "KTX";
        return ReservationScreen(isKtx: isKtx);
      },
    );
  }

  Widget _buildTicketsScreen() {
    return Consumer(
      builder: (context, ref, _) {
        final multiUser = ref.watch(userProvider);
        final isKtx = multiUser.currentRailType == "KTX";
        return isKtx 
            ? const Center(child: Text("KTX 내역 확인은 준비중입니다."))
            : const TicketsScreen();
      },
    );
  }

  void _onItemTapped(int index) {
    ref.read(homeTabIndexProvider.notifier).state = index;
  }

  void _handleSwitchRailType(String type) {
    ref.read(userProvider.notifier).switchRailType(type);
  }

  void _handleAddAccount(String type) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => LoginScreen(initialRailType: type)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(homeTabIndexProvider);
    final multiUser = ref.watch(userProvider);
    final currentUser = multiUser.currentUser;
    final currentType = multiUser.currentRailType;

    return Scaffold(
      appBar: AppBar(
        title: Text('SRTgo - $currentType'),
        elevation: 0,
        actions: [
          if (currentUser != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == "SWITCH_SRT") _handleSwitchRailType("SRT");
                if (value == "SWITCH_KTX") _handleSwitchRailType("KTX");
                if (value == "ADD_SRT") _handleAddAccount("SRT");
                if (value == "ADD_KTX") _handleAddAccount("KTX");
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "${currentUser.name}님",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 16),
                        ],
                      ),
                      Text(
                        "${currentType} (${currentUser.membershipNumber})",
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
              itemBuilder: (context) {
                List<PopupMenuEntry<String>> items = [];
                
                // Switch Options
                if (currentType == "KTX" && multiUser.srtUser != null) {
                  items.add(const PopupMenuItem(
                    value: "SWITCH_SRT",
                    child: Text("SRT로 전환"),
                  ));
                }
                if (currentType == "SRT" && multiUser.ktxUser != null) {
                  items.add(const PopupMenuItem(
                    value: "SWITCH_KTX",
                    child: Text("KTX로 전환"),
                  ));
                }

                // Add Account Option
                if (currentType == "SRT" && multiUser.ktxUser == null) {
                  items.add(const PopupMenuItem(
                    value: "ADD_KTX",
                    child: Text("KTX 로그인 추가"),
                  ));
                }
                if (currentType == "KTX" && multiUser.srtUser == null) {
                  items.add(const PopupMenuItem(
                    value: "ADD_SRT",
                    child: Text("SRT 로그인 추가"),
                  ));
                }

                return items;
              },
            )
        ],
      ),
      body: IndexedStack(
        index: selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number),
            label: '예매',
          ),
          NavigationDestination(
            icon: Icon(Icons.airplane_ticket_outlined),
            selectedIcon: Icon(Icons.airplane_ticket),
            label: '확인/취소',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
