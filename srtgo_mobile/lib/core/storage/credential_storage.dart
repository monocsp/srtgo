import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CredentialStorage {
  final _storage = const FlutterSecureStorage();
  
  static const _keySrtId = 'srt_id';
  static const _keySrtPw = 'srt_pw';
  static const _keyKtxId = 'ktx_id';
  static const _keyKtxPw = 'ktx_pw';
  static const _keyLastType = 'last_rail_type'; // "SRT" or "KTX"

  // Recent Route Keys
  static const _keyRecentRoutePrefix = 'recent_route_';

  Future<void> saveCredentials({
    required String railType,
    required String username,
    required String password,
  }) async {
    if (railType == "SRT") {
      await _storage.write(key: _keySrtId, value: username);
      await _storage.write(key: _keySrtPw, value: password);
    } else {
      await _storage.write(key: _keyKtxId, value: username);
      await _storage.write(key: _keyKtxPw, value: password);
    }
    // Also save password with specific ID key for reliable recovery
    await _storage.write(key: 'pw_$username', value: password);
    await _storage.write(key: _keyLastType, value: railType);
  }

  Future<Map<String, String>?> getCredentials(String railType) async {
    String? id, pw;
    if (railType == "SRT") {
      id = await _storage.read(key: _keySrtId);
      pw = await _storage.read(key: _keySrtPw);
    } else {
      id = await _storage.read(key: _keyKtxId);
      pw = await _storage.read(key: _keyKtxPw);
    }

    if (id != null && pw != null) {
      return {'username': id, 'password': pw};
    }
    return null;
  }

  // [New] Get specific password for an ID
  Future<Map<String, String>?> getCredentialsById(String username) async {
    final pw = await _storage.read(key: 'pw_$username');
    if (pw != null) {
      return {'username': username, 'password': pw};
    }
    return null;
  }
  
  Future<String?> getLastRailType() async {
    return await _storage.read(key: _keyLastType);
  }

  Future<void> clearCredentials(String railType) async {
    if (railType == "SRT") {
      await _storage.delete(key: _keySrtId);
      await _storage.delete(key: _keySrtPw);
    } else {
      await _storage.delete(key: _keyKtxId);
      await _storage.delete(key: _keyKtxPw);
    }
    // Don't delete last type immediately to allow fallback? 
    // Or check if other exists. For simplicity, keep last type or clear if matches.
  }

  // Recent Route Persistence
  Future<void> saveRecentRoute(String userId, String dep, String arr) async {
    final key = '$_keyRecentRoutePrefix$userId';
    final value = "$dep|$arr"; 
    await _storage.write(key: key, value: value);
  }

  Future<Map<String, String>?> getRecentRoute(String userId) async {
    final key = '$_keyRecentRoutePrefix$userId';
    final value = await _storage.read(key: key);
    if (value != null) {
      final parts = value.split('|');
      if (parts.length == 2) {
        return {'dep': parts[0], 'arr': parts[1]};
      }
    }
    return null;
  }
}
