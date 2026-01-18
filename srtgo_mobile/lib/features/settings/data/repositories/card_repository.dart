import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/credit_card_model.dart';

class CardRepository {
  final _storage = const FlutterSecureStorage();
  static const _key = 'user_credit_cards';

  Future<List<CreditCard>> getCards() async {
    final jsonStr = await _storage.read(key: _key);
    if (jsonStr == null) return [];
    
    final List<dynamic> list = jsonDecode(jsonStr);
    return list.map((e) => CreditCard.fromJson(e)).toList();
  }

  Future<void> addCard(CreditCard card) async {
    final cards = await getCards();
    // Overwrite if alias exists
    cards.removeWhere((c) => c.alias == card.alias);
    cards.add(card);
    
    await _saveCards(cards);
  }

  Future<void> removeCard(String alias) async {
    final cards = await getCards();
    cards.removeWhere((c) => c.alias == alias);
    await _saveCards(cards);
  }

  Future<void> _saveCards(List<CreditCard> cards) async {
    final jsonStr = jsonEncode(cards.map((e) => e.toJson()).toList());
    await _storage.write(key: _key, value: jsonStr);
  }
}
