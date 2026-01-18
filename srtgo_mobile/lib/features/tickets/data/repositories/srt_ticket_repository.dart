import 'package:dio/dio.dart';
import '../../../../core/network/http_client.dart';
import '../models/ticket_model.dart';

class SrtTicketRepository {
  final Dio _dio = HttpClient().client;
  static const String _url = "https://app.srail.or.kr:443/atc/selectListAtc14016_n.do";
  static const String _cancelUrl = "https://app.srail.or.kr:443/ard/selectListArd02045_n.do";
  static const String _paymentUrl = "https://app.srail.or.kr:443/ata/selectListAta09036_n.do";

  Future<List<Ticket>> fetchTickets() async {
    try {
      final formData = FormData.fromMap({
        "pageNo": "0",
      });

      final response = await _dio.post(
        _url,
        data: formData,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final json = response.data;
      // Debug Log
      print("[DEBUG] Tickets API Response: $json");

      if (json is Map<String, dynamic>) {
        if (json.containsKey("MSG")) {
           // check msg
        }

        final trainList = json['trainListMap'] as List?;
        final payList = json['payListMap'] as List?;

        if (trainList == null || payList == null || trainList.isEmpty) {
          return [];
        }

        List<Ticket> tickets = [];
        for (int i = 0; i < trainList.length; i++) {
          if (i < payList.length) {
             tickets.add(Ticket.fromSrtJson(trainList[i], payList[i]));
          }
        }
        return tickets;
      }

      return [];

    } catch (e) {
      throw Exception("예약 내역 조회 실패: $e");
    }
  }

  Future<void> cancelTicket(String pnrNo) async {
    try {
      final formData = FormData.fromMap({
        "pnrNo": pnrNo,
        "jrnyCnt": "1",
        "rsvChgTno": "0",
      });

      final response = await _dio.post(
        _cancelUrl,
        data: formData,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final json = response.data;
      if (json is Map<String, dynamic>) {
        if (json.containsKey("MSG") && (json['strResult'] == 'FAIL')) {
           throw Exception(json['MSG']); 
        }
      }
    } catch (e) {
      throw Exception("예약 취소 실패: $e");
    }
  }

  Future<void> payTicket({
    required Ticket ticket,
    required String cardNumber,
    required String cardPassword, // 2 digits
    required String cardExpiry, // YYMM
    required String cardAuthValue, // Birthday or Business No
    required String mbCrdNo, // Required to fix 500/Input Errors
  }) async {
    try {
      final cardType = cardAuthValue.length == 10 ? "S" : "J";

      final formData = FormData.fromMap({
        "stlDmnDt": DateTime.now().toString().replaceAll("-", "").substring(0, 8),
        "mbCrdNo": mbCrdNo,
        "stlMnsSqno1": "1",
        "ststlGridcnt": "1",
        "totNewStlAmt": ticket.totalCost,
        "athnDvCd1": cardType,
        "vanPwd1": cardPassword,
        "crdVlidTrm1": cardExpiry,
        "stlMnsCd1": "02", // Credit Card
        "rsvChgTno": "0",
        "chgMcs": "0",
        "ismtMnthNum1": "0",
        "ctlDvCd": "3102",
        "cgPsId": "korail",
        "pnrNo": ticket.pnrNo,
        "totPrnb": ticket.seatCount,
        "mnsStlAmt1": ticket.totalCost,
        "crdInpWayCd1": "@",
        "athnVal1": cardAuthValue,
        "stlCrCrdNo1": cardNumber,
        "jrnyCnt": "1",
        "strJobId": "3102",
        "inrecmnsGridcnt": "1",
        "dptTm": ticket.depTime,
        "arvTm": ticket.arrTime,
        "dptStnConsOrdr2": "000000",
        "arvStnConsOrdr2": "000000",
        "trnGpCd": "300",
        "pageNo": "-",
        "rowCnt": "-",
        "pageUrl": "",
      });

      final response = await _dio.post(
        _paymentUrl,
        data: formData,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final json = response.data;
      if (json is Map<String, dynamic>) {
        if (json.containsKey('outDataSets') && json['outDataSets']['dsOutput0'] != null) {
           final output = json['outDataSets']['dsOutput0'];
           if (output is List && output.isNotEmpty) {
             if (output[0]['strResult'] == 'FAIL') {
               throw Exception(output[0]['msgTxt'] ?? "결제 실패");
             }
             return; 
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