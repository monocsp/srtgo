import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/dio_provider.dart';
import '../dtos/auth_response_dto.dart';

part 'auth_remote_data_source.g.dart';

@Riverpod(keepAlive: true)
AuthRemoteDataSource authRemoteDataSource(AuthRemoteDataSourceRef ref) {
  return AuthRemoteDataSource(ref.watch(dioProvider));
}

class AuthRemoteDataSource {
  final Dio _dio;

  AuthRemoteDataSource(this._dio);

  Future<AuthResponseDto> login({
    required String username,
    required String password,
  }) async {
    final emailRegex = RegExp(r"[^@]+@[^@]+\.[^@]+");
    final phoneRegex = RegExp(r"(\d{3})-(\d{3,4})-(\d{4})");

    String loginType = "1"; // Default: Membership Number
    if (emailRegex.hasMatch(username)) {
      loginType = "2";
    } else if (phoneRegex.hasMatch(username)) {
      loginType = "3";
      username = username.replaceAll("-", "");
    }

    final data = {
      "auto": "Y",
      "check": "Y",
      "page": "menu",
      "deviceKey": "-",
      "customerYn": "",
      "login_referer": ApiEndpoints.main,
      "srchDvCd": loginType,
      "srchDvNm": username,
      "hmpgPwdCphd": password,
    };

    try {
      final response = await _dio.post(
        ApiEndpoints.login,
        data: FormData.fromMap(data), // SRT API expects form-data
      );

      final json = response.data is Map<String, dynamic> 
          ? response.data 
          : throw Exception("Unexpected response format");

      // Check for specific FATAL errors first
      final msg = json['MSG'] as String? ?? "";
      if (msg.contains("존재하지않는 회원") || msg.contains("비밀번호 오류")) {
         throw Exception(msg);
      }

      // Check for valid user data (Success or Already Logged In)
      if (json.containsKey("userMap") && json["userMap"] != null) {
         final userMap = json["userMap"];
         if (userMap is Map && userMap["MB_CRD_NO"] != null) {
            return AuthResponseDto.fromJson(json);
         }
      }

      // Check for SRT API logical failure
      if (json['strResult'] == 'FAIL') {
        throw Exception(msg.isNotEmpty ? msg : "로그인에 실패했습니다.");
      }
          
      return AuthResponseDto.fromJson(json);
    } catch (e) {
      rethrow;
    }
  }
}
