import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/train_model.dart';

part 'cart_provider.g.dart';

@riverpod
class Cart extends _$Cart {
  @override
  List<Train> build() => [];

  void toggleTrain(Train train) {
    if (state.any((t) => t.id == train.id)) {
      state = state.where((t) => t.id != train.id).toList();
    } else {
      state = [...state, train];
    }
  }

  void removeTrain(String trainId) {
    state = state.where((t) => t.id != trainId).toList();
  }

  void clear() {
    state = [];
  }

  bool contains(Train train) {
    return state.any((t) => t.id == train.id);
  }
}
