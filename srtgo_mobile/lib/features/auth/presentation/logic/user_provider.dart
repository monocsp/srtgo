import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserState {
  final String name;
  final String membershipNumber;
  final String railType; // SRT or KTX

  UserState({
    required this.name,
    required this.membershipNumber,
    required this.railType,
  });
}

class MultiUserState {
  final UserState? srtUser;
  final UserState? ktxUser;
  final String currentRailType; // "SRT" or "KTX"

  MultiUserState({
    this.srtUser,
    this.ktxUser,
    required this.currentRailType,
  });

  UserState? get currentUser => currentRailType == "SRT" ? srtUser : ktxUser;

  MultiUserState copyWith({
    UserState? srtUser,
    UserState? ktxUser,
    String? currentRailType,
  }) {
    return MultiUserState(
      srtUser: srtUser ?? this.srtUser,
      ktxUser: ktxUser ?? this.ktxUser,
      currentRailType: currentRailType ?? this.currentRailType,
    );
  }
}

class UserNotifier extends StateNotifier<MultiUserState> {
  UserNotifier() : super(MultiUserState(currentRailType: "SRT"));

  void setUser(String name, String membershipNumber, String railType) {
    final newUser = UserState(
      name: name,
      membershipNumber: membershipNumber,
      railType: railType,
    );

    if (railType == "SRT") {
      state = state.copyWith(srtUser: newUser, currentRailType: "SRT");
    } else {
      state = state.copyWith(ktxUser: newUser, currentRailType: "KTX");
    }
  }
  
  void switchRailType(String type) {
    if (type == "SRT" || type == "KTX") {
      state = state.copyWith(currentRailType: type);
    }
  }

  void logoutCurrent() {
    if (state.currentRailType == "SRT") {
      state = MultiUserState(srtUser: null, ktxUser: state.ktxUser, currentRailType: state.ktxUser != null ? "KTX" : "SRT");
    } else {
      state = MultiUserState(srtUser: state.srtUser, ktxUser: null, currentRailType: state.srtUser != null ? "SRT" : "KTX");
    }
  }
  
  void logoutAll() {
    state = MultiUserState(currentRailType: "SRT");
  }
}

final userProvider = StateNotifierProvider<UserNotifier, MultiUserState>((ref) {
  return UserNotifier();
});
