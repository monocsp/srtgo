import 'package:dio/dio.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/network/net_funnel_helper.dart';
import 'models/train_model.dart';

class SrtReservationRepository {
  final Dio _dio = HttpClient().client;
  final NetFunnelHelper _netFunnel = NetFunnelHelper();

  static const String _reserveUrl = "https://app.srail.or.kr:443/arc/selectListArc05013_n.do";

  // Seat Types
  static const int GENERAL = 1;
  static const int SPECIAL = 2;

  Future<Map<String, dynamic>> reserve({
    required Train train,
    required Map<String, int> passengers, // {"adult": 1, "child": 0, ...}
    bool isStandby = false,
    bool preferSpecialSeat = false,
  }) async {
    try {
      final netKey = await _netFunnel.getNetFunnelKey();

      final totalCount = passengers.values.fold(0, (sum, count) => sum + count);
      if (totalCount == 0) throw Exception("승객 수가 0명입니다.");

      final jobId = isStandby ? "1102" : "1101";
      final seatType = preferSpecialSeat ? "2" : "1"; // 1: General, 2: Special

      final formDataMap = {
        "jobId": jobId,
        "jrnyCnt": "1",
        "jrnyTpCd": "11",
        "jrnySqno1": "001",
        "stndFlg": "N",
        "trnGpCd1": "300",
        "trnGpCd": "109",
        "grpDv": "0",
        "rtnDv": "0",
        
        // Train Info
        "stlbTrnClsfCd1": train.trainCode,
        "dptRsStnCd1": train.depStationCode,
        "dptRsStnCdNm1": train.depStation,
        "arvRsStnCd1": train.arrStationCode,
        "arvRsStnCdNm1": train.arrStation,
        "dptDt1": train.depDate,
        "dptTm1": train.depTime,
        "arvTm1": train.arrTime,
        "trnNo1": train.trainNo.padLeft(5, '0'),
        "runDt1": train.depDate,
        "dptStnConsOrdr1": train.depStationConsOrder,
        "arvStnConsOrdr1": train.arrStationConsOrder,
        "dptStnRunOrdr1": train.depStationRunOrder,
        "arvStnRunOrdr1": train.arrStationRunOrder,
        
        "mblPhone": "", // Optional, maybe needed for standby
        "netfunnelKey": netKey,
        
        if (!isStandby) "reserveType": "11",

        // Passenger Info Headers
        "totPrnb": totalCount.toString(),
        "psgGridcnt": totalCount.toString(),
        "locSeatAttCd1": "000",
        "rqSeatAttCd1": "015",
        "dirSeatAttCd1": "009",
        "smkSeatAttCd1": "000",
        "etcSeatAttCd1": "000",
        "psrmClCd1": seatType,
      };

      // Flatten Passenger Counts
      // psgTpCd: 1=Adult, 2=Dis1~3, 3=Dis4~6, 4=Senior, 5=Child
      int index = 1;
      void addPassenger(String typeCode, int count) {
        if (count > 0) {
          formDataMap["psgTpCd$index"] = typeCode;
          formDataMap["psgInfoPerPrnb$index"] = count.toString();
          index++;
        }
      }

      addPassenger("1", passengers['adult'] ?? 0);
      addPassenger("5", passengers['child'] ?? 0);
      addPassenger("4", passengers['senior'] ?? 0);
      // Add others if needed

      final formData = FormData.fromMap(formDataMap);

      final response = await _dio.post(
        _reserveUrl,
        data: formData,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final json = response.data;
      if (json is Map<String, dynamic>) {
         if (json.containsKey('reservListMap') && json['reservListMap'] is List && json['reservListMap'].isNotEmpty) {
           return json['reservListMap'][0];
         }
         
         if (json.containsKey('MSG')) {
           throw Exception(json['MSG']);
         }
      }
      
      throw Exception("예약 결과 파싱 실패: ${response.data}");

    } catch (e) {
      throw Exception("예약 요청 실패: $e");
    }
  }

  Future<void> payWithCard({
    required Map<String, dynamic> reservationResult, // Result from reserve()
    required String membershipNumber, // Required to fix 500 Error
    required String cardNumber,
    required String cardPassword, // 2 digits
    required String cardExpiry, // YYMM
    required String cardAuthValue, // Birthday or Business No
    bool isCorporate = false, // Not used much, usually determined by auth value length
  }) async {
    const String paymentUrl = "https://app.srail.or.kr:443/ata/selectListAta09036_n.do";

    try {
      // Extract necessary info from reservation result
      final pnrNo = reservationResult['pnrNo'];
      final totalCost = reservationResult['rcvdAmt']; // Total cost

      // Determining Card Type: J (Personal, 6 digits) / S (Corporate, 10 digits)
      final cardType = cardAuthValue.length == 10 ? "S" : "J";

      final formData = FormData.fromMap({
        "stlDmnDt": DateTime.now().toString().replaceAll("-", "").substring(0, 8),
        "mbCrdNo": membershipNumber, // Use passed membership number
        "stlMnsSqno1": "1",
        "ststlGridcnt": "1",
        "totNewStlAmt": totalCost,
        "athnDvCd1": cardType,
        "vanPwd1": cardPassword,
        "crdVlidTrm1": cardExpiry,
        "stlMnsCd1": "02", // Credit Card
        "rsvChgTno": "0",
        "chgMcs": "0",
        "ismtMnthNum1": "0", // Installment: 0 (Lump sum)
        "ctlDvCd": "3102",
        "cgPsId": "korail",
        "pnrNo": pnrNo,
        "totPrnb": reservationResult['tkSpecNum'] ?? reservationResult['seatNum'] ?? "1",
        "mnsStlAmt1": totalCost,
        "crdInpWayCd1": "@",
        "athnVal1": cardAuthValue,
        "stlCrCrdNo1": cardNumber,
        "jrnyCnt": "1",
        "strJobId": "3102",
        "inrecmnsGridcnt": "1",
        "dptTm": reservationResult['dptTm'] ?? "",
        "arvTm": reservationResult['arvTm'] ?? "",
        "dptStnConsOrdr2": "000000",
        "arvStnConsOrdr2": "000000",
        "trnGpCd": "300",
        "pageNo": "-",
        "rowCnt": "-",
        "pageUrl": "",
      });

      final response = await _dio.post(
        paymentUrl,
        data: formData,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final json = response.data;
      if (json is Map<String, dynamic>) {
        // Check outDataSets > dsOutput0 > [0] > strResult == SUCC
        if (json.containsKey('outDataSets') && json['outDataSets']['dsOutput0'] != null) {
           final output = json['outDataSets']['dsOutput0'];
           if (output is List && output.isNotEmpty) {
             if (output[0]['strResult'] == 'FAIL') {
               throw Exception(output[0]['msgTxt'] ?? "결제 실패");
             }
             return; // Success
           }
        }
        
        if (json['strResult'] == 'FAIL') {
           throw Exception(json['MSG'] ?? "결제 오류");
        }
      }

    } catch (e) {
      throw Exception("결제 요청 실패: $e");
    }
  }
}