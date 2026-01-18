import 'dart:convert';
import 'dart:typed_data' as dev;
import 'package:encrypt/encrypt.dart';

class KtxEncryption {
  /// Encrypts the password using the specific logic found in korail2.py
  /// 
  /// Logic:
  /// 1. Key = UTF-8 bytes of the [keyString]
  /// 2. IV = First 16 bytes of the Key
  /// 3. AES Mode = CBC, Padding = PKCS7
  /// 4. Result = Base64(Base64(EncryptedBytes)) -> Double Base64!
  static String encryptPassword({required String password, required String keyString}) {
    final keyBytes = utf8.encode(keyString);
    final ivBytes = keyBytes.sublist(0, 16);

    final key = Key(dev.Uint8List.fromList(keyBytes));
    final iv = IV(dev.Uint8List.fromList(ivBytes));

    final encrypter = Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));

    final encrypted = encrypter.encrypt(password, iv: iv);
    
    // python: base64.b64encode(base64.b64encode(cipher.encrypt(padded_data))).decode("utf-8")
    // encrypt package's .base64 returns the first level of base64 encoding.
    // So we need to encode it one more time.
    
    final firstBase64 = encrypted.base64;
    final secondBase64 = base64.encode(utf8.encode(firstBase64));

    return secondBase64;
  }
}

