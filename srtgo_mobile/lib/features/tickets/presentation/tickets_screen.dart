import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/srt_ticket_repository.dart';
import '../data/models/ticket_model.dart';
import '../../settings/data/repositories/card_repository.dart';
import '../../settings/data/models/credit_card_model.dart';
import 'logic/tickets_provider.dart';
import '../../auth/presentation/logic/user_provider.dart'; // Added Import

class TicketsScreen extends ConsumerWidget {
  const TicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(ticketsProvider);

    return Scaffold(
      body: ticketsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(err.toString().replaceAll("Exception: ", "")),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.refresh(ticketsProvider),
                child: const Text("다시 시도"),
              )
            ],
          ),
        ),
        data: (tickets) {
          if (tickets.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.confirmation_number_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text("예약 내역이 없습니다.", style: TextStyle(color: Colors.grey, fontSize: 16)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref.refresh(ticketsProvider),
                    child: const Text("새로고침"),
                  )
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.refresh(ticketsProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: tickets.length,
              itemBuilder: (context, index) {
                return TicketCard(ticket: tickets[index]);
              },
            ),
          );
        },
      ),
    );
  }
}

class TicketCard extends ConsumerStatefulWidget {
  final Ticket ticket;
  const TicketCard({super.key, required this.ticket});

  @override
  ConsumerState<TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends ConsumerState<TicketCard> {
  final SrtTicketRepository _repo = SrtTicketRepository();
  final CardRepository _cardRepo = CardRepository();
  bool _isLoading = false;

  Future<void> _handlePayment() async {
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
    final selectedCard = await showDialog<CreditCard>(
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

    if (selectedCard == null) return;

    // Get current user info for payment
    final userState = ref.read(userProvider);
    final currentUser = userState.currentUser;
    if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("로그인 정보가 없습니다.")),
          );
        }
        return;
    }

    setState(() => _isLoading = true);
    try {
      await _repo.payTicket(
        ticket: widget.ticket,
        cardNumber: selectedCard.number,
        cardPassword: selectedCard.password,
        cardExpiry: selectedCard.expiry,
        cardAuthValue: selectedCard.birthday,
        mbCrdNo: currentUser.membershipNumber,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("결제가 완료되었습니다!")),
        );
        ref.refresh(ticketsProvider); // Refresh List via Provider
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

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context, 
      builder: (context) => AlertDialog(
        title: const Text("예약 취소"),
        content: Text("정말 [${widget.ticket.trainName} ${widget.ticket.trainNo}] 예약을 취소하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("아니오")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("네, 취소합니다", style: TextStyle(color: Colors.red))),
        ],
      )
    );

    if (confirmed == true) {
      _cancelTicket();
    }
  }

  Future<void> _cancelTicket() async {
    setState(() => _isLoading = true);
    try {
      await _repo.cancelTicket(widget.ticket.pnrNo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("예약이 취소되었습니다.")));
        ref.refresh(ticketsProvider); // Refresh List via Provider
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll("Exception: ", "")), backgroundColor: Colors.red));
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;
    final bool isExpired = !ticket.isPaid && _isExpired(ticket.paymentLimitDate, ticket.paymentLimitTime);
    
    Color statusColor;
    String statusText;

    if (ticket.isPaid) {
      statusColor = Colors.green;
      statusText = "결제완료";
    } else if (isExpired) {
      statusColor = Colors.grey;
      statusText = "기한만료";
    } else {
      statusColor = Colors.orange;
      statusText = "결제대기";
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("예약번호: ${ticket.pnrNo}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                    )
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text("[${ticket.trainName}] ${ticket.trainNo}", 
                       style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStationInfo(ticket.depStation, ticket.depDate, ticket.depTime),
                    const Icon(Icons.arrow_forward, color: Colors.grey),
                    _buildStationInfo(ticket.arrStation, "", ticket.arrTime), 
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("${ticket.seatCount}석", style: const TextStyle(color: Colors.grey)),
                  ],
                ),
                if (!ticket.isPaid && !isExpired)
                   Padding(
                     padding: const EdgeInsets.only(top: 12.0),
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Row(
                           mainAxisAlignment: MainAxisAlignment.end,
                           children: [
                             // Cancel Button
                             OutlinedButton(
                               onPressed: _isLoading ? null : _confirmCancel,
                               style: OutlinedButton.styleFrom(
                                 foregroundColor: Colors.red,
                                 side: const BorderSide(color: Colors.red),
                               ),
                               child: const Text("예약 취소"),
                             ),
                             const SizedBox(width: 8),
                             // Payment Button
                             FilledButton(
                               onPressed: _isLoading ? null : _handlePayment,
                               style: FilledButton.styleFrom(
                                 backgroundColor: Colors.blue[800],
                               ),
                               child: const Text("결제하기"),
                             ),
                           ],
                         ),
                         const SizedBox(height: 8),
                         Text(
                           "기한: ${_formatDate(ticket.paymentLimitDate)} ${_formatTime(ticket.paymentLimitTime)} 까지",
                           style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                         ),
                       ],
                     ),
                   ),
              ],
            ),
          ),
          if (_isLoading)
            const Positioned.fill(
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildStationInfo(String station, String date, String time) {
    String formattedTime = "${time.substring(0, 2)}:${time.substring(2, 4)}";
    String formattedDate = date.isNotEmpty ? _formatDate(date) : "";
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(station, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (formattedDate.isNotEmpty)
           Text(formattedDate, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(formattedTime, style: const TextStyle(fontSize: 16)),
      ],
    );
  }

  String _formatDate(String yyyymmdd) {
    if (yyyymmdd.length != 8) return yyyymmdd;
    return "${yyyymmdd.substring(4, 6)}/${yyyymmdd.substring(6, 8)}";
  }

  String _formatTime(String hhmmss) {
    if (hhmmss.length < 4) return hhmmss;
    return "${hhmmss.substring(0, 2)}:${hhmmss.substring(2, 4)}";
  }

  bool _isExpired(String date, String time) {
    if (date.isEmpty || time.isEmpty) return false;
    try {
      final limit = DateTime.parse("${date}T$time");
      return DateTime.now().isAfter(limit);
    } catch (_) {
      return false;
    }
  }
}
