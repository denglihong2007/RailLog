import 'package:flutter/material.dart';
import 'package:raillog/src/models/ticket_12306_order.dart';
import 'package:raillog/src/pages/settings/email_connection_settings_page.dart';
import 'package:raillog/src/services/mail_account_settings.dart';
import 'package:raillog/src/services/mail_import_service.dart';
import 'package:raillog/src/services/ticket_order_confirmation.dart';
import 'package:raillog/src/services/train_service.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

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

    final confirmed = await showTicketImportConfirmationDialog(
      context,
      selected.length,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _importing = true;
      _message = null;
      _messageIsError = false;
    });

    try {
      // 版本列表只取一次：service 内部有缓存，但空结果不缓存，
      // 逐单重复调会在服务端没配时刻表库时白白打一遍网络。
      final versions = await TrainService.fetchTimetableVersions();
      if (!mounted) return;

      final importedCount = await confirmTicketOrderImport(
        context: context,
        orders: selected,
        versions: versions,
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

      if (importedCount == selected.length) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已确认并导入 $importedCount 条行程')));
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _messageIsError = false;
        _message = importedCount == 0
            ? '已取消导入，车票仍保留在待确认列表中'
            : '已导入 $importedCount 条，其余车票尚未确认';
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
      appBar: AppBar(title: const Text('邮箱导入'), scrolledUnderElevation: 0),
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
                  _StepHeader(
                    step: 1,
                    icon: Icons.train_outlined,
                    title: '选择待导入车票',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '读取近两年的 12306 通知邮件并自动解析车票。'
                    '勾选后逐条确认导入，不会自动写入。',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  if (_message != null) ...[
                    _MessageBanner(
                      message: _message!,
                      isError: _messageIsError,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (selectable.isNotEmpty) ...[
                    Row(
                      children: [
                        Checkbox(
                          value: allSelected,
                          tristate: _selectedKeys.isNotEmpty && !allSelected,
                          onChanged: _importing || _loadingTickets
                              ? null
                              : _toggleAll,
                        ),
                        TextButton(
                          onPressed: _importing || _loadingTickets
                              ? null
                              : () => _toggleAll(!allSelected),
                          child: const Text('全选'),
                        ),
                        const Spacer(),
                        Text(
                          '已选择 ${_selectedKeys.length} / ${selectable.length}',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                  for (final order in _orders) ...[
                    _OrderTile(
                      order: order,
                      selected: _selectedKeys.contains(order.dedupKey),
                      imported: _importedKeys.contains(order.dedupKey),
                      enabled: !_importing && !_loadingTickets,
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
                    _EmptyTickets(onRefresh: _loadTickets),
                ],
              ),
            ),
      bottomNavigationBar: _selectedKeys.isEmpty
          ? null
          : Material(
              color: colors.surfaceContainer,
              child: SafeArea(
                minimum: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  12,
                  horizontalPadding,
                  12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _preparingPosition == null
                                ? '逐条确认后写入'
                                : '正在准备第 $_preparingPosition/${_selectedKeys.length} 条',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            '共 ${_selectedKeys.length} 条待确认',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _importing ? null : _importSelected,
                      icon: _importing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward),
                      label: const Text('开始确认'),
                    ),
                  ],
                ),
              ),
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

class _OrderTile extends StatelessWidget {
  const _OrderTile({
    required this.order,
    required this.selected,
    required this.imported,
    required this.enabled,
    required this.onChanged,
  });

  final Ticket12306Order order;
  final bool selected;
  final bool imported;
  final bool enabled;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // 「邮件导入」是来源说明，不必每张卡片都重复；只提示退票、改签这类异常。
    final status = imported
        ? '已导入'
        : order.canImport
        ? ''
        : order.statusText;
    final canToggle = enabled && !imported && onChanged != null;
    return AppCard.filled(
      color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
      padding: EdgeInsets.zero,
      onTap: canToggle ? () => onChanged!(!selected) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: selected, onChanged: canToggle ? onChanged : null),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        order.trainCode,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${order.fromStation} → ${order.toStation}',
                          style: Theme.of(context).textTheme.bodyLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      _OrderFact(
                        icon: Icons.schedule,
                        label: _formatDateTime(order.startTime),
                      ),
                      if (order.passengerName.isNotEmpty)
                        _OrderFact(
                          icon: Icons.person_outline,
                          label: order.passengerName,
                        ),
                      if (order.seatDisplay.isNotEmpty)
                        _OrderFact(
                          icon: Icons.event_seat_outlined,
                          label: order.seatDisplay,
                        ),
                      if (order.price > 0)
                        _OrderFact(
                          icon: Icons.payments_outlined,
                          label: '¥${_formatNumber(order.price)}',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (status.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                status,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: order.canImport ? colors.primary : colors.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderFact extends StatelessWidget {
  const _OrderFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: isError ? colors.errorContainer : colors.secondaryContainer,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              color: isError
                  ? colors.onErrorContainer
                  : colors.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isError
                      ? colors.onErrorContainer
                      : colors.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.step,
    required this.icon,
    required this.title,
  });

  final int step;
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox.square(
          dimension: 40,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: colors.onSecondaryContainer, size: 21),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '步骤 $step',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: colors.primary),
              ),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ],
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

class _EmptyTickets extends StatelessWidget {
  const _EmptyTickets({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.confirmation_number_outlined,
            size: 48,
            color: colors.outline,
          ),
          const SizedBox(height: 12),
          Text(
            '暂无可导入车票',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            '仅读取近两年内 12306 发件人或带转发标记的通知邮件',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('重新读取'),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _formatNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);
