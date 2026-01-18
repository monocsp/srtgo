import 'package:dio/dio.dart';
import 'package:srtgo_mobile/features/reservation/data/models/train_model.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/network/net_funnel_helper.dart';
import '../../../../core/constants/stations.dart';

class SrtTrainRepository {
  final Dio _dio = HttpClient().client;
  final NetFunnelHelper _netFunnel = NetFunnelHelper();

  static const String _searchUrl =
      "https://app.srail.or.kr:443/ara/selectListAra10007_n.do";

  Future<List<Train>> searchTrains({
    required String depStation,
    required String arrStation,
    required String date, // YYYYMMDD
    required String time, // HHMMSS
  }) async {
    try {
      // 1. Get NetFunnel Key
      final netKey = await _netFunnel.getNetFunnelKey();

      // 2. Prepare Data
      final depCode = AppStations.getSrtStationCode(depStation);
      final arrCode = AppStations.getSrtStationCode(arrStation);

      final formData = FormData.fromMap({
        "chtnDvCd": "1",
        "dptDt": date,
        "dptTm": time,
        "dptDt1": date,
        "dptTm1": "${time.substring(0, 2)}0000",
        "dptRsStnCd": depCode,
        "arvRsStnCd": arrCode,
        "stlbTrnClsfCd": "05",
        "trnGpCd": 109,
        "trnNo": "",
        "psgNum": "1", // Hardcoded for now, need to pass total count
        "seatAttCd": "015",
        "arriveTime": "N",
        "dlayTnumAplFlg": "Y",
        "netfunnelKey": netKey,
      });

      // 3. Request
      final response = await _dio.post(
        _searchUrl,
        data: formData,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final json = response.data;

            if (json is Map<String, dynamic>) {

              if (json.containsKey('outDataSets') && json['outDataSets']['dsOutput1'] != null) {

                final list = json['outDataSets']['dsOutput1'] as List;

                // Python srt.py filters only "17" (SRT) trains. 

                // Other trains (like KTX "00", "07") appearing in SRT app search might cause booking errors.

                return list

                    .where((e) => e['stlbTrnClsfCd'] == '17')

                    .map((e) => Train.fromJson(e))

                    .toList();

              }

              if (json.containsKey('MSG')) {

                throw Exception(json['MSG']);

              }

            }

      throw Exception("Unexpected response format");
    } catch (e) {
      throw Exception("열차 조회 실패: $e");
    }
  }
}
