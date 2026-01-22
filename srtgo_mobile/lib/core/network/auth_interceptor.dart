import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import '../../core/storage/credential_storage.dart';
import '../constants/api_endpoints.dart';
import 'session_exception.dart';

class AuthInterceptor extends QueuedInterceptor {
  final Dio _dio;
  final CookieJar _cookieJar;
  final CredentialStorage _storage = CredentialStorage();

  AuthInterceptor(this._dio, this._cookieJar);

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // Skip login requests from this check to avoid recursion issues
    if (response.requestOptions.path.contains(ApiEndpoints.login)) {
      return handler.next(response);
    }

    final dataStr = response.data.toString();
    if (dataStr.contains("로그인 후 사용")) {
      final error = DioException(
        requestOptions: response.requestOptions,
        error: SessionExpiredException("로그인이 필요합니다."),
        type: DioExceptionType.unknown,
        response: response,
      );
      // Trigger onError manually to start retry flow
      // Note: We use rejection which will flow to onError
      return handler.reject(error);
    }
    return handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Check if it's a session error
    bool isSessionError = err.error is SessionExpiredException ||
        err.message?.contains("로그인") == true ||
        (err.response?.data.toString().contains("로그인 후 사용") ?? false);

    // Skip if it's already a login request that failed
    if (err.requestOptions.path.contains(ApiEndpoints.login)) {
      return handler.next(err);
    }

    if (isSessionError) {
      print("[AuthInterceptor] 세션 만료 감지. 자동 재로그인 시도...");

      try {
        // 1. Get stored credentials based on last usage
        String railType = await _storage.getLastRailType() ?? "SRT";
        Map<String, String>? cred = await _storage.getCredentials(railType);
        
        // If not found, try the other one? 
        if (cred == null) {
           railType = railType == "SRT" ? "KTX" : "SRT";
           cred = await _storage.getCredentials(railType);
        }

        if (cred == null) {
          throw Exception("저장된 계정 정보 없음");
        }

        final username = cred['username'];
        final password = cred['password'];

        if (username == null || password == null) throw Exception("계정 정보 누락");

        // Prepare Login Data
        final emailRegex = RegExp(r"[^@]+@[^@]+\.[^@]+");
        final phoneRegex = RegExp(r"(\d{3})-(\d{3,4})-(\d{4})");

        String loginType = "1";
        String processedUsername = username;
        if (emailRegex.hasMatch(username)) {
          loginType = "2";
        } else if (phoneRegex.hasMatch(username)) {
          loginType = "3";
          processedUsername = username.replaceAll("-", "");
        }

        final data = {
          "auto": "Y",
          "check": "Y",
          "page": "menu",
          "deviceKey": "-",
          "customerYn": "",
          "login_referer": ApiEndpoints.main,
          "srchDvCd": loginType,
          "srchDvNm": processedUsername,
          "hmpgPwdCphd": password,
        };

        // Create a temporary Dio to perform login without triggering this interceptor lock
        // CRITICAL: Must use the SAME CookieJar to persist the new session!
        final tokenDio = Dio(BaseOptions(
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 10),
           headers: {
             'User-Agent': 'Mozilla/5.0 (Linux; Android 15; SM-S912N Build/AP3A.240905.015.A2; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/136.0.7103.125 Mobile Safari/537.36SRT-APP-Android V.2.0.38',
             'Accept': 'application/json',
           }
        ));
        
        tokenDio.interceptors.add(CookieManager(_cookieJar)); // Share CookieJar
        // DO NOT add AuthInterceptor to tokenDio

        final loginResponse = await tokenDio.post(
          ApiEndpoints.login,
          data: FormData.fromMap(data),
        );
        
        // Verify Login Success
        final json = loginResponse.data;
        if (json is Map<String, dynamic>) {
           if (json['strResult'] == 'FAIL') {
              throw Exception(json['MSG'] ?? "로그인 실패");
           }
           if (json['MSG']?.toString().contains("비밀번호 오류") == true) {
              throw Exception("비밀번호 오류");
           }
        }

        print("[AuthInterceptor] 재로그인 성공. 원래 요청 재시도...");

        // Retry the original request using the main _dio
        // We use _dio.fetch which will trigger interceptors again, checking the new session.
        // Since session is refreshed, it should pass onResponse check.
        final retryResponse = await _dio.fetch(err.requestOptions);
        return handler.resolve(retryResponse);

      } catch (e) {
        print("[AuthInterceptor] 재로그인 실패: $e");
        // If re-login fails, reject the original error so UI handles it (Logout)
        // We wrap the error or pass original to indicating session is definitely dead
        return handler.next(err);
      }
    }

    return handler.next(err);
  }
}
