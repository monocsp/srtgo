import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';
import 'auth_interceptor.dart'; // Added Import

const String kUserAgent =
    "Mozilla/5.0 (Linux; Android 15; SM-S912N Build/AP3A.240905.015.A2; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/136.0.7103.125 Mobile Safari/537.36SRT-APP-Android V.2.0.38";

class HttpClient {
  static final HttpClient _instance = HttpClient._internal();
  late Dio _dio;
  late PersistCookieJar _cookieJar;

  factory HttpClient() {
    return _instance;
  }

  HttpClient._internal();

  Future<void> init() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    _cookieJar = PersistCookieJar(
      storage: FileStorage("${appDocDir.path}/.cookies/"),
    );

    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'User-Agent': kUserAgent,
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(CookieManager(_cookieJar));
    
    // Use AuthInterceptor for global session handling
    _dio.interceptors.add(AuthInterceptor(_dio, _cookieJar));
    
    // Debug Logging
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => print('Network: $obj'),
    ));
  }

  Dio get client => _dio;
  PersistCookieJar get cookieJar => _cookieJar;
  
  Future<void> clearCookies() async {
    await _cookieJar.deleteAll();
  }
}
