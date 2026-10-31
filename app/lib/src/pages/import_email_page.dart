import 'package:flutter/material.dart';
import 'package:raillog/src/models/ticket_12306_order.dart';
import 'package:raillog/src/pages/settings/email_connection_settings_page.dart';
import 'package:raillog/src/services/mail_account_settings.dart';
import 'package:raillog/src/services/mail_import_service.dart';
import 'package:raillog/src/services/ticket_order_confirmation.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:raillog/src/widgets/ticket_order_selection.dart';

class ImportEmailPage extends StatefulWidget {
  const ImportEmailPage({super.key, this.service});

  final MailImportService? service;

  @override
  State<ImportEmailPage> createState() => _ImportEmailPageState();
}

class _ImportEmailPageState extends State<ImportEmailPage> {
  late final MailImportService _service =
      widget.service ?? const MailImportService();
  MailAccountConfig? _config;
  List<Ticket12306Order> _orders = const [];
  final Set<String> _selectedKeys = {};
  final Set<String> _importedKeys = {};
  bool _loadingConfig = true;
  bool _loadingTickets = false;
  bool _importing = false;
  int? _preparingPosition;
  String? _message;
  bool _messageIsError = false;

  bool get _isConfigured => _config?.isComplete ?? false;

  List<Ticket12306Order> get _selectableOrders => _orders
      .where(
        (order) => order.canImport && !_importedKeys.contains(order.dedupKey),
      )
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await MailAccountSettings.load();
    if (!mounted) return;
    setState(() {
      _config = config;
      _loadingConfig = false;
    });
    if (_isConfigured) await _loadTickets();
  }

  /// 读取邮箱后直接解析全部 12306 邮件，页面只保留车票卡片。
  Future<void> _loadTickets() async {
    final config = _config;
    if (!_isConfigured || config == null || _loadingTickets) return;
    setState(() {
      _loadingTickets = true;
      _selectedKeys.clear();
      _message = null;
      _messageIsError = false;
    });
    try {
      final messages = await _service.listMessages(config);
      if (!mounted) return;
      if (messages.isEmpty) {
        setState(() {
          _orders = const [];
          _message = '近两年没有找到 12306 购票通知邮件';
        });
        return;
      }

      setState(() => _message = '正在解析 ${messages.length} 封 12306 邮件...');
      final batches = await _service.fetchTickets(config, messages);
      if (!mounted) return;

      final ordersByKey = <String, Ticket12306Order>{};
      for (final batch in batches) {
        for (final order in batch.orders) {
          // 同一张票可能同时出现在支付通知和退票/改签通知里；
          // 列表按时间倒序，保留较新的那封里的状态。
          ordersByKey.putIfAbsent(order.dedupKey, () => order);
        }
      }
      final orders = ordersByKey.values.toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));

      setState(() {
        _orders = orders;
        _messageIsError = false;
        _message = orders.isEmpty
            ? '已读取 ${messages.length} 封 12306 邮件，但没有解析出车票'
            : '已读取 ${messages.length} 封邮件，找到 ${orders.length} 张车票';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = '读取邮件失败：$error';
      });
    } finally {
      if (mounted) setState(() => _loadingTickets = false);
    }
  }

  Future<void> _openSettings() async {
    final previous = _config;
    await Navigator.of(context).push<void>(
      m3PageRoute(builder: (context) => const EmailConnectionSettingsPage()),
    );
    if (!mounted) return;
    final config = await MailAccountSettings.load();
    if (!mounted || _sameConfig(previous, config)) return;

    setState(() {
      _config = config;
      _loadingConfig = false;
      _orders = const [];
      _selectedKeys.clear();
      _importedKeys.clear();
      _message = null;
    });
    if (_isConfigured) await _loadTickets();
  }

  bool _sameConfig(MailAccountConfig? first, MailAccountConfig? second) {
    if (first == null || second == null) return first == second;
    return first.emailAddress == second.emailAddress &&
        first.password == second.password &&
        first.host == second.host &&
        first.port == second.port &&
        first.protocol == second.protocol &&
        first.useTls == second.useTls;
  }

  void _toggleOrder(Ticket12306Order order, bool? selected) {
    if (_loadingTickets ||
        !order.canImport ||
        _importedKeys.contains(order.dedupKey)) {
      return;
    }
    setState(() {
      if (selected == true) {
        _selectedKeys.add(order.dedupKey);
      } else {
        _selectedKeys.remove(order.dedupKey);
      }
    });
  }

  void _toggleAll(bool? selected) {
    if (_loadingTickets) return;
    setState(() {
      _selectedKeys.clear();
      if (selected == true) {
        _selectedKeys.addAll(_selectableOrders.map((order) => order.dedupKey));
      }
    });
  }

  Future<void> _importSelected() async {
    if (_importing || _loadingTickets) return;
    final selected = _orders
        .where((order) => _selectedKeys.contains(order.dedupKey))
        .toList(growable: false);
    if (selected.isEmpty) return;

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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width > 880
        ? (width - AppLayout.detailMaxWidth) / 2
        : AppSpacing.lg;
    final selectable = _selectableOrders;
    final allSelected =
        selectable.isNotEmpty &&
        selectable.every((order) => _selectedKeys.contains(order.dedupKey));

    return Scaffold(
      appBar: AppBar(title: const Text('从邮箱导入'), scrolledUnderElevation: 0),
      body: _loadingConfig
          ? const Center(child: CircularProgressIndicator())
          : !_isConfigured
          ? _NotConfigured(onOpenSettings: _openSettings)
          : RefreshIndicator(
              onRefresh: _loadTickets,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  16,
                  horizontalPadding,
                  112,
                ),
                children: [
                  _AccountCard(config: _config!, onOpenSettings: _openSettings),
                  const SizedBox(height: 20),
                  TicketImportStepHeader(
                    step: 1,
                    icon: Icons.train_outlined,
                    title: '选择待导入车票',
                    trailing: IconButton.filledTonal(
                      tooltip: '重新读取',
                      onPressed: _loadingTickets || _importing
                          ? null
                          : _loadTickets,
                      icon: _loadingTickets
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '读取近两年的 12306 通知邮件并自动解析车票。'
                    '勾选后逐条确认导入，不会自动写入。',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  if (_message != null) ...[
                    TicketImportMessageBanner(
                      message: _message!,
                      isError: _messageIsError,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (selectable.isNotEmpty) ...[
                    TicketOrderSelectionToolbar(
                      selectedCount: _selectedKeys.length,
                      selectableCount: selectable.length,
                      allSelected: allSelected,
                      enabled: !_importing && !_loadingTickets,
                      onToggleAll: _toggleAll,
                    ),
                  ],
                  for (final order in _orders) ...[
                    TicketOrderSelectionTile(
                      order: order,
                      selected: _selectedKeys.contains(order.dedupKey),
                      imported: _importedKeys.contains(order.dedupKey),
                      enabled: !_importing && !_loadingTickets,
                      hideStatusWhenImportable: true,
                      onChanged: order.canImport
                          ? (value) => _toggleOrder(order, value)
                          : null,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_loadingTickets)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (_orders.isEmpty && !_loadingTickets)
                    TicketImportEmptyState(
                      title: '暂无可导入车票',
                      hint: '仅读取近两年内 12306 发件人或带转发标记的通知邮件',
                      actionLabel: '重新读取',
                      onAction: _loadTickets,
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
  const _AccountCard({required this.config, required this.onOpenSettings});

  final MailAccountConfig config;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard.filled(
      color: colors.surfaceContainerLow,
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.mark_email_read_outlined, color: colors.primary),
        title: Text(config.emailAddress),
        subtitle: Text(
          '${config.protocol.label} · ${config.host}:${config.port}',
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

class _NotConfigured extends StatelessWidget {
  const _NotConfigured({required this.onOpenSettings});

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
            Icon(Icons.alternate_email, size: 48, color: colors.outline),
            const SizedBox(height: 12),
            Text(
              '尚未配置邮箱连接',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              '配置邮箱服务器与授权码 / 应用密码后，即可读取 12306 购票通知',
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
