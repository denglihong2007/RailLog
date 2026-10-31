import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:raillog/src/models/ticket_12306_order.dart';
import 'package:raillog/src/services/ticket_12306_service.dart';
import 'package:raillog/src/services/ticket_order_confirmation.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/ticket_order_selection.dart';

class Import12306Page extends StatefulWidget {
  const Import12306Page({super.key, this.service});

  final Ticket12306Service? service;

  @override
  State<Import12306Page> createState() => _Import12306PageState();
}

class _Import12306PageState extends State<Import12306Page> {
  late final Ticket12306Service _service =
      widget.service ?? Ticket12306Service();
  final Set<String> _selectedKeys = {};
  final Set<String> _importedKeys = {};
  List<Ticket12306Order> _orders = const [];
  Uint8List? _qrImage;
  String? _username;
  String? _message;
  String? _qrMessage;
  bool _messageIsError = false;
  bool _qrMessageIsError = false;
  bool _isCreatingQr = false;
  bool _isPollingQr = false;
  bool _isFinalizingLogin = false;
  bool _invoiceVerified = false;
  bool _invoiceVerificationStarted = false;
  bool _isQuerying = false;
  bool _isImporting = false;
  int? _preparingPosition;
  int _pollGeneration = 0;

  bool get _canQuery =>
      _username != null && !_isFinalizingLogin && !_isQuerying;

  List<Ticket12306Order> get _selectableOrders => _orders
      .where(
        (order) => order.canImport && !_importedKeys.contains(order.dedupKey),
      )
      .toList(growable: false);

  @override
  void dispose() {
    _pollGeneration++;
    _service.dispose();
    super.dispose();
  }

  Future<void> _startQrLogin() async {
    final generation = ++_pollGeneration;
    setState(() {
      _isCreatingQr = true;
      _qrImage = null;
      _username = null;
      _invoiceVerified = false;
      _invoiceVerificationStarted = false;
      _orders = const [];
      _selectedKeys.clear();
      _importedKeys.clear();
      _message = null;
      _qrMessage = null;
      _qrMessageIsError = false;
    });
    try {
      final result = await _service.createQrCode();
      if (!mounted || generation != _pollGeneration) return;
      final image = _decodeQrImage(result.imageBase64);
      setState(() {
        _qrImage = image;
        _isPollingQr = true;
        _qrMessage = '请使用铁路 12306 App 扫码并确认登录';
      });
      unawaited(_pollQrStatus(result.uuid, generation));
    } catch (error) {
      if (!mounted || generation != _pollGeneration) return;
      setState(() {
        _qrMessageIsError = true;
        _qrMessage = '获取二维码失败：$error';
      });
    } finally {
      if (mounted && generation == _pollGeneration) {
        setState(() => _isCreatingQr = false);
      }
    }
  }

  Future<void> _pollQrStatus(String uuid, int generation) async {
    try {
      while (mounted && generation == _pollGeneration) {
        final status = await _service.checkQrStatus(uuid);
        if (!mounted || generation != _pollGeneration) return;
        setState(() {
          _qrMessageIsError = false;
          _qrMessage = status.message.isEmpty ? '等待扫码确认' : status.message;
        });
        if (status.code == '2') {
          final ticket = status.uamtk;
          if (ticket == null || ticket.isEmpty) {
            throw const Ticket12306Exception('扫码成功，但未获得登录票据');
          }
          await _completeLogin(ticket, generation);
          if (mounted && generation == _pollGeneration) {
            await _queryRegularOrders();
          }
          return;
        }
        if (status.code == '3') {
          setState(() {
            _qrMessageIsError = true;
            _qrMessage = '二维码已过期，请重新获取';
          });
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } catch (error) {
      if (!mounted || generation != _pollGeneration) return;
      setState(() {
        _qrMessageIsError = true;
        _qrMessage = '登录状态查询失败：$error';
      });
    } finally {
      if (mounted && generation == _pollGeneration) {
        setState(() => _isPollingQr = false);
      }
    }
  }

  Future<void> _completeLogin(String uamtk, int generation) async {
    setState(() {
      _isFinalizingLogin = true;
      _qrMessage = '正在完成登录校验...';
    });
    try {
      final username = await _service.completeLogin(uamtk);
      if (!mounted || generation != _pollGeneration) return;
      setState(() {
        _username = username.isEmpty ? '已登录账号' : username;
        _qrMessage = '登录成功，正在查询行程';
      });
    } catch (error) {
      if (!mounted || generation != _pollGeneration) return;
      setState(() {
        _qrMessageIsError = true;
        _qrMessage = '登录失败：$error';
      });
    } finally {
      if (mounted && generation == _pollGeneration) {
        setState(() => _isFinalizingLogin = false);
      }
    }
  }

  Future<void> _restartInvoiceVerification() async {
    final generation = ++_pollGeneration;
    await _startInvoiceVerification(generation);
  }

  Future<void> _startInvoiceVerification(int generation) async {
    if (!mounted || generation != _pollGeneration) return;
    setState(() {
      _invoiceVerified = false;
      _invoiceVerificationStarted = true;
      _isCreatingQr = true;
      _qrImage = null;
      _qrMessageIsError = false;
      _qrMessage = '正在生成电子发票核验二维码...';
    });
    try {
      final result = await _service.createInvoiceVerificationQr();
      if (!mounted || generation != _pollGeneration) return;
      setState(() {
        _qrImage = _decodeQrImage(result.imageBase64);
        _isCreatingQr = false;
        _isPollingQr = true;
        _qrMessage = '请再次扫码完成电子发票访问核验';
      });
      await _pollInvoiceVerification(result.uuid, generation);
    } catch (error) {
      if (!mounted || generation != _pollGeneration) return;
      setState(() {
        _qrMessageIsError = true;
        _qrMessage = '获取电子发票核验二维码失败：$error';
      });
    } finally {
      if (mounted && generation == _pollGeneration) {
        setState(() {
          _isCreatingQr = false;
          _isPollingQr = false;
        });
      }
    }
  }

  Future<void> _pollInvoiceVerification(String uuid, int generation) async {
    while (mounted && generation == _pollGeneration) {
      final status = await _service.checkInvoiceVerificationQr(uuid);
      if (!mounted || generation != _pollGeneration) return;
      if (status.code == '2') {
        setState(() {
          _invoiceVerified = true;
          _qrMessageIsError = false;
          _qrMessage = status.message;
        });
        await _queryInvoiceAndMerge();
        return;
      }
      if (status.code != '0' && status.code != '1') {
        throw const Ticket12306Exception('电子发票核验状态异常，请重新获取二维码');
      }
      setState(() {
        _qrMessageIsError = false;
        _qrMessage = status.message;
      });
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _refreshOrders() async {
    await _queryRegularOrders();
    if (_invoiceVerified) {
      await _queryInvoiceAndMerge();
    }
  }

  /// 登录后即可查询，无需电子发票核验。
  Future<void> _queryRegularOrders() async {
    if (_username == null) return;
    setState(() {
      _isQuerying = true;
      _message = null;
      _selectedKeys.clear();
    });
    try {
      final orders = await _service.queryOrderTrips();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _messageIsError = false;
        _message = orders.isEmpty
            ? '近 1 个月没有可导入行程，可查看更多行程'
            : '近 1 个月共查询到 ${orders.length} 张车票';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = '查询订单失败：$error';
      });
    } finally {
      if (mounted) setState(() => _isQuerying = false);
    }
  }

  /// 核验通过后追加电子发票行程，并按车票去重合并（发票数据优先）。
  Future<void> _queryInvoiceAndMerge() async {
    setState(() => _isQuerying = true);
    try {
      final extra = await _service.queryInvoiceTrips();
      if (!mounted) return;
      setState(() {
        _orders = Ticket12306Service.mergeTrips(_orders, extra);
        _messageIsError = false;
        _message = '已加载近 180 天行程，合并去重后共 ${_orders.length} 张车票';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = '查询电子发票行程失败：$error';
      });
    } finally {
      if (mounted) setState(() => _isQuerying = false);
    }
  }

  Future<void> _importSelected() async {
    final selected = _orders
        .where((order) => _selectedKeys.contains(order.dedupKey))
        .toList(growable: false);
    if (selected.isEmpty || _isImporting) return;

    setState(() {
      _isImporting = true;
      _message = null;
      _messageIsError = false;
    });

    try {
      final result = await runTicketImport(
        context: context,
        orders: selected,
        onPreparing: (position) {
          if (!mounted) return;
          setState(() => _preparingPosition = position);
        },
        onImported: (order) {
          if (!mounted) return;
          setState(() {
            _importedKeys.add(order.dedupKey);
            _selectedKeys.remove(order.dedupKey);
          });
        },
      );
      if (!mounted) return;

      if (result.completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ticketImportOutcomeMessage(result))),
        );
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _messageIsError = false;
        _message = ticketImportOutcomeMessage(result);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = '导入失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _preparingPosition = null;
        });
      }
    }
  }

  void _toggleAll(bool? selected) {
    setState(() {
      _selectedKeys.clear();
      if (selected == true) {
        _selectedKeys.addAll(_selectableOrders.map((order) => order.dedupKey));
      }
    });
  }

  void _toggleOrder(Ticket12306Order order, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedKeys.add(order.dedupKey);
      } else {
        _selectedKeys.remove(order.dedupKey);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width > 880
        ? (width - AppLayout.detailMaxWidth) / 2
        : AppSpacing.lg;
    final selectable = _selectableOrders;
    final allSelected =
        selectable.isNotEmpty &&
        selectable.every((order) => _selectedKeys.contains(order.dedupKey));
    return Scaffold(
      appBar: AppBar(
        title: const Text('从 12306 导入'),
        scrolledUnderElevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              4,
            ),
            sliver: const SliverToBoxAdapter(child: _SmallWindowTip()),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              10,
            ),
            sliver: const SliverToBoxAdapter(
              child: TicketImportStepHeader(
                step: 1,
                icon: Icons.login,
                title: '登录铁路 12306',
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              24,
            ),
            sliver: SliverToBoxAdapter(
              child: _username == null
                  ? Column(
                      children: [
                        _LoginPanel(
                          qrImage: _qrImage,
                          status: _qrMessage,
                          statusIsError: _qrMessageIsError,
                          isBusy:
                              _isCreatingQr ||
                              _isPollingQr ||
                              _isFinalizingLogin,
                          isLoggedIn: false,
                          isInvoiceVerification: false,
                          onCreateQr: _startQrLogin,
                        ),
                      ],
                    )
                  : _CompletedStepCard(message: '已登录：$_username'),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              10,
            ),
            sliver: const SliverToBoxAdapter(
              child: TicketImportStepHeader(
                step: 2,
                icon: Icons.more_horiz,
                title: '查看更多行程（可选）',
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              24,
            ),
            sliver: SliverToBoxAdapter(
              child: _username == null
                  ? const _PendingStepCard(message: '登录后可查看更多行程')
                  : _invoiceVerified
                  ? const _CompletedStepCard(message: '已加载近 180 天电子发票行程')
                  : _invoiceVerificationStarted
                  ? Column(
                      children: [
                        _LoginPanel(
                          qrImage: _qrImage,
                          status: _qrMessage,
                          statusIsError: _qrMessageIsError,
                          isBusy:
                              _isCreatingQr ||
                              _isPollingQr ||
                              _isFinalizingLogin,
                          isLoggedIn: true,
                          isInvoiceVerification: true,
                          onCreateQr: _restartInvoiceVerification,
                        ),
                      ],
                    )
                  : _MoreTripsCard(onPressed: _restartInvoiceVerification),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              8,
            ),
            sliver: SliverToBoxAdapter(
              child: TicketImportStepHeader(
                step: 3,
                icon: Icons.train_outlined,
                title: '选择待导入车票',
                trailing: IconButton.filledTonal(
                  tooltip: '重新查询',
                  onPressed: _canQuery ? _refreshOrders : null,
                  icon: _isQuerying
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              8,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                '勾选车票后逐条确认导入，不会自动写入。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (_message != null)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding,
                8,
              ),
              sliver: SliverToBoxAdapter(
                child: TicketImportMessageBanner(
                  message: _message!,
                  isError: _messageIsError,
                ),
              ),
            ),
          if (_orders.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              sliver: SliverToBoxAdapter(
                child: TicketOrderSelectionToolbar(
                  selectedCount: _selectedKeys.length,
                  selectableCount: selectable.length,
                  allSelected: allSelected,
                  enabled: !_isImporting,
                  onToggleAll: _toggleAll,
                ),
              ),
            ),
          if (_orders.isEmpty && !_isQuerying)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: TicketImportEmptyState(
                  icon: _username == null
                      ? Icons.lock_outline
                      : Icons.confirmation_number_outlined,
                  title: _username == null ? '登录后显示近期行程' : '暂无可导入车票',
                  hint: _username == null
                      ? '扫码登录后即可查询近 1 个月的 12306 订单'
                      : '可尝试查看更多行程以加载更早记录',
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                4,
                horizontalPadding,
                112,
              ),
              sliver: SliverList.separated(
                itemCount: _orders.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final order = _orders[index];
                  return TicketOrderSelectionTile(
                    order: order,
                    selected: _selectedKeys.contains(order.dedupKey),
                    imported: _importedKeys.contains(order.dedupKey),
                    enabled: !_isImporting,
                    onChanged: order.canImport
                        ? (value) => _toggleOrder(order, value)
                        : null,
                  );
                },
              ),
            ),
        ],
      ),
      bottomNavigationBar: _selectedKeys.isEmpty
          ? null
          : TicketImportActionBar(
              selectedCount: _selectedKeys.length,
              preparingPosition: _preparingPosition,
              isImporting: _isImporting,
              onStart: _importSelected,
              horizontalPadding: horizontalPadding,
            ),
    );
  }
}

class _CompletedStepCard extends StatelessWidget {
  const _CompletedStepCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard.filled(
      color: colors.primaryContainer,
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.check_circle_outline, color: colors.primary),
        title: Text(message),
      ),
    );
  }
}

class _MoreTripsCard extends StatelessWidget {
  const _MoreTripsCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard.filled(
      color: colors.surfaceContainerLow,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 32,
                  color: colors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '查看更多行程',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '以上为 12306 订单记录。电子发票行程可覆盖近 180 天，'
                        '需要再次扫码核验访问权限，重复行程会自动去重。',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: const Icon(Icons.qr_code_2),
              label: const Text('扫码查看更多'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingStepCard extends StatelessWidget {
  const _PendingStepCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard.filled(
      color: colors.surfaceContainerLow,
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.lock_outline, color: colors.onSurfaceVariant),
        title: Text(message, style: TextStyle(color: colors.onSurfaceVariant)),
      ),
    );
  }
}

class _SmallWindowTip extends StatelessWidget {
  const _SmallWindowTip();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard.filled(
      color: colors.tertiaryContainer,
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          Icons.picture_in_picture_alt_outlined,
          color: colors.onTertiaryContainer,
        ),
        title: Text(
          '建议开启小窗模式',
          style: TextStyle(color: colors.onTertiaryContainer),
        ),
        subtitle: Text(
          '避免切回应用时网络请求中断',
          style: TextStyle(color: colors.onTertiaryContainer),
        ),
      ),
    );
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.qrImage,
    required this.status,
    required this.statusIsError,
    required this.isBusy,
    required this.isLoggedIn,
    required this.isInvoiceVerification,
    required this.onCreateQr,
  });

  final Uint8List? qrImage;
  final String? status;
  final bool statusIsError;
  final bool isBusy;
  final bool isLoggedIn;
  final bool isInvoiceVerification;
  final VoidCallback onCreateQr;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard.filled(
      color: isLoggedIn ? colors.primaryContainer : colors.surfaceContainerLow,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final details = _LoginDetails(
              status: status,
              statusIsError: statusIsError,
              isBusy: isBusy,
              isLoggedIn: isLoggedIn,
              isInvoiceVerification: isInvoiceVerification,
              hasQrCode: qrImage != null,
              onCreateQr: onCreateQr,
            );
            final qr = qrImage == null
                ? null
                : Container(
                    width: compact ? 168 : 184,
                    height: compact ? 168 : 184,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Image.memory(qrImage!, gaplessPlayback: true),
                  );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  details,
                  if (qr != null) ...[
                    const SizedBox(height: 20),
                    Align(child: qr),
                  ],
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: details),
                if (qr != null) ...[const SizedBox(width: 28), qr],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LoginDetails extends StatelessWidget {
  const _LoginDetails({
    required this.status,
    required this.statusIsError,
    required this.isBusy,
    required this.isLoggedIn,
    required this.isInvoiceVerification,
    required this.hasQrCode,
    required this.onCreateQr,
  });

  final String? status;
  final bool statusIsError;
  final bool isBusy;
  final bool isLoggedIn;
  final bool isInvoiceVerification;
  final bool hasQrCode;
  final VoidCallback onCreateQr;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isInvoiceVerification
              ? Icons.domain_verification_outlined
              : isLoggedIn
              ? Icons.verified_outlined
              : Icons.phone_android,
          size: 32,
          color: isLoggedIn ? colors.onPrimaryContainer : colors.primary,
        ),
        const SizedBox(height: 12),
        Text(
          isInvoiceVerification
              ? '核验电子发票访问'
              : isLoggedIn
              ? '账号已连接'
              : '使用 12306 App 扫码',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (status != null) ...[
          const SizedBox(height: 6),
          Text(
            status!,
            style: TextStyle(
              color: statusIsError
                  ? colors.error
                  : isLoggedIn
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: isBusy ? null : onCreateQr,
          icon: isBusy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.qr_code_2),
          label: Text(hasQrCode ? '重新获取' : '获取二维码'),
        ),
      ],
    );
  }
}

Uint8List _decodeQrImage(String source) {
  final comma = source.indexOf(',');
  return base64Decode(comma >= 0 ? source.substring(comma + 1) : source);
}
