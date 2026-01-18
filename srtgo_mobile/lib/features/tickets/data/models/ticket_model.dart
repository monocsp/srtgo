class Ticket {
  final String pnrNo;        // 예약번호
  final String trainCode;
  final String trainName;    // 열차명
  final String trainNo;      // 열차번호
  final String depStation;
  final String arrStation;
  final String depDate;      // YYYYMMDD
  final String depTime;      // HHMMSS
  final String arrTime;      // HHMMSS
  final String seatCount;    // 좌석수
  final String totalCost;    // 총 결제금액
  final bool isPaid;         // 결제 완료 여부
  final String paymentLimitDate; // 결제 기한 날짜
  final String paymentLimitTime; // 결제 기한 시간

  Ticket({
    required this.pnrNo,
    required this.trainCode,
    required this.trainName,
    required this.trainNo,
    required this.depStation,
    required this.arrStation,
    required this.depDate,
    required this.depTime,
    required this.arrTime,
    required this.seatCount,
    required this.totalCost,
    required this.isPaid,
    required this.paymentLimitDate,
    required this.paymentLimitTime,
  });

  factory Ticket.fromSrtJson(Map<String, dynamic> trainMap, Map<String, dynamic> payMap) {
    // Helper to map code to name
    String getTrainName(String code) {
      const map = {
        "00": "KTX", "02": "무궁화", "03": "통근열차", "04": "누리로",
        "05": "전체", "07": "KTX-산천", "08": "ITX-새마을", 
        "09": "ITX-청춘", "10": "KTX-산천", "17": "SRT", "18": "ITX-마음"
      };
      return map[code] ?? "기타";
    }

    final trainCode = payMap['stlbTrnClsfCd'] ?? "";
    
    return Ticket(
      pnrNo: (trainMap['pnrNo'] ?? "").toString(),
      trainCode: trainCode.toString(),
      trainName: getTrainName(trainCode.toString()),
      trainNo: (payMap['trnNo'] ?? "").toString(),
      depStation: _mapStationCodeToName((payMap['dptRsStnCd'] ?? "").toString()),
      arrStation: _mapStationCodeToName((payMap['arvRsStnCd'] ?? "").toString()),
      depDate: (payMap['dptDt'] ?? "").toString(),
      depTime: (payMap['dptTm'] ?? "").toString(),
      arrTime: (payMap['arvTm'] ?? "").toString(),
      seatCount: (trainMap['tkSpecNum'] ?? trainMap['seatNum'] ?? "0").toString(),
      totalCost: (trainMap['rcvdAmt'] ?? payMap['rcvdAmt'] ?? "0").toString(),
      isPaid: payMap['stlFlg'] == "Y",
      paymentLimitDate: (payMap['iseLmtDt'] ?? "").toString(),
      paymentLimitTime: (payMap['iseLmtTm'] ?? "").toString(),
    );
  }

  // Station Code Mapping (Inverse of AppStations)
  static String _mapStationCodeToName(String code) {
    const map = {
      "0551": "수서", "0552": "동탄", "0553": "평택지제", "0508": "경주",
      "0049": "곡성", "0514": "공주", "0036": "광주송정", "0050": "구례구",
      "0507": "김천(구미)", "0037": "나주", "0048": "남원", "0010": "대전",
      "0015": "동대구", "0059": "마산", "0041": "목포", "0017": "밀양",
      "0020": "부산", "0506": "서대구", "0051": "순천", "0053": "여수EXPO",
      "0139": "여천", "0297": "오송", "0509": "울산(통도사)", "0030": "익산",
      "0045": "전주", "0033": "정읍", "0056": "진영", "0063": "진주",
      "0057": "창원", "0512": "창원중앙", "0502": "천안아산", "0515": "포항"
    };
    return map[code] ?? code;
  }
}
