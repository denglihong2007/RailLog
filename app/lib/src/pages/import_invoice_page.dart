import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:raillog/src/models/ticket_12306_order.dart';
import 'package:raillog/src/services/ticket_invoice_import_service.dart';
import 'package:raillog/src/services/ticket_order_confirmation.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/ticket_order_selection.dart';

class ImportInvoicePage extends StatefulWidget {
  const ImportInvoicePage({super.key});

  @override
  State<ImportInvoicePage> createState() => _ImportInvoicePageState();
}

class _ImportInvoicePageState extends State<ImportInvoicePage> {
  final Set<String> _selectedKeys = {};
  final Set<String> _importedKeys = {};
  List<Ticket12306Order> _orders = const [];
  List<String> _failures = const [];
  bool _isReading = false;
  bool _isImporting = false;
  int? _preparingPosition;
  String? _message;
  bool _messageIsError = false;

  bool get _isBusy => _isReading || _isImporting;

  // iOS 与 Web 不支持选择文件夹；Android 的 SAF 目录也拿不到稳定的文件路径。
  bool get _supportsFolderPick =>
      !kIsWeb &&
      const {
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }.contains(defaultTargetPlatform);

  List<Ticket12306Order> get _selectableOrders => _orders
      .where(
        (order) => order.canImport && !_importedKeys.contains(order.dedupKey),
      )
      .toList(growable: false);

  Future<void> _pickFiles() async {
    if (_isBusy) return;
    // iOS 只认 UTI，而 OFD 没有公开的 UTI，只能放开到 public.data；
    // 其他平台靠扩展名过滤，选错类型也会在解析时被拒绝。
    final typeGroup = XTypeGroup(
      label: '电子发票',
      extensions: const ['pdf', 'ofd'],
      mimeTypes: const ['application/pdf', 'application/octet-stream'],
      uniformTypeIdentifiers: defaultTargetPlatform == TargetPlatform.iOS
          ? const ['com.adobe.pdf', 'public.data']
          : const ['com.adobe.pdf'],
    );
    final List<XFile> selection;
    try {
      selection = await openFiles(acceptedTypeGroups: [typeGroup]);
    } catch (error) {
      if (mounted) {
        setState(() {
          _messageIsError = true;
          _message = '无法打开文件选择器：$error';
        });
      }
      return;
    }
    if (selection.isEmpty || !mounted) return;

    setState(() {
      _isReading = true;
      _message = null;
      _messageIsError = false;
    });
    try {
      final files = <InvoiceImportFile>[];
      for (final file in selection) {
        files.add(
          InvoiceImportFile(name: file.name, bytes: await file.readAsBytes()),
        );
      }
      if (!mounted) return;
      await _applyFiles(files);
    } catch (error) {
      if (mounted) {
        setState(() {
          _messageIsError = true;
          _message = '读取文件失败：$error';
        });
      }
    } finally {
      if (mounted) setState(() => _isReading = false);
    }
  }

  Future<void> _pickFolder() async {
    if (_isBusy) return;
    final String? path;
    try {
      path = await getDirectoryPath(confirmButtonText: '选择文件夹');
    } catch (error) {
      if (mounted) {
        setState(() {
          _messageIsError = true;
          _message = '当前平台不支持选择文件夹，请改用选择文件：$error';
        });
      }
      return;
    }
    if (path == null || !mounted) return;

    setState(() {
      _isReading = true;
      _message = null;
      _messageIsError = false;
    });
    try {
      final fileSet = await TicketInvoiceImportService.readDirectory(path);
      if (!mounted) return;
      if (fileSet.files.isEmpty) {
        setState(() {
          _messageIsError = true;
          _message = '该文件夹内没有 PDF / OFD 电子发票';
        });
        return;
      }
      await _applyFiles(fileSet.files, truncated: fileSet.truncated);
    } catch (error) {
      if (mounted) {
        setState(() {
          _messageIsError = true;
          _message = '读取文件夹失败：$error';
        });
      }
    } finally {
      if (mounted) setState(() => _isReading = false);
    }
  }

  Future<void> _applyFiles(
    List<InvoiceImportFile> files, {
    bool truncated = false,
  }) async {
    final batch = TicketInvoiceImportService.importFiles(files);
    if (!mounted) return;
    setState(() {
      _orders = batch.orders;
      _failures = batch.failures;
      _selectedKeys.clear();
      _importedKeys.clear();
      _messageIsError = batch.orders.isEmpty;
      _message = _describeBatch(batch, truncated);
    });

    // 只有一条可导入行程时跳过列表，直接进入逐条确认。
    final importable = batch.orders.where((order) => order.canImport).toList();
    if (importable.length == 1) {
      _selectedKeys.add(importable.single.dedupKey);
      await _startImport(importable);
    }
  }

  String _describeBatch(InvoiceImportBatch batch, bool truncated) {
    if (batch.orders.isEmpty) {
      return batch.failures.isEmpty ? '没有找到可导入的电子发票' : '没有从所选文件中解析出可导入行程';
    }
    final importableCount = batch.orders
        .where((order) => order.canImport)
        .length;
    final parts = ['已读取 ${batch.fileCount} 个文件，可导入 $importableCount 条行程'];
    if (batch.failures.isNotEmpty) {
      parts.add('${batch.failures.length} 个文件无法解析');
    }
    if (truncated) {
      parts.add('文件夹内文件较多，仅读取了前 ${batch.fileCount} 个');
    }
    return parts.join('；');
  }

  Future<void> _startImport(List<Ticket12306Order> orders) async {
    if (orders.isEmpty || _isImporting) return;

    setState(() {
      _isImporting = true;
      _message = null;
      _messageIsError = false;
    });
    try {
      final result = await runTicketImport(
        context: context,
        orders: orders,
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
        // 取消或部分导入后把未导入的重新勾上，方便直接重试。
        _selectedKeys.addAll(
          orders
              .where((order) => !_importedKeys.contains(order.dedupKey))
              .map((order) => order.dedupKey),
        );
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
    if (_isBusy) return;
    setState(() {
      _selectedKeys.clear();
      if (selected == true) {
        _selectedKeys.addAll(_selectableOrders.map((order) => order.dedupKey));
      }
    });
  }

  void _toggleOrder(Ticket12306Order order, bool? selected) {
    if (_isBusy || !order.canImport || _importedKeys.contains(order.dedupKey)) {
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

  Future<void> _showFailures() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.error_outline,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: const Text('无法解析的文件'),
        content: SizedBox(
          width: AppLayout.compactMaxWidth,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final failure in _failures)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SelectableText(failure),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width > 880
        ? (width - AppLayout.detailMaxWidth) / 2
        : AppSpacing.lg;
    final colors = Theme.of(context).colorScheme;
    final selectable = _selectableOrders;
    final allSelected =
        selectable.isNotEmpty &&
        selectable.every((order) => _selectedKeys.contains(order.dedupKey));
    final selectedOrders = _orders
        .where((order) => _selectedKeys.contains(order.dedupKey))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('从电子发票导入'), scrolledUnderElevation: 0),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          16,
          horizontalPadding,
          112,
        ),
        children: [
          _SourceCard(
            isBusy: _isBusy,
            canPickFolder: _supportsFolderPick,
            onPickFiles: _pickFiles,
            onPickFolder: _pickFolder,
          ),
          const SizedBox(height: 20),
          TicketImportStepHeader(
            step: 1,
            icon: Icons.train_outlined,
            title: '选择待导入车票',
            trailing: IconButton.filledTonal(
              tooltip: '重新选择',
              onPressed: _isBusy ? null : _pickFiles,
              icon: _isReading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '解析所选电子发票后勾选车票，逐条确认导入，不会自动写入。',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_isReading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          if (_message != null) ...[
            TicketImportMessageBanner(
              message: _message!,
              isError: _messageIsError,
            ),
            const SizedBox(height: 12),
          ],
          if (_failures.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _showFailures,
                icon: const Icon(Icons.error_outline, size: 18),
                label: Text('查看 ${_failures.length} 个无法解析的文件'),
              ),
            ),
            const SizedBox(height: 4),
          ],
          if (selectable.isNotEmpty) ...[
            TicketOrderSelectionToolbar(
              selectedCount: _selectedKeys.length,
              selectableCount: selectable.length,
              allSelected: allSelected,
              enabled: !_isBusy,
              onToggleAll: _toggleAll,
            ),
          ],
          for (final order in _orders) ...[
            TicketOrderSelectionTile(
              order: order,
              selected: _selectedKeys.contains(order.dedupKey),
              imported: _importedKeys.contains(order.dedupKey),
              enabled: !_isBusy,
              hideStatusWhenImportable: true,
              onChanged: order.canImport
                  ? (value) => _toggleOrder(order, value)
                  : null,
            ),
            const SizedBox(height: 8),
          ],
          if (_orders.isEmpty && !_isReading)
            TicketImportEmptyState(
              title: '暂无可导入车票',
              hint: '选择已下载的 PDF / OFD 电子发票，车次、站点、席别和票价会自动填入',
            ),
        ],
      ),
      bottomNavigationBar: selectedOrders.isEmpty
          ? null
          : TicketImportActionBar(
              selectedCount: selectedOrders.length,
              preparingPosition: _preparingPosition,
              isImporting: _isImporting,
              onStart: () => _startImport(selectedOrders),
              horizontalPadding: horizontalPadding,
            ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.isBusy,
    required this.canPickFolder,
    required this.onPickFiles,
    required this.onPickFolder,
  });

  final bool isBusy;
  final bool canPickFolder;
  final VoidCallback onPickFiles;
  final VoidCallback onPickFolder;

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
                  child: Text(
                    '选择铁路电子客票',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '支持从 12306 下载的电子发票 PDF / OFD 文件。'
              '可一次选择多个文件${canPickFolder ? '，或选择整个文件夹' : ''}；'
              '同一张发票的 PDF 与 OFD 只会导入一次。',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: isBusy ? null : onPickFiles,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('选择文件'),
                ),
                if (canPickFolder)
                  OutlinedButton.icon(
                    onPressed: isBusy ? null : onPickFolder,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('选择文件夹'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
