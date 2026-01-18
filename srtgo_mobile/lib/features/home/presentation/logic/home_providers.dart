import 'package:flutter_riverpod/flutter_riverpod.dart';

// Controls the current tab index of the BottomNavigationBar in HomeScreen
final homeTabIndexProvider = StateProvider<int>((ref) => 0);
