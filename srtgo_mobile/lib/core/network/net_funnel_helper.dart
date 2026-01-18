import 'dart:async';
import 'package:dio/dio.dart';
import 'http_client.dart';

class NetFunnelHelper {
  final Dio _dio = HttpClient().client;
  
  static const String _url = "https://nf.letskorail.com/ts.wseq";
  
  String? _cachedKey;
  DateTime? _lastFetchTime;
  final Duration _cacheTtl = const Duration(seconds: 45);

  Future<String> getNetFunnelKey() async {
    final now = DateTime.now();
    
    if (_cachedKey != null && _lastFetchTime != null && now.difference(_lastFetchTime!) < _cacheTtl) {
      return _cachedKey!;
    }

    try {
      var response = await _makeRequest("5101");
      var status = response['status'];
      var key = response['key'];
      var ip = response['ip'];

      while (status == "201") {
        await Future.delayed(const Duration(seconds: 1));
        response = await _makeRequest("5002", key: key, ip: ip);
        status = response['status'];
      }

      await _makeRequest("5004", key: key, ip: ip);

      _cachedKey = key;
      _lastFetchTime = DateTime.now();
      return key!;
    } catch (e) {
      _cachedKey = null;
      throw Exception("NetFunnel 토큰 발급 실패: $e");
    }
  }

  Future<Map<String, String?>> _makeRequest(String opcode, {String? key, String? ip}) async {
    final targetUrl = ip != null ? "https://$ip/ts.wseq" : _url;
    
    final params = {
      "opcode": opcode,
      "nfid": "0",
      "prefix": "NetFunnel.gRtype=$opcode;",
      "js": "true",
      "sid": "service_1",
      "aid": "act_10",
      DateTime.now().millisecondsSinceEpoch.toString(): "",
    };

    if (key != null) params["key"] = key;
    if (opcode == "5002") params["ttl"] = "1";

    final response = await _dio.get(
      targetUrl,
      queryParameters: params,
      options: Options(
        headers: {
          'Host': 'nf.letskorail.com',
          'Referer': 'https://app.srail.or.kr/',
        },
      ),
    );

    return _parseResponse(response.data.toString());
  }

  Map<String, String?> _parseResponse(String body) {
    final regExp = RegExp(r"NetFunnel\.gControl\.result='([^']+)'");
    final match = regExp.firstMatch(body);
    if (match == null) throw Exception("NetFunnel 응답 파싱 실패");

    final parts = match.group(1)!.split(':');
    final status = parts[1];
    final paramsStr = parts[2];
    
    final params = <String, String?>{'status': status};
    for (var p in paramsStr.split('&')) {
      final kv = p.split('=');
      if (kv.length == 2) params[kv[0]] = kv[1];
    }
    return params;
  }
}
