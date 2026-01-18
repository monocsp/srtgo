import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/ticket_model.dart';
import '../../data/repositories/srt_ticket_repository.dart';

final ticketsProvider = FutureProvider.autoDispose<List<Ticket>>((ref) async {
  final repo = SrtTicketRepository();
  return repo.fetchTickets();
});
