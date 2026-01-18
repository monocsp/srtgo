import 'package:flutter/material.dart';
import '../data/models/credit_card_model.dart';
import '../data/repositories/card_repository.dart';

class CardManagementScreen extends StatefulWidget {
  const CardManagementScreen({super.key});

  @override
  State<CardManagementScreen> createState() => _CardManagementScreenState();
}

class _CardManagementScreenState extends State<CardManagementScreen> {
  final CardRepository _repo = CardRepository();
  List<CreditCard> _cards = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    setState(() => _isLoading = true);
    try {
      final cards = await _repo.getCards();
      setState(() => _cards = cards);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addCard() async {
    final result = await showDialog<CreditCard>(
      context: context,
      builder: (context) => const AddCardDialog(),
    );

    if (result != null) {
      await _repo.addCard(result);
      _loadCards();
    }
  }

  Future<void> _deleteCard(String alias) async {
    await _repo.removeCard(alias);
    _loadCards();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("카드 관리")),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCard,
        child: const Icon(Icons.add),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _cards.isEmpty
          ? const Center(child: Text("등록된 카드가 없습니다."))
          : ListView.builder(
              itemCount: _cards.length,
              itemBuilder: (context, index) {
                final card = _cards[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: const Icon(Icons.credit_card, color: Colors.blue),
                    title: Text(card.alias),
                    subtitle: Text("${card.number.substring(0, 4)}-****-****-****"),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteCard(card.alias),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class AddCardDialog extends StatefulWidget {
  const AddCardDialog({super.key});

  @override
  State<AddCardDialog> createState() => _AddCardDialogState();
}

class _AddCardDialogState extends State<AddCardDialog> {
  final _formKey = GlobalKey<FormState>();
  final _aliasCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _birthdayCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("카드 추가"),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _aliasCtrl,
                decoration: const InputDecoration(labelText: "별명 (예: 법인카드)"),
                validator: (v) => v!.isEmpty ? "필수 입력입니다" : null,
              ),
              TextFormField(
                controller: _numberCtrl,
                decoration: const InputDecoration(labelText: "카드번호 (- 제외)"),
                keyboardType: TextInputType.number,
                validator: (v) => v!.length < 15 ? "유효한 번호를 입력하세요" : null,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _passwordCtrl,
                      decoration: const InputDecoration(labelText: "비번 앞 2자리"),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 2,
                      validator: (v) => v!.length != 2 ? "2자리 입력" : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _expiryCtrl,
                      decoration: const InputDecoration(labelText: "유효기간 (YYMM)"),
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      validator: (v) => v!.length != 4 ? "4자리 입력" : null,
                    ),
                  ),
                ],
              ),
              TextFormField(
                controller: _birthdayCtrl,
                decoration: const InputDecoration(labelText: "생년월일(6자리) / 사업자번호(10자리)"),
                keyboardType: TextInputType.number,
                validator: (v) => (v!.length != 6 && v.length != 10) ? "6자리 또는 10자리" : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, CreditCard(
                alias: _aliasCtrl.text,
                number: _numberCtrl.text,
                password: _passwordCtrl.text,
                expiry: _expiryCtrl.text,
                birthday: _birthdayCtrl.text,
              ));
            }
          },
          child: const Text("등록"),
        ),
      ],
    );
  }
}
