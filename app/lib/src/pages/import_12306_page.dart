import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:raillog/src/models/ticket_12306_order.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/pages/train_trip_form_page.dart';
import 'package:raillog/src/services/ticket_12306_service.dart';
import 'package:raillog/src/services/train_service.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

class Import12306Page extends StatefulWidget {
  const Import12306Page({super.key, this.service});

  final Ticket12306Service? service;

  @override
  State<Import12306Page> createState() => _Import12306PageState();
}

class _Import12306PageState extends State<Import12306Page> {
  late final Ticket12306Service _service =
      widget.service ?? Ticket12306Service();
  final Set<String> _selectedIds = {};
  final Set<String> _importedIds = {};
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
  bool _isQuerying = false;
  bool _isImporting = false;
  int? _preparingPosition;
  int _pollGeneration = 0;

  bool get _canQuery => _invoiceVerified && !_isFinalizingLogin && !_isQuerying;

  List<Ticket12306Order> get _selectableOrders => _orders
      .where((order) => order.canImport && !_importedIds.contains(order.id))
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
      _orders = const [];
      _selectedIds.clear();
      _importedIds.clear();
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
            await _startInvoiceVerification(generation);
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
        _qrMessage = '登录成功，正在准备电子发票访问核验';
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
        await _queryOrders();
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

  Future<void> _queryOrders() async {
    if (!_invoiceVerified) return;
    setState(() {
      _isQuerying = true;
      _message = null;
      _selectedIds.clear();
    });
    try {
      final orders = await _service.queryInvoiceTrips();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _messageIsError = false;
        _message = orders.isEmpty
            ? '近 180 天没有可导入行程'
            : '共查询到 ${orders.length} 张车票';
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

  Future<void> _importSelected() async {
    final selected = _orders
        .where((order) => _selectedIds.contains(order.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.fact_check_outlined),
        title: const Text('逐条确认行程'),
        content: Text(
          '接下来将依次确认 ${selected.length} 条行程，并自动补全担当公司、车型和经由线路。每次确认后保存当前一条。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _isImporting = true;
      _message = null;
    });

    var importedCount = 0;
    for (var index = 0; index < selected.length; index++) {
      if (!mounted) return;
      setState(() => _preparingPosition = index + 1);
      final order = selected[index];
      final prepared = await _prepareOrder(order);
      if (!mounted) return;
      setState(() => _preparingPosition = null);
      final saved = await Navigator.of(context).push<bool>(
        m3PageRoute(
          builder: (context) => TrainTripFormPage(
            trainNumber: order.trainCode,
            scheduleStops: prepared.stops,
            departureStopIndex: prepared.departureIndex,
            arrivalStopIndex: prepared.arrivalIndex,
            initialSeatType: order.seatType,
            initialSeatNumber: order.seatNumber,
            initialMileageKm: order.distance,
            initialPrice: order.price,
            initialNotes: order.statusText,
            reviewPosition: index + 1,
            reviewTotal: selected.length,
          ),
        ),
      );
      if (!mounted) return;
      if (saved != true) break;
      importedCount++;
      setState(() {
        _importedIds.add(order.id);
        _selectedIds.remove(order.id);
      });
    }

    if (!mounted) return;
    if (importedCount == selected.length) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已确认并导入 $importedCount 条行程')));
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _isImporting = false;
      _preparingPosition = null;
      _messageIsError = false;
      _message = importedCount == 0
          ? '已取消导入，订单仍保留在待确认列表中'
          : '已导入 $importedCount 条，其余订单尚未确认';
    });
  }

  Future<_PreparedOrder> _prepareOrder(Ticket12306Order order) async {
    final searchResults = await TrainService.searchTrains(
      order.trainCode,
      order.startTime,
    );
    final normalizedTrainNumber = _normalizeTrainNumber(order.trainCode);
    final matches = searchResults.where(
      (result) =>
          _normalizeTrainNumber(result.trainNumber) == normalizedTrainNumber,
    );
    final train = matches.firstOrNull ?? searchResults.firstOrNull;
    if (train != null) {
      final schedule = await TrainService.fetchTrainSchedule(
        train.trainNo,
        order.startTime,
      );
      final departureIndex = schedule.indexWhere(
        (stop) => _sameStation(stop.stationName, order.fromStation),
      );
      final arrivalIndex = schedule.indexWhere(
        (stop) => _sameStation(stop.stationName, order.toStation),
      );
      if (departureIndex >= 0 && arrivalIndex > departureIndex) {
        final resolved = TrainService.resolveScheduleDateTimes(
          schedule,
          order.startTime,
          departureIndex,
        ).toList();
        resolved[departureIndex] = resolved[departureIndex].copyWith(
          departureDateTime: order.startTime,
        );
        final arrivalTime =
            order.arriveTime ??
            resolved[arrivalIndex].arrivalDateTime ??
            resolved[arrivalIndex].departureDateTime ??
            order.startTime;
        resolved[arrivalIndex] = resolved[arrivalIndex].copyWith(
          arrivalDateTime: arrivalTime,
        );
        return _PreparedOrder(
          stops: resolved,
          departureIndex: departureIndex,
          arrivalIndex: arrivalIndex,
        );
      }
    }
    return _fallbackPreparedOrder(order);
  }

  _PreparedOrder _fallbackPreparedOrder(Ticket12306Order order) {
    final arrival = order.arriveTime ?? order.startTime;
    final dayDifference = DateTime(arrival.year, arrival.month, arrival.day)
        .difference(
          DateTime(
            order.startTime.year,
            order.startTime.month,
            order.startTime.day,
          ),
        )
        .inDays;
    return _PreparedOrder(
      stops: [
        TrainScheduleStop(
          stationName: order.fromStation,
          stationNo: '01',
          arriveTime: '--',
          startTime: _formatClock(order.startTime),
          runningTime: '00:00',
          arriveDay: '当日',
          arriveDayDifference: 0,
          departureDateTime: order.startTime,
          arrivalDateTime: order.startTime,
        ),
        TrainScheduleStop(
          stationName: order.toStation,
          stationNo: '02',
          arriveTime: _formatClock(arrival),
          startTime: '--',
          runningTime: '',
          arriveDay: dayDifference == 0 ? '当日' : '第${dayDifference + 1}日',
          arriveDayDifference: dayDifference,
          departureDateTime: arrival,
          arrivalDateTime: arrival,
        ),
      ],
      departureIndex: 0,
      arrivalIndex: 1,
    );
  }

  void _toggleAll(bool? selected) {
    setState(() {
      _selectedIds.clear();
      if (selected == true) {
        _selectedIds.addAll(_selectableOrders.map((order) => order.id));
      }
    });
  }

  void _toggleOrder(Ticket12306Order order, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedIds.add(order.id);
      } else {
        _selectedIds.remove(order.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width > 880 ? (width - 840) / 2 : 16.0;
    final selectable = _selectableOrders;
    final allSelected =
        selectable.isNotEmpty &&
        selectable.every((order) => _selectedIds.contains(order.id));
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      appBar: AppBar(title: const Text('12306 行程'), scrolledUnderElevation: 0),
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
              child: _StepHeader(
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
              child: _StepHeader(
                step: 2,
                icon: Icons.domain_verification_outlined,
                title: '核验电子发票访问',
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
                  ? const _PendingStepCard(message: '完成登录后进行二次核验')
                  : _invoiceVerified
                  ? const _CompletedStepCard(message: '电子发票访问核验通过')
                  : Column(
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
              child: Row(
                children: [
                  const Expanded(
                    child: _StepHeader(
                      step: 3,
                      icon: Icons.train_outlined,
                      title: '选择待导入行程',
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: '重新查询',
                    onPressed: _canQuery ? _queryOrders : null,
                    icon: _isQuerying
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
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
                child: Material(
                  color: _messageIsError
                      ? colors.errorContainer
                      : colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _messageIsError
                              ? Icons.error_outline
                              : Icons.info_outline,
                          color: _messageIsError
                              ? colors.onErrorContainer
                              : colors.onSecondaryContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _message!,
                            style: TextStyle(
                              color: _messageIsError
                                  ? colors.onErrorContainer
                                  : colors.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_orders.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Checkbox(
                      value: allSelected,
                      tristate: _selectedIds.isNotEmpty && !allSelected,
                      onChanged: _isImporting ? null : _toggleAll,
                    ),
                    TextButton(
                      onPressed: _isImporting
                          ? null
                          : () => _toggleAll(!allSelected),
                      child: const Text('全选'),
                    ),
                    const Spacer(),
                    Text(
                      '已选择 ${_selectedIds.length} / ${selectable.length}',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          if (_orders.isEmpty && !_isQuerying)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyOrders(isLoggedIn: _username != null),
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
                  return _OrderTile(
                    order: order,
                    selected: _selectedIds.contains(order.id),
                    imported: _importedIds.contains(order.id),
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
      bottomNavigationBar: _selectedIds.isEmpty
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
                                : '正在准备第 $_preparingPosition/${_selectedIds.length} 条',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            '共 ${_selectedIds.length} 条待确认',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _isImporting ? null : _importSelected,
                      icon: _isImporting
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

class _CompletedStepCard extends StatelessWidget {
  const _CompletedStepCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colors.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Icon(Icons.check_circle_outline, color: colors.primary),
        title: Text(message),
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
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colors.tertiaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    return Card.filled(
      margin: EdgeInsets.zero,
      color: isLoggedIn ? colors.primaryContainer : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                      borderRadius: BorderRadius.circular(8),
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

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders({required this.isLoggedIn});

  final bool isLoggedIn;

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
              isLoggedIn ? Icons.route_outlined : Icons.lock_outline,
              size: 48,
              color: colors.outline,
            ),
            const SizedBox(height: 12),
            Text(
              isLoggedIn ? '近 180 天暂无行程' : '登录并核验后显示近 180 天行程',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
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
    final status = imported ? '已导入' : order.statusText;
    final canToggle = enabled && !imported && onChanged != null;
    return Material(
      color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canToggle ? () => onChanged!(!selected) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                onChanged: canToggle ? onChanged : null,
              ),
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

class _PreparedOrder {
  const _PreparedOrder({
    required this.stops,
    required this.departureIndex,
    required this.arrivalIndex,
  });

  final List<TrainScheduleStop> stops;
  final int departureIndex;
  final int arrivalIndex;
}

Uint8List _decodeQrImage(String source) {
  final comma = source.indexOf(',');
  return base64Decode(comma >= 0 ? source.substring(comma + 1) : source);
}

String _formatDateTime(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _formatClock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _normalizeTrainNumber(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[\s次]'), '');

bool _sameStation(String first, String second) =>
    _normalizeStation(first) == _normalizeStation(second);

String _normalizeStation(String value) =>
    value.trim().replaceFirst(RegExp(r'站$'), '');

String _formatNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);
