import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srtgo_mobile/core/constants/seat_options.dart';
import 'package:srtgo_mobile/features/reservation/data/models/train_model.dart';
import '../data/srt_reservation_repository.dart';
import '../data/srt_train_repository.dart';
import 'logic/cart_provider.dart'; // Added Import
import '../../auth/presentation/logic/user_provider.dart';
import '../../auth/data/repositories/auth_repository_impl.dart';
import '../../auth/presentation/login_screen.dart';
import '../../../core/network/session_exception.dart';

import '../../home/presentation/logic/home_providers.dart';
import '../../tickets/presentation/logic/tickets_provider.dart';
import '../../tickets/data/repositories/srt_ticket_repository.dart';
import '../../settings/data/models/credit_card_model.dart';

class TrainListScreen extends ConsumerStatefulWidget {
  // ... (rest remains same)

  const TrainListScreen({
    super.key,
    required this.trains,
    required this.title,
    required this.passengerCounts,
    this.paymentCard,
    required this.seatOption,
    this.useSchedule = false,
    this.scheduledTime,
    this.durationMinutes = 0,
  });

  @override
  ConsumerState<TrainListScreen> createState() => _TrainListScreenState();
}

class _TrainListScreenState extends ConsumerState<TrainListScreen> {
  final SrtReservationRepository _reserveRepo = SrtReservationRepository();
  final SrtTrainRepository _trainRepo = SrtTrainRepository();
  final SrtTicketRepository _ticketRepo = SrtTicketRepository();

  bool _isReserving = false;
  bool _isMacroRunning = false;
  int _macroTryCount = 0;
  String _macroStatus = "시작하는 중...";
  int _macroLoopId = 0;

  // Helper to check availability based on option
  bool _canReserve(Train train) {
    switch (widget.seatOption) {
      case SeatOption.generalFirst:
        return train.canReserveGeneral ||
            train.canReserveSpecial ||
            train.canReserveStandby;
      case SeatOption.generalOnly:
        return train.canReserveGeneral || train.canReserveStandby;
      case SeatOption.specialFirst:
        return train.canReserveSpecial ||
            train.canReserveGeneral ||
            train.canReserveStandby;
      case SeatOption.specialOnly:
        return train.canReserveSpecial || train.canReserveStandby;
    }
  }

  Future<void> _handleReserve(Train train) async {
    if (_canReserve(train)) {
      await _attemptReserve(train);
    } else {
      _showMacroDialog(train);
    }
  }

  Future<void> _attemptReserve(Train train, {bool isFromMacro = false}) async {
    if (mounted) setState(() => _isReserving = true);

    bool isStandby = false;
    bool preferSpecial = false;

    switch (widget.seatOption) {
      case SeatOption.generalFirst:
        if (!train.canReserveGeneral) {
          if (train.canReserveSpecial) {
            preferSpecial = true;
          } else if (train.canReserveStandby) {
            isStandby = true;
          }
        }
        break;
      case SeatOption.generalOnly:
        if (!train.canReserveGeneral && train.canReserveStandby) {
          isStandby = true;
        }
        break;
      case SeatOption.specialFirst:
        if (train.canReserveSpecial) {
          preferSpecial = true;
        } else if (!train.canReserveGeneral && train.canReserveStandby) {
          isStandby = true;
        }
        break;
      case SeatOption.specialOnly:
        if (train.canReserveSpecial) {
          preferSpecial = true;
        } else if (train.canReserveStandby) {
          isStandby = true;
        }
        break;
    }

    try {
      await _performReservation(train, isStandby, preferSpecial);
    } catch (e) {
      // Check for Login Required Error
      if (e.toString().contains("로그인") ||
          (e is DioException && e.error is SessionExpiredException)) {
        String? failedId;
        try {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("세션 만료. 재로그인 시도 중..."),
                duration: Duration(seconds: 1),
              ),
            );
          }

          final storage = CredentialStorage();
          final userState = ref.read(userProvider);
          final currentUser = userState.currentUser;

          if (currentUser != null) {
            failedId = currentUser.membershipNumber;
            final creds = await storage.getCredentialsById(
              currentUser.membershipNumber,
            );
            if (creds != null) {
              await ref
                  .read(authRepositoryProvider)
                  .login(creds['username']!, creds['password']!);

              // Retry Reservation
              try {
                await _performReservation(train, isStandby, preferSpecial);
                return; // Success
              } catch (retryError) {
                if (isFromMacro) {
                  // If macro, don't fail, just resume searching
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "재시도 실패 (${retryError.toString().replaceAll("Exception: ", "")})... 매크로 재개",
                        ),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                    // Resume Macro Loop
                    _showMacroDialog(train);
                    return;
                  }
                }
                rethrow; // Manual mode -> show error
              }
            }
          }
        } catch (reloginError) {
          // Fatal Re-login Failure
          if (mounted) {
            // Navigate to Login with Error & ID
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => LoginScreen(
                  initialRailType:
                      "SRT", // Assume SRT for now as this is SRT logic
                  initialId: failedId,
                  errorMessage: "로그인에 실패하여 로그아웃되었습니다.",
                ),
              ),
              (route) => false,
            );
            return;
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll("Exception: ", "")),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isReserving = false);
    }
  }

  Future<void> _performReservation(
    Train train,
    bool isStandby,
    bool preferSpecial,
  ) async {
    final reservationResult = await _reserveRepo.reserve(
      train: train,
      passengers: widget.passengerCounts,
      isStandby: isStandby,
      preferSpecialSeat: preferSpecial,
    );

    final pnrNo = reservationResult['pnrNo'] ?? "Unknown";
    String message = "예약번호: $pnrNo\n\n";

    bool paid = false;
    if (widget.paymentCard != null && !isStandby) {
      try {
        final userState = ref.read(userProvider);
        final currentUser = userState.currentUser;
        if (currentUser == null) throw Exception("로그인 정보가 없습니다.");

        // Wait a bit before fetching tickets to ensure backend update
        await Future.delayed(const Duration(milliseconds: 500));

        final tickets = await _ticketRepo.fetchTickets();
        final ticket = tickets.firstWhere(
          (t) => t.pnrNo == pnrNo,
          orElse: () => throw Exception("예약 내역을 찾을 수 없습니다."),
        );

        await _ticketRepo.payTicket(
          ticket: ticket,
          cardNumber: widget.paymentCard!.number,
          cardPassword: widget.paymentCard!.password,
          cardExpiry: widget.paymentCard!.expiry,
          cardAuthValue: widget.paymentCard!.birthday,
          mbCrdNo: currentUser.membershipNumber,
        );

        message += "✅ 자동 결제 성공!\n\n[확인/취소] 탭에서 발권 내역을 확인하세요.";
        paid = true;
      } catch (e) {
        message +=
            "⚠️ 자동 결제 실패: ${e.toString().replaceAll("Exception: ", "")}\n\n직접 결제를 진행해주세요.";
      }
    } else {
      message += "[확인/취소] 탭으로 이동합니다.";
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(paid ? "예약 및 결제 성공!" : "예약 성공!"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              ref.invalidate(ticketsProvider);
              ref.read(homeTabIndexProvider.notifier).state = 1;
            },
            child: const Text("확인"),
          ),
        ],
      ),
    );
  }

  void _showMacroDialog(Train targetTrain) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (sbContext, setStateDialog) {
            if (!_isMacroRunning) {
              _isMacroRunning = true;
              _macroLoopId++;
              final currentLoopId = _macroLoopId;

              _runMacroLoop(targetTrain, currentLoopId, (count, status) {
                // Safely call setStateDialog
                if (_isMacroRunning &&
                    _macroLoopId == currentLoopId &&
                    mounted) {
                  try {
                    setStateDialog(() {});
                  } catch (_) {
                    // Ignore if dialog is disposed
                  }
                }
              });
            }

            return AlertDialog(
              title: const Text("자동 예매 실행 중"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  Text("열차: ${targetTrain.trainName} ${targetTrain.trainNo}"),
                  const SizedBox(height: 8),
                  Text("옵션: ${widget.seatOption.label}"),
                  const SizedBox(height: 8),
                  Text("시도 횟수: $_macroTryCount회"),
                  const SizedBox(height: 8),
                  Text(
                    _macroStatus,
                    style: const TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _isMacroRunning = false;
                    Navigator.pop(dialogContext);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text("사용자 요청으로 예매가 중단되었습니다."),
                          duration: const Duration(
                            days: 1,
                          ), // Persistent until action
                          action: SnackBarAction(
                            label: '닫기',
                            textColor: Colors.white,
                            onPressed: () {
                              ScaffoldMessenger.of(
                                context,
                              ).hideCurrentSnackBar();
                            },
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    "중단하기",
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      _isMacroRunning = false;
    });
  }

  int _getHumanDelay() {
    final random = Random();
    final base = 800;
    final jitter = (random.nextDouble() * random.nextDouble() * 1200).toInt();
    return base + jitter;
  }

  Future<void> _runMacroLoop(
    Train target,
    int loopId,
    Function(int, String) onUpdate,
  ) async {
    _macroTryCount = 0;
    final random = Random();
    DateTime? limitEndTime;
    int reloginAttempts = 0;

    // 1. Scheduled Start Logic
    if (widget.useSchedule && widget.scheduledTime != null) {
      final now = DateTime.now();
      var startDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        widget.scheduledTime!.hour,
        widget.scheduledTime!.minute,
      );
      if (startDateTime.isBefore(now))
        startDateTime = startDateTime.add(const Duration(days: 1));

      while (_isMacroRunning &&
          loopId == _macroLoopId &&
          DateTime.now().isBefore(startDateTime)) {
        final remaining = startDateTime.difference(DateTime.now());
        final h = remaining.inHours;
        final m = remaining.inMinutes % 60;
        final s = remaining.inSeconds % 60;
        _macroStatus =
            "⏰ 예약 시작 대기 중...\n(${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')} 남음)";
        onUpdate(0, _macroStatus);
        await Future.delayed(const Duration(seconds: 1));
      }

      if (!_isMacroRunning || loopId != _macroLoopId) return;

      // Re-login after waiting
      _macroStatus = "🔄 세션 갱신을 위해 재로그인 중...";
      onUpdate(0, _macroStatus);
      try {
        final storage = CredentialStorage();
        final userState = ref.read(userProvider);
        final currentUser = userState.currentUser;
        if (currentUser != null) {
          final creds = await storage.getCredentialsById(
            currentUser.membershipNumber,
          );
          if (creds != null) {
            await ref
                .read(authRepositoryProvider)
                .login(creds['username']!, creds['password']!);
          }
        }
      } catch (_) {}
    }

    if (widget.durationMinutes > 0) {
      limitEndTime = DateTime.now().add(
        Duration(minutes: widget.durationMinutes),
      );
    }

    while (_isMacroRunning && loopId == _macroLoopId) {
      // 2. Duration Check
      if (limitEndTime != null && DateTime.now().isAfter(limitEndTime)) {
        _macroStatus = "🛑 설정한 예매 지속 시간(${widget.durationMinutes}분)이 지났습니다.";
        onUpdate(_macroTryCount, _macroStatus);

        _isMacroRunning = false;
        if (mounted) Navigator.pop(context); // Close Dialog

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("설정된 시간 내에 예매를 실패하여 중단되었습니다."),
              backgroundColor: Colors.orange,
              duration: const Duration(days: 1), // Persistent
              action: SnackBarAction(
                label: '닫기',
                textColor: Colors.white,
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              ),
            ),
          );
        }
        return;
      }

      _macroTryCount++;
      if (_macroTryCount % (20 + random.nextInt(10)) == 0) {
        final breakTime = 3 + random.nextInt(5);
        for (int i = breakTime; i > 0; i--) {
          if (!_isMacroRunning || loopId != _macroLoopId) return;
          _macroStatus = "과도한 접속 방지 휴식 중... ${i}초";
          onUpdate(_macroTryCount, _macroStatus);
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      _macroStatus = "잔여석 조회 중...";
      onUpdate(_macroTryCount, _macroStatus);

      try {
        final trains = await _trainRepo.searchTrains(
          depStation: target.depStation,
          arrStation: target.arrStation,
          date: target.depDate,
          time: target.depTime,
        );
        reloginAttempts = 0; // Success, reset attempts

        if (!_isMacroRunning || loopId != _macroLoopId) return;

        final freshTarget = trains.firstWhere(
          (t) => t.trainNo == target.trainNo,
          orElse: () => target,
        );

        if (_canReserve(freshTarget)) {
          _macroStatus = "좌석 발견! 예약 시도 중...";
          onUpdate(_macroTryCount, _macroStatus);

          // ATTEMPT RESERVATION INSIDE LOOP
          try {
            bool isStandby = false;
            bool preferSpecial = false;
            // Determine options (Logic copied from _attemptReserve)
            switch (widget.seatOption) {
              case SeatOption.generalFirst:
                if (!freshTarget.canReserveGeneral) {
                  if (freshTarget.canReserveSpecial)
                    preferSpecial = true;
                  else if (freshTarget.canReserveStandby)
                    isStandby = true;
                }
                break;
              case SeatOption.generalOnly:
                if (!freshTarget.canReserveGeneral &&
                    freshTarget.canReserveStandby)
                  isStandby = true;
                break;
              case SeatOption.specialFirst:
                if (freshTarget.canReserveSpecial)
                  preferSpecial = true;
                else if (!freshTarget.canReserveGeneral &&
                    freshTarget.canReserveStandby)
                  isStandby = true;
                break;
              case SeatOption.specialOnly:
                if (freshTarget.canReserveSpecial)
                  preferSpecial = true;
                else if (freshTarget.canReserveStandby)
                  isStandby = true;
                break;
            }

            // Perform Reservation Logic directly
            final reservationResult = await _reserveRepo.reserve(
              train: freshTarget,
              passengers: widget.passengerCounts,
              isStandby: isStandby,
              preferSpecialSeat: preferSpecial,
            );

            // SUCCESS!
            _isMacroRunning = false;
            if (mounted) Navigator.pop(context); // Close Macro Dialog

            // Show Success Dialog / Payment
            if (mounted)
              _handleReservationSuccess(reservationResult, isStandby);
            return;
          } catch (reserveError) {
            // Handle Reservation Error
            bool isSession =
                (reserveError is DioException &&
                    reserveError.error is SessionExpiredException) ||
                reserveError.toString().contains("로그인");

            if (isSession) {
              throw reserveError; // Throw to outer catch block for re-login logic
            }

            // Other errors (e.g. taken seat) -> Continue loop
            _macroStatus =
                "예약 실패 (${reserveError.toString().replaceAll("Exception: ", "")})... 재시도";
            onUpdate(_macroTryCount, _macroStatus);
            await Future.delayed(const Duration(seconds: 1));
            continue; // Continue searching
          }
        }
        await Future.delayed(Duration(milliseconds: _getHumanDelay()));
      } catch (e) {
        bool isSessionError =
            (e is DioException && e.error is SessionExpiredException) ||
            e.toString().contains("로그인");

        if (isSessionError) {
          String? failedId;
          _macroStatus = "🔑 세션 만료. 자동 재로그인 시도 중...";
          onUpdate(_macroTryCount, _macroStatus);

          if (reloginAttempts >= 1) {
            // Fatal Re-login Failure
            _isMacroRunning = false;
            if (mounted) Navigator.pop(context); // Close Dialog

            // Need to get ID for login screen
            final userState = ref.read(userProvider);
            failedId = userState.currentUser?.membershipNumber;

            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => LoginScreen(
                    initialRailType: "SRT",
                    initialId: failedId,
                    errorMessage: "로그인에 실패하여 로그아웃되었습니다.",
                  ),
                ),
                (route) => false,
              );
            }
            return;
          }

          try {
            reloginAttempts++;
            final storage = CredentialStorage();
            final userState = ref.read(userProvider);
            final currentUser = userState.currentUser;
            if (currentUser != null) {
              final creds = await storage.getCredentialsById(
                currentUser.membershipNumber,
              );
              if (creds != null) {
                await ref
                    .read(authRepositoryProvider)
                    .login(creds['username']!, creds['password']!);
                _macroStatus = "✅ 재로그인 성공. 다시 시도합니다.";
                onUpdate(_macroTryCount, _macroStatus);
                continue; // Continue loop immediately
              }
            }
            throw Exception("No credentials found");
          } catch (_) {
            // Re-login failed (will be caught next loop or handled here)
            // We increment reloginAttempts, so next time it will hit the limit if we just continue.
            // But actually we should probably fail hard here if login throws.
            // Let's rely on reloginAttempts logic in next iteration OR fail immediately.
            // For robustness, let's continue to let the 'reloginAttempts >= 1' check handle it if it persists.
          }
        }
        _macroStatus =
            "오류 발생 (${e.toString().replaceAll("Exception: ", "")})... 재시도";
        onUpdate(_macroTryCount, _macroStatus);
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  // Extracted Success Logic
  Future<void> _handleReservationSuccess(
    Map<String, dynamic> reservationResult,
    bool isStandby,
  ) async {
    final pnrNo = reservationResult['pnrNo'] ?? "Unknown";
    String message = "예약번호: $pnrNo\n\n";

    bool paid = false;
    if (widget.paymentCard != null && !isStandby) {
      try {
        final userState = ref.read(userProvider);
        final currentUser = userState.currentUser;
        if (currentUser == null) throw Exception("로그인 정보가 없습니다.");

        // Wait a bit before fetching tickets to ensure backend update
        await Future.delayed(const Duration(milliseconds: 500));

        final tickets = await _ticketRepo.fetchTickets();
        final ticket = tickets.firstWhere(
          (t) => t.pnrNo == pnrNo,
          orElse: () => throw Exception("예약 내역을 찾을 수 없습니다."),
        );

        await _ticketRepo.payTicket(
          ticket: ticket,
          cardNumber: widget.paymentCard!.number,
          cardPassword: widget.paymentCard!.password,
          cardExpiry: widget.paymentCard!.expiry,
          cardAuthValue: widget.paymentCard!.birthday,
          mbCrdNo: currentUser.membershipNumber,
        );

        message += "✅ 자동 결제 성공!\n\n[확인/취소] 탭에서 발권 내역을 확인하세요.";
        paid = true;
      } catch (e) {
        message +=
            "⚠️ 자동 결제 실패: ${e.toString().replaceAll("Exception: ", "")}\n\n직접 결제를 진행해주세요.";
      }
    } else {
      message += "[확인/취소] 탭으로 이동합니다.";
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(paid ? "예약 및 결제 성공!" : "예약 성공!"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              ref.invalidate(ticketsProvider);
              ref.read(homeTabIndexProvider.notifier).state = 1;
            },
            child: const Text("확인"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          ListView.builder(
            itemCount: widget.trains.length,
            itemBuilder: (context, index) {
              final train = widget.trains[index];
              final duration = _calculateDuration(train.depTime, train.arrTime);

              final cart = ref.watch(cartProvider);
              final isInCart = cart.any((t) => t.id == train.id);

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "[${train.trainName}] ${train.trainNo}",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            "소요시간: $duration분",
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildTimeColumn(train.depStation, train.depTime),
                          const Icon(Icons.arrow_right_alt),
                          _buildTimeColumn(train.arrStation, train.arrTime),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatusChip(
                            "특실",
                            train.specialSeatState,
                            train.canReserveSpecial,
                          ),
                          _buildStatusChip(
                            "일반실",
                            train.generalSeatState,
                            train.canReserveGeneral,
                          ),
                          if (train.reserveWaitCode >= 0)
                            _buildStatusChip(
                              "예약대기",
                              train.reserveWaitCode == 9 ? "신청가능" : "마감",
                              train.canReserveStandby,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            ref.read(cartProvider.notifier).toggleTrain(train);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: isInCart
                                ? Colors.redAccent
                                : Colors.blueGrey,
                          ),
                          icon: Icon(
                            isInCart
                                ? Icons.remove_shopping_cart
                                : Icons.add_shopping_cart,
                          ),
                          label: Text(isInCart ? "선택 해제" : "장바구니 담기"),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_isReserving)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeColumn(String station, String time) {
    final formattedTime = "${time.substring(0, 2)}:${time.substring(2, 4)}";
    return Column(
      children: [
        Text(station, style: const TextStyle(fontSize: 16)),
        Text(
          formattedTime,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String label, String status, bool isAvailable) {
    return Chip(
      label: Text("$label $status"),
      backgroundColor: isAvailable ? Colors.green[100] : Colors.grey[200],
      labelStyle: TextStyle(
        color: isAvailable ? Colors.green[900] : Colors.grey[600],
        fontSize: 12,
      ),
    );
  }

  int _calculateDuration(String dep, String arr) {
    final dH = int.parse(dep.substring(0, 2));
    final dM = int.parse(dep.substring(2, 4));
    final aH = int.parse(arr.substring(0, 2));
    final aM = int.parse(arr.substring(2, 4));
    int minDiff = (aH * 60 + aM) - (dH * 60 + dM);
    if (minDiff < 0) minDiff += 24 * 60;
    return minDiff;
  }
}
