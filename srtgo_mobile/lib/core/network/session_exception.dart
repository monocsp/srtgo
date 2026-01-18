class SessionExpiredException implements Exception {
  final String message;
  SessionExpiredException([this.message = "세션이 만료되었습니다. 다시 로그인해주세요."]);

  @override
  String toString() => message;
}
