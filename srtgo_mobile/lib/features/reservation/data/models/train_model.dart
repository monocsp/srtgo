import '../../../../core/constants/stations.dart';

class Train {
  final String trainCode;    // 열차종류코드 (17: SRT, 00: KTX 등)

  final String trainName;    // 열차명 (SRT, KTX 등)
  final String trainNo;      // 열차번호
  final String depDate;      // 출발날짜 (YYYYMMDD)
  final String depTime;      // 출발시간 (HHMMSS)
  final String arrDate;      // 도착날짜
  final String arrTime;      // 도착시간
  final String depStation;   // 출발역명
  final String arrStation;   // 도착역명
  final String depStationCode;
  final String arrStationCode;
  final String depStationRunOrder;
  final String arrStationRunOrder;
  final String depStationConsOrder;
  final String arrStationConsOrder;
  
  final String generalSeatState; // 일반실 상태 텍스트
  final String specialSeatState; // 특실 상태 텍스트
  final int reserveWaitCode;     // 예약대기 코드 (9: 가능)

  String get id => "$trainCode-$trainNo-$depDate-$depTime";

  Train({
    required this.trainCode,
    required this.trainName,
    required this.trainNo,
    required this.depDate,
    required this.depTime,
    required this.arrDate,
    required this.arrTime,
    required this.depStation,
    required this.arrStation,
    required this.depStationCode,
    required this.arrStationCode,
    required this.depStationRunOrder,
    required this.arrStationRunOrder,
    required this.depStationConsOrder,
    required this.arrStationConsOrder,
    required this.generalSeatState,
    required this.specialSeatState,
    required this.reserveWaitCode,
  });

  bool get canReserveGeneral => generalSeatState.contains("예약가능");
  bool get canReserveSpecial => specialSeatState.contains("예약가능");
  bool get canReserveStandby => reserveWaitCode == 9;

  factory Train.fromJson(Map<String, dynamic> json) {
    // Helper to map code to name
    String getTrainName(String code) {
      const map = {
        "00": "KTX", "02": "무궁화", "03": "통근열차", "04": "누리로",
        "05": "전체", "07": "KTX-산천", "08": "ITX-새마을", 
        "09": "ITX-청춘", "10": "KTX-산천", "17": "SRT", "18": "ITX-마음"
      };
      return map[code] ?? "기타";
    }

    // Always use local mapping for station names to prevent encoding issues
    final depCode = json['dptRsStnCd'] ?? "";
    final arrCode = json['arvRsStnCd'] ?? "";
    
    final depName = AppStations.getSrtStationName(depCode);
    final arrName = AppStations.getSrtStationName(arrCode);

    return Train(
      trainCode: json['stlbTrnClsfCd'] ?? "",
      trainName: getTrainName(json['stlbTrnClsfCd'] ?? ""),
      trainNo: json['trnNo'] ?? "",
      depDate: json['dptDt'] ?? "",
      depTime: json['dptTm'] ?? "",
      arrDate: json['arvDt'] ?? "",
      arrTime: json['arvTm'] ?? "",
      depStation: depName, 
      arrStation: arrName,
      depStationCode: depCode,
      arrStationCode: arrCode,
      depStationRunOrder: json['dptStnRunOrdr'] ?? "",
      arrStationRunOrder: json['arvStnRunOrdr'] ?? "",
      depStationConsOrder: json['dptStnConsOrdr'] ?? "",
      arrStationConsOrder: json['arvStnConsOrdr'] ?? "",
      generalSeatState: json['gnrmRsvPsbStr'] ?? "",
      specialSeatState: json['sprmRsvPsbStr'] ?? "",
      reserveWaitCode: int.tryParse(json['rsvWaitPsbCd'] ?? "-1") ?? -1,
    );
  }
}
