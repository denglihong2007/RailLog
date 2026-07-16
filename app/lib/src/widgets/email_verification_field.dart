import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:raillog/src/services/session_service.dart';

class EmailVerificationField extends StatefulWidget {
  const EmailVerificationField({
    super.key,
    required this.controller,
    required this.onSend,
    this.enabled = true,
  });

  final TextEditingController controller;
  final Future<String> Function() onSend;
  final bool enabled;

  @override
  State<EmailVerificationField> createState() => _EmailVerificationFieldState();
}

class _EmailVerificationFieldState extends State<EmailVerificationField> {
  Timer? _timer;
  int _seconds = 0;
  bool _sending = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || _seconds > 0) return;
    setState(() => _sending = true);
    try {
      final message = await widget.onSend();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      setState(() => _seconds = 60);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _seconds <= 1) {
          timer.cancel();
          if (mounted) setState(() => _seconds = 0);
        } else {
          setState(() => _seconds--);
        }
      });
    } on SessionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 6,
      decoration: InputDecoration(
        labelText: '邮箱验证码',
        prefixIcon: const Icon(Icons.verified_user_outlined),
        border: const OutlineInputBorder(),
        counterText: '',
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: TextButton(
            onPressed: !widget.enabled || _sending || _seconds > 0
                ? null
                : _send,
            child: Text(
              _sending ? '发送中' : (_seconds > 0 ? '${_seconds}s' : '获取验证码'),
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 96),
      ),
      validator: (value) => value?.length == 6 ? null : '请输入 6 位邮箱验证码',
    );
  }
}
