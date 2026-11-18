import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:raillog/src/models/ticket_12306_order.dart';
import 'package:raillog/src/pages/settings/ticket_12306_settings_page.dart';
import 'package:raillog/src/services/ticket_12306_auth_settings.dart';
import 'package:raillog/src/services/ticket_12306_service.dart';
import 'package:raillog/src/services/ticket_order_confirmation.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
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
  Ticket12306Credentials? _credentials;
  bool _loadingCredentials = true;
  bool _credentialsExpired = false;
  List<Ticket12306Order> _orders = const [];
  final Set<String> _selectedKeys = {};
  final Set<String> _importedKeys = {};
  bool _querying = false;
  bool _importing = false;
  bool _extendedLoaded = false;
  int? _preparingPosition;
  String? _message;
  bool _messageIsError = false;

  List<Ticket12306Order> get _selectableOrders => _orders
      .where(
        (order) => order.canImport && !_importedKeys.contains(order.dedupKey),
      )
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _loadCredentials() async {
    final credentials = await Ticket12306AuthSettings.load();
    if (!mounted) return;
    final usable = credentials?.isComplete ?? false;
    if (usable) _service.restoreCredentials(credentials!);
    setState(() {
      _credentials = usable ? credentials : null;
      _loadingCredentials = false;
      _credentialsExpired = credentials != null && !usable;
    });
    if (usable) await _loadTrips();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      m3PageRoute(builder: (context) => const Ticket12306SettingsPage()),
    );
    if (!mounted) return;
    final credentials = await Ticket12306AuthSettings.load();
    if (!mounted) return;
    final usable = credentials?.isComplete ?? false;
    if (usable) _service.restoreCredentials(credentials!);
    final changed = !_sameCredentials(
      _credentials,
      usable ? credentials : null,
    );
    setState(() {
      _credentials = usable ? credentials : null;
      _credentialsExpired = credentials != null && !usable;
      if (!usable || changed) {
        _orders = const [];
        _extendedLoaded = false;
        _selectedKeys.clear();
        _message = null;
        _messageIsError = false;
      }
    });
    if (usable && changed) await _loadTrips();
  }

  bool _sameCredentials(
    Ticket12306Credentials? first,
    Ticket12306Credentials? second,
  ) {
    if (first == null || second == null) return first == second;
    return jsonEncode(first.toJson()) == jsonEncode(second.toJson());
  }

  Future<void> _loadTrips() async {
    final credentials = _credentials;
    if (credentials == null || _querying) return;
    setState(() {
      _querying = true;
      _selectedKeys.clear();
      _message = null;
      _messageIsError = false;
    });
    try {
      var invoiceVerified = credentials.invoiceVerified;
      String? warning;
      try {
        final state = await _service.checkCredentials();
        if (!mounted) return;
        if (!state.loginValid) {
          await _markCredentialsExpired();
          return;
        }
        if (credentials.invoiceVerified && !state.invoiceVerified) {
          warning = '人证核验凭证已过期，本次只加载近 1 个月订单，请前往设置重新核验';
        }
        invoiceVerified = state.invoiceVerified;
        if (invoiceVerified != credentials.invoiceVerified) {
          await _persistCredentials(invoiceVerified: invoiceVerified);
        }
      } catch (_) {
        // 服务端检查失败时不阻断查询；订单接口本身还会再判断一次登录状态。
      }
      if (!mounted) return;

      final orders = await _service.queryOrderTrips();
      if (!mounted) return;

      var merged = orders;
      var extendedLoaded = false;
      if (invoiceVerified) {
        try {
          merged = Ticket12306Service.mergeTrips(
            merged,
            await _service.queryPersonalTrips(),
          );
          extendedLoaded = true;
        } on Ticket12306AuthException {
          warning ??= '人证核验已失效，本次只加载了近期订单，请前往设置重新核验';
          invoiceVerified = false;
        } catch (error) {
          warning ??= '本人车票加载失败：$error';
        }
        if (invoiceVerified) {
          try {
            merged = Ticket12306Service.mergeTrips(
              merged,
              await _service.queryInvoiceTrips(),
            );
            extendedLoaded = true;
          } on Ticket12306AuthException {
            warning ??= '人证核验已失效，本次只加载了近期订单，请前往设置重新核验';
            invoiceVerified = false;
          } catch (error) {
            warning ??= '电子发票行程加载失败：$error';
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _orders = merged;
        _extendedLoaded = extendedLoaded;
        _messageIsError = warning != null;
        _message =
            warning ??
            (merged.isEmpty ? '近 1 个月没有可导入行程' : '共查询到 ${merged.length} 张车票');
      });
      await _persistCredentials(invoiceVerified: invoiceVerified);
    } on Ticket12306AuthException {
      await _markCredentialsExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = '查询订单失败：$error';
      });
    } finally {
      if (mounted) setState(() => _querying = false);
    }
  }

  Future<void> _markCredentialsExpired() async {
    await Ticket12306AuthSettings.clear();
    _service.clearSession();
    if (!mounted) return;
    setState(() {
      _credentials = null;
      _credentialsExpired = true;
      _orders = const [];
      _extendedLoaded = false;
      _selectedKeys.clear();
      _message = null;
      _messageIsError = false;
    });
  }

  /// 查询会刷新 Cookie 有效期，顺手把最新凭证写回本机。
  Future<void> _persistCredentials({required bool invoiceVerified}) async {
    final credentials = _credentials;
    if (credentials == null) return;
    final updated = _service.exportCredentials(
      invoiceVerified: invoiceVerified,
      loginAt: credentials.loginAt,
    );
    if (updated.cookies.isEmpty) return;
    await Ticket12306AuthSettings.save(updated);
    if (!mounted) return;
    setState(() => _credentials = updated);
  }

  Future<void> _importSelected() async {
    final selected = _orders
        .where((order) => _selectedKeys.contains(order.dedupKey))
        .toList(growable: false);
    if (selected.isEmpty || _importing) return;

    setState(() {
      _importing = true;
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
          _importing = false;
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
    final colors = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width > 880
        ? (width - AppLayout.detailMaxWidth) / 2
        : AppSpacing.lg;
    final credentials = _credentials;
    final selectable = _selectableOrders;
    final allSelected =
        selectable.isNotEmpty &&
        selectable.every((order) => _selectedKeys.contains(order.dedupKey));

    return Scaffold(
      appBar: AppBar(
        title: const Text('从 12306 导入'),
        scrolledUnderElevation: 0,
      ),
      body: _loadingCredentials
          ? const Center(child: CircularProgressIndicator())
          : credentials == null || _credentialsExpired
          ? _CredentialsProblem(
              expired: _credentialsExpired,
              onOpenSettings: _openSettings,
            )
          : RefreshIndicator(
              onRefresh: _loadTrips,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  16,
                  horizontalPadding,
                  112,
                ),
                children: [
                  _AccountCard(
                    credentials: credentials,
                    extendedLoaded: _extendedLoaded,
                    onOpenSettings: _openSettings,
                  ),
                  const SizedBox(height: 20),
                  TicketImportStepHeader(
                    step: 1,
                    icon: Icons.train_outlined,
                    title: '选择待导入车票',
                    trailing: IconButton.filledTonal(
                      tooltip: '重新查询',
                      onPressed: _querying || _importing ? null : _loadTrips,
                      icon: _querying
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '读取近 1 个月的 12306 订单；完成人证核验后可加载电子发票和本人车票。'
                    '勾选后逐条确认导入，不会自动写入。',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  if (!credentials.invoiceVerified) ...[
                    _InvoiceVerificationHint(onOpenSettings: _openSettings),
                    const SizedBox(height: 12),
                  ],
                  if (_message != null) ...[
                    TicketImportMessageBanner(
                      message: _message!,
                      isError: _messageIsError,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_querying)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (selectable.isNotEmpty) ...[
                    TicketOrderSelectionToolbar(
                      selectedCount: _selectedKeys.length,
                      selectableCount: selectable.length,
                      allSelected: allSelected,
                      enabled: !_importing && !_querying,
                      onToggleAll: _toggleAll,
                    ),
                  ],
                  for (final order in _orders) ...[
                    TicketOrderSelectionTile(
                      order: order,
                      selected: _selectedKeys.contains(order.dedupKey),
                      imported: _importedKeys.contains(order.dedupKey),
                      enabled: !_importing && !_querying,
                      onChanged: order.canImport
                          ? (value) => _toggleOrder(order, value)
                          : null,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_orders.isEmpty && !_querying)
                    TicketImportEmptyState(
                      title: '暂无可导入车票',
                      hint: credentials.invoiceVerified
                          ? '近 1 个月没有查询到 12306 订单'
                          : '可在设置中完成人证核验，加载更早行程',
                      actionLabel: '重新查询',
                      onAction: _loadTrips,
                    ),
                ],
              ),
            ),
      bottomNavigationBar: _selectedKeys.isEmpty
          ? null
          : TicketImportActionBar(
              selectedCount: _selectedKeys.length,
              preparingPosition: _preparingPosition,
              isImporting: _importing,
              onStart: _importSelected,
              horizontalPadding: horizontalPadding,
            ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.credentials,
    required this.extendedLoaded,
    required this.onOpenSettings,
  });

  final Ticket12306Credentials credentials;
  final bool extendedLoaded;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final username = credentials.username.trim();
    final verificationStatus = credentials.invoiceVerified
        ? (extendedLoaded ? '已加载扩展行程' : '人证核验已通过')
        : '人证核验未核验';
    return AppCard.filled(
      color: colors.surfaceContainerLow,
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.verified_user_outlined, color: colors.primary),
        title: Text(username.isEmpty ? '12306 账号' : username),
        subtitle: Text(
          '登录于 ${_formatDateTime(credentials.loginAt)} · $verificationStatus',
        ),
        trailing: TextButton.icon(
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('设置'),
        ),
      ),
    );
  }
}

class _InvoiceVerificationHint extends StatelessWidget {
  const _InvoiceVerificationHint({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard.filled(
      color: colors.surfaceContainerLow,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.receipt_long_outlined, color: colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('查看更多行程', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    '完成人证核验后，可加载近 180 天电子发票行程和近 1 年本人车票。',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.domain_verification_outlined),
                    label: const Text('去设置核验'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CredentialsProblem extends StatelessWidget {
  const _CredentialsProblem({
    required this.expired,
    required this.onOpenSettings,
  });

  final bool expired;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              expired ? Icons.lock_clock_outlined : Icons.lock_outline,
              size: 48,
              color: colors.outline,
            ),
            const SizedBox(height: 12),
            Text(
              expired ? '登录凭证已失效' : '尚未配置 12306 登录凭证',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              expired ? '请前往设置重新登录 12306' : '在设置中登录 12306 后，即可查询并导入车票',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('去设置'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
