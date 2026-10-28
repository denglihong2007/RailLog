class MailImportException implements Exception {
  const MailImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
