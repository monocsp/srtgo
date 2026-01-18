import 'dart:convert';

class CreditCard {
  final String alias;
  final String number;
  final String password;
  final String expiry; // YYMM
  final String birthday;

  CreditCard({
    required this.alias,
    required this.number,
    required this.password,
    required this.expiry,
    required this.birthday,
  });

  Map<String, dynamic> toJson() {
    return {
      'alias': alias,
      'number': number,
      'password': password,
      'expiry': expiry,
      'birthday': birthday,
    };
  }

  factory CreditCard.fromJson(Map<String, dynamic> json) {
    return CreditCard(
      alias: json['alias'] ?? '',
      number: json['number'] ?? '',
      password: json['password'] ?? '',
      expiry: json['expiry'] ?? '',
      birthday: json['birthday'] ?? '',
    );
  }
}
