import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/security/ktx_encryption.dart';

class KtxAuthRepository {
  final Dio _dio;

  KtxAuthRepository() : _dio = HttpClient().client;

  // Constants from ktx.py
  static const String _baseUrl = "https://smart.letskorail.com:443/classes/com.korail.mobile";
  static const String _loginUrl = "$_baseUrl.login.Login";
  static const String _codeUrl = "$_baseUrl.common.code.do";
  
  // Hardcoded values from ktx.py
  static const String _device = "AD";
  static const String _version = "240531001";
    static const String _staticKey = "korail1234567890"; // Only used in payload, not for encryption
  
    // KTX Specific User Agent from ktx.py
    static const String _userAgent = "Dalvik/2.1.0 (Linux; U; Android 14; SM-S912N Build/UP1A.231005.007)";
  
    static final RegExp _emailRegex = RegExp(r"[^@]+@[^@]+\.[^@]+");
    static final RegExp _phoneRegex = RegExp(r"(\d{3})-(\d{3,4})-(\d{4})");
  
    Future<Map<String, dynamic>> login({
      required String username,
      required String password,
    }) async {
      try {
        // 1. Fetch Encryption Key
        final keyData = await _fetchEncryptionKey();
        final String key = keyData['key'];
        final String idx = keyData['idx'];
  
        // 2. Encrypt Password
        final encryptedPassword = KtxEncryption.encryptPassword(
          password: password,
          keyString: key,
        );
  
        // 3. Prepare Login Payload
        String inputFlag = "2"; // Default: Membership No
        if (_emailRegex.hasMatch(username)) {
          inputFlag = "5";
        } else if (_phoneRegex.hasMatch(username)) {
          inputFlag = "4";
        }
  
        final formData = FormData.fromMap({
          "Device": _device,
          "Version": _version,
          "Key": _staticKey,
          "txtMemberNo": username,
          "txtPwd": encryptedPassword,
          "txtInputFlg": inputFlag,
          "idx": idx,
        });
  
        // 4. Send Login Request
        final response = await _dio.post(
          _loginUrl,
          data: formData,
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {
              "User-Agent": _userAgent,
            },
          ),
        );
  
        dynamic data = response.data;
        if (data is String) {
          try {
            data = jsonDecode(data);
          } catch (_) {}
        }
  
        if (data is Map<String, dynamic>) {
          if (data["strResult"] == "SUCC" && data.containsKey("strMbCrdNo")) {
            return {
              "membership_number": data["strMbCrdNo"],
              "name": data["strCustNm"],
              "email": data["strEmailAdr"],
              "phone": data["strCpNo"],
            };
          } else {
             String msg = data["h_msg_txt"] ?? data["h_msg_cd"] ?? "로그인 실패";
             throw Exception(msg);
          }
        }
        throw Exception("응답 형식 오류: $data");
  
      } catch (e) {
        throw Exception("KTX 로그인 오류: $e");
      }
    }
  
    Future<Map<String, dynamic>> _fetchEncryptionKey() async {
      final formData = FormData.fromMap({
        "code": "app.login.cphd",
      });
  
      final response = await _dio.post(
        _codeUrl,
        data: formData,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            "User-Agent": _userAgent,
          },
        ),
      );
      
      dynamic data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {}
      }
  
      if (data is Map<String, dynamic>) {
        if (data["strResult"] == "SUCC" && data.containsKey("app.login.cphd")) {
          final innerData = data["app.login.cphd"];
          return {
            "key": innerData["key"],
            "idx": innerData["idx"],
          };
        }
      }
      throw Exception("암호화 키 조회 실패");
    }
  }
  
