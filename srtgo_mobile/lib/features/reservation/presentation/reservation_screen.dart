import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/stations.dart';
import '../../../../core/constants/seat_options.dart';
import '../../../../core/storage/credential_storage.dart';
import '../../auth/presentation/logic/user_provider.dart';
import '../../settings/data/models/credit_card_model.dart';
import '../../settings/data/repositories/card_repository.dart';
import '../data/srt_train_repository.dart';
import 'train_list_screen.dart';

class ReservationScreen extends ConsumerStatefulWidget {
  final bool isKtx;
  const ReservationScreen({super.key, required this.isKtx});

  @override
  ConsumerState<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends ConsumerState<ReservationScreen> {
  // Defaults
  late String _depStation;
  late String _arrStation;
  DateTime _selectedDate = DateTime.now();
  String _selectedTime = '120000'; // HHMMSS
  
  // Passenger Counts
  int _adultCount = 1;
  int _childCount = 0;
  int _seniorCount = 0;
  
  // Options
  bool _autoPayment = false; 
  CreditCard? _selectedCard; 
  SeatOption _seatOption = SeatOption.generalFirst; // Default
  
  // New Options (Ported from srtgo.py)
  bool _useSchedule = false; // Default: Immediate
  TimeOfDay _scheduledTime = TimeOfDay.now(); 
  int _durationMinutes = 0; // Default: Until success (0)
  
  bool _isLoading = false;
  final SrtTrainRepository _srtRepo = SrtTrainRepository();
  final CardRepository _cardRepo = CardRepository();
  final CredentialStorage _storage = CredentialStorage();
  
  // Generated dynamically
  List<String> _times = [];

  @override
  void initState() {
    super.initState();
    if (widget.isKtx) {
      _depStation = '서울';
      _arrStation = '부산';
    } else {
      _depStation = '수서';
      _arrStation = '동대구';
    }
    
    // Load saved route
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecentRoute();
    });

    _updateAvailableTimes();
    
    if (_isToday(_selectedDate)) {
      final now = DateTime.now();
      final nextHour = now.hour + 1;
      if (nextHour < 24) {
        _selectedTime = "${nextHour.toString().padLeft(2, '0')}0000";
      }
    }
  }

  Future<void> _loadRecentRoute() async {
    final multiUser = ref.read(userProvider);
    final currentUser = multiUser.currentUser;
    if (currentUser != null) {
      final route = await _storage.getRecentRoute(currentUser.membershipNumber);
      if (route != null) {
        setState(() {
          _depStation = route['dep']!;
          _arrStation = route['arr']!;
        });
      }
    }
  }

  Future<void> _saveRecentRoute() async {
    final multiUser = ref.read(userProvider);
    final currentUser = multiUser.currentUser;
    if (currentUser != null) {
      await _storage.saveRecentRoute(currentUser.membershipNumber, _depStation, _arrStation);
    }
  }

  void _swapStations() {
    setState(() {
      final temp = _depStation;
      _depStation = _arrStation;
      _arrStation = temp;
    });
  }

  void _updateAvailableTimes() {
    final now = DateTime.now();
    int startHour = 0;

    if (_isToday(_selectedDate)) {
      startHour = now.hour; 
    }

    _times = List.generate(24 - startHour, (index) {
      final hour = startHour + index;
      return "${hour.toString().padLeft(2, '0')}0000";
    });

    if (!_times.contains(_selectedTime)) {
      if (_times.isNotEmpty) {
        _selectedTime = _times.first;
      } else {
        _selectedTime = "230000"; 
      }
    }
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  Future<void> _handleAutoPaymentChange(bool value) async {
    if (!value) {
      setState(() {
        _autoPayment = false;
        _selectedCard = null;
      });
      return;
    }

    final cards = await _cardRepo.getCards();
    if (cards.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("등록된 카드가 없습니다. 설정 메뉴에서 카드를 등록해주세요.")),
        );
      }
      return;
    }

    if (!mounted) return;
    
    final picked = await showDialog<CreditCard>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text("결제 카드 선택"),
        children: cards.map((c) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, c),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text("${c.alias} (${c.number.substring(0, 4)}...)", style: const TextStyle(fontSize: 16)),
          ),
        )).toList(),
      ),
    );

    if (picked != null) {
      setState(() {
        _autoPayment = true;
        _selectedCard = picked;
      });
    }
  }

  Future<void> _searchTrains() async {
    if (widget.isKtx) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('KTX 조회는 아직 준비중입니다.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _saveRecentRoute(); 

      final dateStr = DateFormat('yyyyMMdd').format(_selectedDate);
      
      final trains = await _srtRepo.searchTrains(
        depStation: _depStation, 
        arrStation: _arrStation, 
        date: dateStr, 
        time: _selectedTime
      );

      if (!mounted) return;

      if (trains.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('조회 가능한 열차가 없습니다.')),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TrainListScreen(
              trains: trains, 
              title: "$_depStation → $_arrStation",
              passengerCounts: {
                "adult": _adultCount,
                "child": _childCount,
                "senior": _seniorCount,
              },
              paymentCard: _autoPayment ? _selectedCard : null,
              seatOption: _seatOption,
              // Pass new settings
              useSchedule: _useSchedule,
              scheduledTime: _useSchedule ? _scheduledTime : null,
              durationMinutes: _durationMinutes,
            )
          )
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll("Exception: ", "")),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showStationPicker(String title, Function(String) onSelected) {
    final stations = widget.isKtx ? AppStations.ktxStations : AppStations.srtStations;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: stations.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(stations[index]),
                        onTap: () {
                          onSelected(stations[index]);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showTimePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView.builder(
          itemCount: _times.length,
          itemBuilder: (context, index) {
            final timeStr = _times[index];
            final hour = timeStr.substring(0, 2);
            return ListTile(
              title: Text("$hour:00"),
              onTap: () {
                setState(() => _selectedTime = timeStr);
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStationTap(String label, String value, Function(String) onChanged) {
    return InkWell(
      onTap: () {
        _showStationPicker('$label역 선택', onChanged);
      },
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Text(
            value, 
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // 1. Station Selector
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildStationTap('출발', _depStation, (val) => setState(() => _depStation = val)),
                        ),
                        InkWell(
                          onTap: _swapStations,
                          borderRadius: BorderRadius.circular(25),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.swap_horiz, color: Colors.blue, size: 28),
                          ),
                        ),
                        Expanded(
                          child: _buildStationTap('도착', _arrStation, (val) => setState(() => _arrStation = val)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 2. Date & Time
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text("${_selectedDate.year}년 ${_selectedDate.month}월 ${_selectedDate.day}일"),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                    initialDate: _selectedDate,
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDate = picked;
                      _updateAvailableTimes();
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: Text("출발 시간: ${_selectedTime.substring(0, 2)}:00 이후"),
                onTap: _showTimePicker,
              ),
              
              const Divider(),

              // 3. Seat Option
              ListTile(
                leading: const Icon(Icons.chair),
                title: const Text("좌석 옵션"),
                trailing: DropdownButton<SeatOption>(
                  value: _seatOption,
                  underline: const SizedBox(),
                  onChanged: (SeatOption? newValue) {
                    if (newValue != null) setState(() => _seatOption = newValue);
                  },
                  items: SeatOption.values.map((SeatOption option) {
                    return DropdownMenuItem<SeatOption>(
                      value: option,
                      child: Text(option.label),
                    );
                  }).toList(),
                ),
              ),

              // 4. Passengers
              ExpansionTile(
                leading: const Icon(Icons.people),
                title: Text("승객: 성인 $_adultCount, 어린이 $_childCount ..."),
                children: [
                  _buildCounter("어른/청소년", _adultCount, (v) => setState(() => _adultCount = v)),
                  _buildCounter("어린이", _childCount, (v) => setState(() => _childCount = v)),
                  _buildCounter("경로", _seniorCount, (v) => setState(() => _seniorCount = v)),
                ],
              ),

              const Divider(),
              
              // 5. Auto Payment Option
              SwitchListTile(
                secondary: Icon(Icons.payment, color: _autoPayment ? Colors.blue : Colors.grey),
                title: const Text("예약 성공 시 자동 결제"),
                subtitle: _autoPayment && _selectedCard != null
                    ? Text("결제 카드: [${_selectedCard!.alias}]", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))
                    : const Text("설정에 등록된 카드로 즉시 결제합니다."),
                value: _autoPayment,
                onChanged: _handleAutoPaymentChange,
              ),

              const Divider(),

              // 6. Macro Execution Options (Ported from srtgo.py)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("예매 실행 옵션", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    const SizedBox(height: 8),
                    
                    // Scheduled Start
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("특정 시간에 예매 시작"),
                      subtitle: Text(_useSchedule 
                          ? "시작 시각: ${_scheduledTime.format(context)}" 
                          : "설정 완료 후 즉시 예매를 시도합니다."),
                      value: _useSchedule,
                      onChanged: (val) {
                        setState(() => _useSchedule = val);
                      },
                    ),
                    if (_useSchedule)
                      ListTile(
                        contentPadding: const EdgeInsets.only(left: 16),
                        leading: const Icon(Icons.timer_outlined),
                        title: const Text("시작 시각 설정"),
                        trailing: Text(_scheduledTime.format(context), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _scheduledTime,
                          );
                          if (picked != null) setState(() => _scheduledTime = picked);
                        },
                      ),

                    const SizedBox(height: 8),

                    // Duration
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("최대 예매 시도 시간"),
                      subtitle: Text(_durationMinutes == 0 ? "성공할 때까지 무제한 시도" : "$_durationMinutes분 동안 시도 후 종료"),
                      trailing: DropdownButton<int>(
                        value: _durationMinutes,
                        underline: const SizedBox(),
                        onChanged: (val) {
                          if (val != null) setState(() => _durationMinutes = val);
                        },
                        items: [
                          const DropdownMenuItem(value: 0, child: Text("무제한")),
                          const DropdownMenuItem(value: 10, child: Text("10분")),
                          const DropdownMenuItem(value: 30, child: Text("30분")),
                          const DropdownMenuItem(value: 60, child: Text("1시간")),
                          const DropdownMenuItem(value: 120, child: Text("2시간")),
                          const DropdownMenuItem(value: 300, child: Text("5시간")),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // 6. Search Button
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _searchTrains,
                    icon: _isLoading 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.search),
                    label: Text(_isLoading ? "조회중..." : "열차 조회하기", style: const TextStyle(fontSize: 18)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCounter(String label, int value, Function(int) onChanged) {
    return ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
          ),
          Text(value.toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < 9 ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}