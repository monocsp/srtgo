import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dio_provider.g.dart';

@Riverpod(keepAlive: true)
Dio dio(DioRef ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 15; SM-S912N Build/AP3A.240905.015.A2; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/136.0.7103.125 Mobile Safari/537.36SRT-APP-Android V.2.0.38',
        'Accept': 'application/json',
      },
    ),
  );

  // We need to initialize the cookie jar asynchronously
  // But this provider is synchronous.
  // For simplicity in this step, we will use a FutureProvider for the CookieJar
  // and attach it. Ideally, we just use a PersistCookieJar.
  
  // Since we can't await here easily without making Dio async (which makes usage harder),
  // we will attach the interceptor in a separate initialization step or use a standard CookieJar for now.
  // For production, we should use PersistCookieJar with path_provider.
  
  final cookieJar = CookieJar();
  dio.interceptors.add(CookieManager(cookieJar));

  return dio;
}
