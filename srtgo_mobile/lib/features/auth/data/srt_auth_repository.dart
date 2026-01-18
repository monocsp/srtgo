import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../core/network/http_client.dart';

class SrtAuthRepository {
  final Dio _dio;

  SrtAuthRepository() : _dio = HttpClient().client;

  // Constants from srt.py
  static const String _loginUrl = "https://app.srail.or.kr:443/apb/selectListApb01080_n.do";
  static const String _mainUrl = "https://app.srail.or.kr:443/main/main.do";

  static final RegExp _emailRegex = RegExp(r"[^@]+@[^@]+\.[^@]+");
  static final RegExp _phoneRegex = RegExp(r"(\d{3})-(\d{3,4})-(\d{4})");

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    String loginType = "1"; // Default: Membership Number
    String processedUsername = username;

    // Logic from srt.py: Login Type Detection
    if (_emailRegex.hasMatch(username)) {
      loginType = "2"; // Email
    } else if (_phoneRegex.hasMatch(username)) {
      loginType = "3"; // Phone
      // Logic from srt.py: Remove hyphens for phone numbers
      processedUsername = username.replaceAll("-", "");
    }

    final formData = FormData.fromMap({
      "auto": "Y",
      "check": "Y",
      "page": "menu",
      "deviceKey": "-",
      "customerYn": "",
      "login_referer": _mainUrl,
      "srchDvCd": loginType,
      "srchDvNm": processedUsername,
      "hmpgPwdCphd": password,
    });

    try {
      final response = await _dio.post(
        _loginUrl,
        data: formData,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final data = response.data;
      
      // Handle Text Response (Dio might parse JSON automatically, but SRT sometimes returns HTML/Text on error)
      if (data is String) {
        if (data.contains("존재하지않는 회원입니다")) {
          throw Exception("존재하지 않는 회원입니다.");
        }
        if (data.contains("비밀번호 오류")) {
          throw Exception("비밀번호가 일치하지 않습니다.");
        }
        try {
          // Attempt to parse if it's a JSON string
           final json = jsonDecode(data);
           return _parseLoginSuccess(json);
        } catch (_) {
           throw Exception("서버 응답 오류: $data");
        }
      } else if (data is Map<String, dynamic>) {
        
        // Check for specific FATAL errors first
        final msg = data['MSG'] as String? ?? "";
        if (msg.contains("존재하지않는 회원") || msg.contains("비밀번호 오류")) {
           throw Exception(msg);
        }

        // [Fix] Check if we have valid user data (Success or Already Logged In)
        // The API returns "FAIL" if already logged in, but includes valid userMap.
        // It also returns "FAIL" with empty/null userMap if credentials are wrong.
        if (data.containsKey("userMap") && data["userMap"] != null) {
           final userMap = data["userMap"];
           if (userMap is Map && userMap["MB_CRD_NO"] != null) {
              return _parseLoginSuccess(data);
           }
        }
        
        // If no valid user data, AND it's a failure, then throw
        if (data['strResult'] == 'FAIL') {
             throw Exception(msg.isNotEmpty ? msg : "로그인 실패");
        }

        // Successful login (or already logged in) usually contains userMap
        if (data.containsKey("userMap")) {
          return _parseLoginSuccess(data);
        }
        
        if (data.containsKey("MSG")) {
           throw Exception(data["MSG"]); 
        }
        return _parseLoginSuccess(data);
      }

      throw Exception("알 수 없는 응답 형식");

    } catch (e) {
      throw Exception("로그인 실패: $e");
    }
  }

  Map<String, dynamic> _parseLoginSuccess(Map<String, dynamic> json) {
    if (json.containsKey("userMap")) {
      final userMap = json["userMap"];
      return {
        "membership_number": userMap["MB_CRD_NO"],
        "name": userMap["CUST_NM"],
        "phone": userMap["MBL_PHONE"],
      };
    }
    throw Exception("로그인 정보 파싱 실패");
  }
}
