import 'dart:io';

import 'package:flutter/material.dart';
import 'package:health/health.dart';

const _healthRed = Color(0xFFFF2D55);
const _iosBackground = Color(0xFFF5F5F7);

void main() {
  runApp(const AppleHealthTestApp());
}

class AppleHealthTestApp extends StatelessWidget {
  const AppleHealthTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Apple Health Test',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _healthRed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: _iosBackground,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: _iosBackground,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: const HealthDashboardScreen(),
    );
  }
}

class HealthDashboardScreen extends StatefulWidget {
  const HealthDashboardScreen({super.key});

  @override
  State<HealthDashboardScreen> createState() => _HealthDashboardScreenState();
}

class _HealthDashboardScreenState extends State<HealthDashboardScreen> {
  final Health _health = Health();

  bool _isLoading = false;
  bool _authorized = false;
  bool _configured = false;
  bool _requestedAuthorization = false;
  DateTime _selectedDate = DateTime.now().dateOnly;
  DateTime? _lastUpdated;
  String? _message;
  List<HealthTypeResult> _results = [];

  @override
  void initState() {
    super.initState();
    _loadHealthData();
  }

  Future<void> _loadHealthData() async {
    if (!Platform.isIOS) {
      setState(() {
        _message = 'Apple Health chỉ chạy trên iPhone/iPad có HealthKit.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    final now = DateTime.now();
    final startTime = _selectedDate.dateOnly;
    final endTime = _isSameDay(_selectedDate, now)
        ? now
        : startTime
              .add(const Duration(days: 1))
              .subtract(const Duration(milliseconds: 1));
    final types = _iosHealthDataTypes
        .where((type) => _health.isDataTypeAvailable(type))
        .where((type) => !_hiddenHealthDataTypes.contains(type))
        .toList();

    try {
      await _ensureHealthReady(types);

      final results = <HealthTypeResult>[];
      for (final type in types) {
        try {
          final queryStartTime = type.isSleepType
              ? startTime.subtract(const Duration(hours: 18))
              : startTime;
          final points = await _health.getHealthDataFromTypes(
            types: [type],
            startTime: queryStartTime,
            endTime: endTime,
          );
          if (type.isSleepType) {
            points.removeWhere((point) => !point.belongsToSleepDay(startTime));
          }
          points.sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
          results.add(HealthTypeResult(type: type, points: points));
        } catch (error) {
          results.add(HealthTypeResult(type: type, error: error.toString()));
        }
      }

      results.sort((a, b) {
        final priority = a.type.priority.compareTo(b.type.priority);
        if (priority != 0) return priority;
        return a.type.title.compareTo(b.type.title);
      });

      setState(() {
        _results = results;
        _lastUpdated = DateTime.now();
        _message = _authorized
            ? null
            : 'HealthKit chưa cấp quyền đọc. Kiểm tra quyền của app trong Apple Health.';
      });
    } catch (error) {
      setState(() {
        _message = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _ensureHealthReady(List<HealthDataType> types) async {
    if (!_configured) {
      await _health.configure();
      _configured = true;
    }

    if (_requestedAuthorization) return;

    _authorized = await _health.requestAuthorization(
      types,
      permissions: List.filled(types.length, HealthDataAccess.READ),
    );
    _requestedAuthorization = true;
  }

  @override
  Widget build(BuildContext context) {
    final visibleResults = _results
        .where((result) => !_hiddenHealthDataTypes.contains(result.type))
        .where((result) => result.points.isNotEmpty)
        .toList();
    final resultByType = {
      for (final result in _results)
        if (!_hiddenHealthDataTypes.contains(result.type)) result.type: result,
    };
    final sleepResult = _combinedSleepResult(resultByType);
    final featuredResults = _featuredHealthDataTypes
        .map(
          (type) => type == HealthDataType.SLEEP_ASLEEP
              ? sleepResult
              : resultByType[type] ?? HealthTypeResult(type: type),
        )
        .toList();
    final totalPoints = visibleResults.fold<int>(
      0,
      (sum, result) => sum + result.points.length,
    );
    final failedTypes = _results.where((result) => result.error != null).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tổng quan',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            onPressed: _isLoading ? null : _loadHealthData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: _healthRed,
          onRefresh: _loadHealthData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    _HealthHeader(
                      isLoading: _isLoading,
                      authorized: _authorized,
                      selectedDate: _selectedDate,
                      dataTypes: visibleResults.length,
                      totalPoints: totalPoints,
                      failedTypes: failedTypes,
                      lastUpdated: _lastUpdated,
                      message: _message,
                      onPreviousDay: _goToPreviousDay,
                      onNextDay: _canGoToNextDay ? _goToNextDay : null,
                      onPickDate: _pickDate,
                    ),
                    const SizedBox(height: 18),
                    if (_isLoading && visibleResults.isEmpty)
                      const _LoadingState()
                    else ...[
                      _SectionTitle(
                        title: 'Ưu tiên',
                        subtitle: '6 chỉ số chính trong ngày đã chọn',
                      ),
                      const SizedBox(height: 10),
                      _FeaturedGrid(results: featuredResults),
                      const SizedBox(height: 22),
                      if (visibleResults.isEmpty)
                        const _EmptyState()
                      else ...[
                        _SectionTitle(
                          title: 'Tất cả dữ liệu',
                          subtitle: '${visibleResults.length} loại có dữ liệu',
                        ),
                        const SizedBox(height: 10),
                        ...visibleResults.map(
                          (result) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: HealthTypeCard(result: result),
                          ),
                        ),
                      ],
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canGoToNextDay => !_isSameDay(_selectedDate, DateTime.now());

  void _goToPreviousDay() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1)).dateOnly;
    });
    _loadHealthData();
  }

  void _goToNextDay() {
    if (!_canGoToNextDay) return;
    setState(() {
      _selectedDate = _selectedDate.add(const Duration(days: 1)).dateOnly;
    });
    _loadHealthData();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 10),
      lastDate: now.dateOnly,
      helpText: 'Chọn ngày',
      cancelText: 'Hủy',
      confirmText: 'Chọn',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: _healthRed),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate == null) return;
    setState(() {
      _selectedDate = pickedDate.dateOnly;
    });
    _loadHealthData();
  }

  HealthTypeResult _combinedSleepResult(
    Map<HealthDataType, HealthTypeResult> resultByType,
  ) {
    final points = <HealthDataPoint>[
      ...?resultByType[HealthDataType.SLEEP_ASLEEP]?.points,
      ...?resultByType[HealthDataType.SLEEP_LIGHT]?.points,
      ...?resultByType[HealthDataType.SLEEP_DEEP]?.points,
      ...?resultByType[HealthDataType.SLEEP_REM]?.points,
    ]..sort((a, b) => b.dateFrom.compareTo(a.dateFrom));

    return HealthTypeResult(type: HealthDataType.SLEEP_ASLEEP, points: points);
  }
}

class _HealthHeader extends StatelessWidget {
  const _HealthHeader({
    required this.isLoading,
    required this.authorized,
    required this.selectedDate,
    required this.dataTypes,
    required this.totalPoints,
    required this.failedTypes,
    required this.lastUpdated,
    required this.message,
    required this.onPreviousDay,
    required this.onNextDay,
    required this.onPickDate,
  });

  final bool isLoading;
  final bool authorized;
  final DateTime selectedDate;
  final int dataTypes;
  final int totalPoints;
  final int failedTypes;
  final DateTime? lastUpdated;
  final String? message;
  final VoidCallback onPreviousDay;
  final VoidCallback? onNextDay;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final statusText = isLoading
        ? 'Đang đồng bộ...'
        : lastUpdated == null
        ? 'Sẵn sàng đọc Apple Health'
        : 'Cập nhật ${lastUpdated!.relativeLabel}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: _healthRed,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Apple Health',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        statusText,
                        style: const TextStyle(
                          color: Color(0xFF6E6E73),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  authorized ? Icons.lock_open_rounded : Icons.lock_rounded,
                  color: authorized ? const Color(0xFF34C759) : Colors.black38,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DaySelector(
              selectedDate: selectedDate,
              onPreviousDay: onPreviousDay,
              onNextDay: onNextDay,
              onPickDate: onPickDate,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _HeaderMetric(
                    label: 'Loại dữ liệu',
                    value: '$dataTypes',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeaderMetric(label: 'Bản ghi', value: '$totalPoints'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeaderMetric(
                    label: 'Bị ẩn lỗi',
                    value: '$failedTypes',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Chỉ hiện các loại có bản ghi trong ngày đã chọn. Các mục chưa có dữ liệu hoặc chưa được cấp quyền sẽ được ẩn.',
              style: TextStyle(color: Color(0xFF6E6E73), fontSize: 12),
            ),
            if (message != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEDEF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  message!,
                  style: const TextStyle(color: _healthRed),
                ),
              ),
            ],
            if (isLoading) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(
                minHeight: 3,
                color: _healthRed,
                backgroundColor: Color(0xFFFFD7DF),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DaySelector extends StatelessWidget {
  const _DaySelector({
    required this.selectedDate,
    required this.onPreviousDay,
    required this.onNextDay,
    required this.onPickDate,
  });

  final DateTime selectedDate;
  final VoidCallback onPreviousDay;
  final VoidCallback? onNextDay;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDay(selectedDate, DateTime.now());

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Ngày trước',
            onPressed: onPreviousDay,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: onPickDate,
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
              label: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isToday ? 'Hôm nay' : selectedDate.weekdayLabel,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    selectedDate.shortDate,
                    style: const TextStyle(
                      color: Color(0xFF6E6E73),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              style: TextButton.styleFrom(
                foregroundColor: _healthRed,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Ngày sau',
            onPressed: onNextDay,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF6E6E73), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _FeaturedGrid extends StatelessWidget {
  const _FeaturedGrid({required this.results});

  final List<HealthTypeResult> results;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 560 ? 3 : 2;
        return GridView.builder(
          itemCount: results.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.08,
          ),
          itemBuilder: (context, index) {
            return _FeaturedMetricCard(result: results[index]);
          },
        );
      },
    );
  }
}

class _FeaturedMetricCard extends StatelessWidget {
  const _FeaturedMetricCard({required this.result});

  final HealthTypeResult result;

  @override
  Widget build(BuildContext context) {
    final style = result.type.style;
    final hasData = result.latest != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(style.icon, color: style.color, size: 22),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    result.type.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF6E6E73),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              hasData ? result.displayValue : '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasData ? style.color : const Color(0xFF8E8E93),
                fontSize: 30,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasData && result.unitLabel.isNotEmpty
                  ? result.unitLabel
                  : 'Chưa có dữ liệu',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF6E6E73)),
            ),
            const SizedBox(height: 8),
            Text(
              hasData ? result.caption : 'Ngày đã chọn',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class HealthTypeCard extends StatelessWidget {
  const HealthTypeCard({super.key, required this.result});

  final HealthTypeResult result;

  @override
  Widget build(BuildContext context) {
    final latest = result.latest;
    final style = result.type.style;
    if (latest == null) return const SizedBox.shrink();

    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: _MetricIcon(style: style),
          title: Text(
            result.type.title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${result.displayValue} ${result.unitLabel} · ${result.caption}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF6E6E73)),
          ),
          trailing: Text(
            '${result.points.length}',
            style: TextStyle(color: style.color, fontWeight: FontWeight.w800),
          ),
          children: [
            _CleanPointDetail(result: result),
            if (result.points.length > 1) ...[
              const SizedBox(height: 10),
              ...result.points
                  .skip(1)
                  .take(4)
                  .map(
                    (point) =>
                        _RecentPointRow(point: point, color: style.color),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricIcon extends StatelessWidget {
  const _MetricIcon({required this.style});

  final HealthMetricStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(style.icon, color: style.color, size: 20),
    );
  }
}

class _CleanPointDetail extends StatelessWidget {
  const _CleanPointDetail({required this.result});

  final HealthTypeResult result;

  @override
  Widget build(BuildContext context) {
    final point = result.latest;
    if (point == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailLine(
            label: result.type.shouldSumSamples ? 'Tổng' : 'Giá trị',
            value: '${result.displayValue} ${result.unitLabel}',
          ),
          _DetailLine(
            label: 'Thời gian',
            value: result.type.shouldSumSamples
                ? 'Tổng ${result.points.length} bản ghi trong ngày'
                : point.dateFrom.fullTime,
          ),
          if (point.sourceName.isNotEmpty)
            _DetailLine(label: 'Nguồn', value: point.sourceName),
          if (point.deviceModel != null && point.deviceModel!.isNotEmpty)
            _DetailLine(label: 'Thiết bị', value: point.deviceModel!),
        ],
      ),
    );
  }
}

class _RecentPointRow extends StatelessWidget {
  const _RecentPointRow({required this.point, required this.color});

  final HealthDataPoint point;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${point.primaryValue} ${point.unitLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            point.dateFrom.shortTime,
            style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF6E6E73)),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: Color(0xFF6E6E73))),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 60),
      child: Center(child: CircularProgressIndicator(color: _healthRed)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const _EmptyCard(
      text: 'Chưa có dữ liệu Apple Health trong khoảng thời gian đã chọn.',
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.favorite_border_rounded, color: _healthRed),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Color(0xFF6E6E73)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HealthTypeResult {
  HealthTypeResult({required this.type, this.points = const [], this.error});

  final HealthDataType type;
  final List<HealthDataPoint> points;
  final String? error;

  HealthDataPoint? get latest => points.isEmpty ? null : points.first;

  String get displayValue {
    if (type.shouldSumSamples) {
      if (type.prefersDurationLabel) {
        return normalizedTotalValue.durationLabel;
      }
      return normalizedTotalValue.clean;
    }
    return latest?.primaryValue ?? '-';
  }

  String get unitLabel {
    if (type.prefersDurationLabel) {
      return '';
    }
    if (type == HealthDataType.DISTANCE_WALKING_RUNNING &&
        latest?.unit == HealthDataUnit.METER) {
      return 'km';
    }
    return latest?.unitLabel ?? '';
  }

  String get caption {
    if (type.shouldSumSamples) {
      return 'Tổng trong ngày';
    }
    return latest?.dateFrom.shortTime ?? '';
  }

  num get totalNumericValue {
    return points.fold<num>(0, (sum, point) => sum + point.numericValue);
  }

  num get normalizedTotalValue {
    if (type == HealthDataType.DISTANCE_WALKING_RUNNING &&
        latest?.unit == HealthDataUnit.METER) {
      return totalNumericValue / 1000;
    }
    return totalNumericValue;
  }
}

class HealthMetricStyle {
  const HealthMetricStyle({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}

extension on HealthDataPoint {
  bool belongsToSleepDay(DateTime selectedDate) {
    return _isSameDay(dateTo, selectedDate) ||
        _isSameDay(dateFrom, selectedDate);
  }

  num get numericValue {
    if (value is NumericHealthValue) {
      return (value as NumericHealthValue).numericValue;
    }
    return 0;
  }

  String get primaryValue {
    if (value is NumericHealthValue) {
      if (unit == HealthDataUnit.PERCENT && numericValue.abs() <= 1) {
        return (numericValue * 100).clean;
      }
      return numericValue.clean;
    }

    final text = value.toString().replaceAll('\n', ' ');
    return text
        .replaceFirst(RegExp(r'^\w+HealthValue - ?'), '')
        .replaceFirst(RegExp(r'^\w+ - ?'), '')
        .trim();
  }

  String get unitLabel => unit.displayName;
}

extension on HealthDataUnit {
  String get displayName {
    return switch (this) {
      HealthDataUnit.COUNT => '',
      HealthDataUnit.METER => 'm',
      HealthDataUnit.GRAM => 'g',
      HealthDataUnit.KILOGRAM => 'kg',
      HealthDataUnit.POUND => 'lb',
      HealthDataUnit.CENTIMETER => 'cm',
      HealthDataUnit.INCH => 'in',
      HealthDataUnit.KILOCALORIE => 'kcal',
      HealthDataUnit.LITER => 'L',
      HealthDataUnit.MILLILITER => 'mL',
      HealthDataUnit.PERCENT => '%',
      HealthDataUnit.BEATS_PER_MINUTE => 'BPM',
      HealthDataUnit.RESPIRATIONS_PER_MINUTE => 'lần/phút',
      HealthDataUnit.MILLIMETER_OF_MERCURY => 'mmHg',
      HealthDataUnit.MINUTE => 'phút',
      HealthDataUnit.HOUR => 'giờ',
      HealthDataUnit.DEGREE_CELSIUS => '°C',
      _ => name.split('_').map((word) => word.toLowerCase()).join(' '),
    };
  }
}

extension on num {
  String get clean {
    if (this is int || this == roundToDouble()) {
      return toInt().toString();
    }
    if (abs() >= 100) {
      return toStringAsFixed(1);
    }
    return toStringAsFixed(2);
  }

  String get durationLabel {
    final totalMinutes = round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) {
      return '$minutes phút';
    }
    if (minutes == 0) {
      return '$hours giờ';
    }
    return '$hours giờ $minutes phút';
  }
}

extension on DateTime {
  DateTime get dateOnly => DateTime(year, month, day);

  String get weekdayLabel {
    return switch (weekday) {
      DateTime.monday => 'Thứ Hai',
      DateTime.tuesday => 'Thứ Ba',
      DateTime.wednesday => 'Thứ Tư',
      DateTime.thursday => 'Thứ Năm',
      DateTime.friday => 'Thứ Sáu',
      DateTime.saturday => 'Thứ Bảy',
      DateTime.sunday => 'Chủ Nhật',
      _ => '',
    };
  }

  String get shortTime {
    final local = toLocal();
    return '${local.day.twoDigits}/${local.month.twoDigits} ${local.hour.twoDigits}:${local.minute.twoDigits}';
  }

  String get shortDate {
    final local = toLocal();
    return '${local.day.twoDigits}/${local.month.twoDigits}/${local.year}';
  }

  String get fullTime {
    final local = toLocal();
    return '${local.day.twoDigits}/${local.month.twoDigits}/${local.year} '
        '${local.hour.twoDigits}:${local.minute.twoDigits}';
  }

  String get relativeLabel {
    final now = DateTime.now();
    final diff = now.difference(this);
    if (diff.inMinutes < 1) return 'vừa xong';
    if (diff.inHours < 1) return '${diff.inMinutes} phút trước';
    if (diff.inDays < 1) return '${diff.inHours} giờ trước';
    return shortTime;
  }
}

extension on int {
  String get twoDigits => toString().padLeft(2, '0');
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

extension on HealthDataType {
  bool get isSleepType {
    return switch (this) {
      HealthDataType.SLEEP_AWAKE ||
      HealthDataType.SLEEP_ASLEEP ||
      HealthDataType.SLEEP_IN_BED ||
      HealthDataType.SLEEP_LIGHT ||
      HealthDataType.SLEEP_DEEP ||
      HealthDataType.SLEEP_REM ||
      HealthDataType.SLEEP_WRIST_TEMPERATURE => true,
      _ => false,
    };
  }

  bool get shouldSumSamples {
    return switch (this) {
      HealthDataType.STEPS ||
      HealthDataType.ACTIVE_ENERGY_BURNED ||
      HealthDataType.BASAL_ENERGY_BURNED ||
      HealthDataType.DISTANCE_WALKING_RUNNING ||
      HealthDataType.EXERCISE_TIME ||
      HealthDataType.SLEEP_ASLEEP ||
      HealthDataType.SLEEP_AWAKE ||
      HealthDataType.SLEEP_IN_BED ||
      HealthDataType.SLEEP_LIGHT ||
      HealthDataType.SLEEP_DEEP ||
      HealthDataType.SLEEP_REM ||
      HealthDataType.APPLE_STAND_TIME ||
      HealthDataType.APPLE_MOVE_TIME ||
      HealthDataType.WATER ||
      HealthDataType.MINDFULNESS ||
      HealthDataType.DIETARY_CARBS_CONSUMED ||
      HealthDataType.DIETARY_CAFFEINE ||
      HealthDataType.DIETARY_ENERGY_CONSUMED ||
      HealthDataType.DIETARY_FATS_CONSUMED ||
      HealthDataType.DIETARY_PROTEIN_CONSUMED => true,
      _ => false,
    };
  }

  bool get prefersDurationLabel {
    return switch (this) {
      HealthDataType.SLEEP_ASLEEP ||
      HealthDataType.SLEEP_AWAKE ||
      HealthDataType.SLEEP_IN_BED ||
      HealthDataType.SLEEP_LIGHT ||
      HealthDataType.SLEEP_DEEP ||
      HealthDataType.SLEEP_REM => true,
      _ => false,
    };
  }

  String get title {
    return switch (this) {
      HealthDataType.STEPS => 'Số bước',
      HealthDataType.HEART_RATE => 'Nhịp tim',
      HealthDataType.ACTIVE_ENERGY_BURNED => 'Năng lượng hoạt động',
      HealthDataType.BASAL_ENERGY_BURNED => 'Năng lượng nghỉ',
      HealthDataType.DISTANCE_WALKING_RUNNING => 'Đi bộ & chạy',
      HealthDataType.EXERCISE_TIME => 'Thời gian tập luyện',
      HealthDataType.WORKOUT => 'Bài tập',
      HealthDataType.SLEEP_ASLEEP => 'Ngủ',
      HealthDataType.SLEEP_IN_BED => 'Trên giường',
      HealthDataType.SLEEP_AWAKE => 'Thức giấc',
      HealthDataType.SLEEP_LIGHT => 'Ngủ nông',
      HealthDataType.SLEEP_DEEP => 'Ngủ sâu',
      HealthDataType.SLEEP_REM => 'REM',
      HealthDataType.WEIGHT => 'Cân nặng',
      HealthDataType.HEIGHT => 'Chiều cao',
      HealthDataType.BODY_MASS_INDEX => 'BMI',
      HealthDataType.BODY_FAT_PERCENTAGE => 'Mỡ cơ thể',
      HealthDataType.LEAN_BODY_MASS => 'Khối lượng nạc',
      HealthDataType.BLOOD_OXYGEN => 'Oxy trong máu',
      HealthDataType.BLOOD_PRESSURE_SYSTOLIC => 'Huyết áp tâm thu',
      HealthDataType.BLOOD_PRESSURE_DIASTOLIC => 'Huyết áp tâm trương',
      HealthDataType.RESPIRATORY_RATE => 'Nhịp thở',
      HealthDataType.HEART_RATE_VARIABILITY_SDNN => 'HRV',
      HealthDataType.BODY_TEMPERATURE => 'Nhiệt độ cơ thể',
      HealthDataType.WATER => 'Nước',
      HealthDataType.WALKING_SPEED => 'Tốc độ đi bộ',
      HealthDataType.MINDFULNESS => 'Chánh niệm',
      HealthDataType.NUTRITION => 'Dinh dưỡng',
      HealthDataType.BLOOD_GLUCOSE => 'Đường huyết',
      HealthDataType.GENDER => 'Giới tính',
      HealthDataType.BLOOD_TYPE => 'Nhóm máu',
      _ =>
        name
            .split('_')
            .map(
              (word) => word.isEmpty
                  ? word
                  : '${word[0]}${word.substring(1).toLowerCase()}',
            )
            .join(' '),
    };
  }

  int get priority {
    return switch (this) {
      HealthDataType.STEPS => 0,
      HealthDataType.HEART_RATE => 1,
      HealthDataType.ACTIVE_ENERGY_BURNED => 2,
      HealthDataType.DISTANCE_WALKING_RUNNING => 3,
      HealthDataType.EXERCISE_TIME => 4,
      HealthDataType.SLEEP_ASLEEP => 5,
      HealthDataType.WEIGHT => 6,
      HealthDataType.BLOOD_OXYGEN => 7,
      HealthDataType.BLOOD_PRESSURE_SYSTOLIC => 8,
      HealthDataType.BLOOD_PRESSURE_DIASTOLIC => 9,
      HealthDataType.WORKOUT => 10,
      HealthDataType.RESPIRATORY_RATE => 11,
      HealthDataType.HEART_RATE_VARIABILITY_SDNN => 12,
      HealthDataType.WATER => 13,
      _ => 100,
    };
  }

  HealthMetricStyle get style {
    return switch (this) {
      HealthDataType.STEPS => const HealthMetricStyle(
        icon: Icons.directions_walk_rounded,
        color: Color(0xFFFF9500),
      ),
      HealthDataType.HEART_RATE ||
      HealthDataType.RESTING_HEART_RATE ||
      HealthDataType.HEART_RATE_VARIABILITY_SDNN => const HealthMetricStyle(
        icon: Icons.favorite_rounded,
        color: _healthRed,
      ),
      HealthDataType.ACTIVE_ENERGY_BURNED ||
      HealthDataType.BASAL_ENERGY_BURNED => const HealthMetricStyle(
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFF3B30),
      ),
      HealthDataType.EXERCISE_TIME ||
      HealthDataType.WORKOUT => const HealthMetricStyle(
        icon: Icons.fitness_center_rounded,
        color: Color(0xFF34C759),
      ),
      HealthDataType.DISTANCE_WALKING_RUNNING ||
      HealthDataType.WALKING_SPEED => const HealthMetricStyle(
        icon: Icons.route_rounded,
        color: Color(0xFF007AFF),
      ),
      HealthDataType.SLEEP_ASLEEP ||
      HealthDataType.SLEEP_IN_BED ||
      HealthDataType.SLEEP_AWAKE ||
      HealthDataType.SLEEP_LIGHT ||
      HealthDataType.SLEEP_DEEP ||
      HealthDataType.SLEEP_REM => const HealthMetricStyle(
        icon: Icons.bedtime_rounded,
        color: Color(0xFF5856D6),
      ),
      HealthDataType.WEIGHT ||
      HealthDataType.HEIGHT ||
      HealthDataType.BODY_MASS_INDEX ||
      HealthDataType.BODY_FAT_PERCENTAGE ||
      HealthDataType.LEAN_BODY_MASS => const HealthMetricStyle(
        icon: Icons.monitor_weight_rounded,
        color: Color(0xFF8E8E93),
      ),
      HealthDataType.BLOOD_OXYGEN ||
      HealthDataType.BLOOD_GLUCOSE ||
      HealthDataType.BLOOD_PRESSURE_DIASTOLIC ||
      HealthDataType.BLOOD_PRESSURE_SYSTOLIC ||
      HealthDataType.BLOOD_TYPE => const HealthMetricStyle(
        icon: Icons.bloodtype_rounded,
        color: Color(0xFFFF2D55),
      ),
      HealthDataType.RESPIRATORY_RATE => const HealthMetricStyle(
        icon: Icons.air_rounded,
        color: Color(0xFF5AC8FA),
      ),
      HealthDataType.WATER => const HealthMetricStyle(
        icon: Icons.water_drop_rounded,
        color: Color(0xFF0A84FF),
      ),
      HealthDataType.NUTRITION => const HealthMetricStyle(
        icon: Icons.restaurant_rounded,
        color: Color(0xFFFF9F0A),
      ),
      HealthDataType.MINDFULNESS => const HealthMetricStyle(
        icon: Icons.spa_rounded,
        color: Color(0xFF30D158),
      ),
      _ => const HealthMetricStyle(
        icon: Icons.health_and_safety_rounded,
        color: _healthRed,
      ),
    };
  }
}

const List<HealthDataType> _iosHealthDataTypes = [
  HealthDataType.ACTIVE_ENERGY_BURNED,
  HealthDataType.APPLE_STAND_TIME,
  HealthDataType.APPLE_STAND_HOUR,
  HealthDataType.APPLE_MOVE_TIME,
  HealthDataType.AUDIOGRAM,
  HealthDataType.BASAL_ENERGY_BURNED,
  HealthDataType.BLOOD_GLUCOSE,
  HealthDataType.BLOOD_OXYGEN,
  HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
  HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
  HealthDataType.BODY_FAT_PERCENTAGE,
  HealthDataType.BODY_MASS_INDEX,
  HealthDataType.BODY_TEMPERATURE,
  HealthDataType.DIETARY_CARBS_CONSUMED,
  HealthDataType.DIETARY_CAFFEINE,
  HealthDataType.DIETARY_ENERGY_CONSUMED,
  HealthDataType.DIETARY_FATS_CONSUMED,
  HealthDataType.DIETARY_PROTEIN_CONSUMED,
  HealthDataType.ELECTRODERMAL_ACTIVITY,
  HealthDataType.FORCED_EXPIRATORY_VOLUME,
  HealthDataType.HEART_RATE,
  HealthDataType.HEART_RATE_VARIABILITY_SDNN,
  HealthDataType.HEIGHT,
  HealthDataType.INSULIN_DELIVERY,
  HealthDataType.RESPIRATORY_RATE,
  HealthDataType.PERIPHERAL_PERFUSION_INDEX,
  HealthDataType.STEPS,
  HealthDataType.WAIST_CIRCUMFERENCE,
  HealthDataType.WEIGHT,
  HealthDataType.DISTANCE_WALKING_RUNNING,
  HealthDataType.WALKING_SPEED,
  HealthDataType.MINDFULNESS,
  HealthDataType.SLEEP_AWAKE,
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.SLEEP_IN_BED,
  HealthDataType.SLEEP_LIGHT,
  HealthDataType.SLEEP_DEEP,
  HealthDataType.SLEEP_REM,
  HealthDataType.WATER,
  HealthDataType.EXERCISE_TIME,
  HealthDataType.WORKOUT,
  HealthDataType.WORKOUT_ROUTE,
  HealthDataType.HEADACHE_NOT_PRESENT,
  HealthDataType.HEADACHE_MILD,
  HealthDataType.HEADACHE_MODERATE,
  HealthDataType.HEADACHE_SEVERE,
  HealthDataType.HEADACHE_UNSPECIFIED,
  HealthDataType.LEAN_BODY_MASS,
  HealthDataType.ELECTROCARDIOGRAM,
  HealthDataType.NUTRITION,
  HealthDataType.GENDER,
  HealthDataType.BLOOD_TYPE,
  HealthDataType.MENSTRUATION_FLOW,
  HealthDataType.WATER_TEMPERATURE,
  HealthDataType.UNDERWATER_DEPTH,
  HealthDataType.UV_INDEX,
  HealthDataType.SLEEP_WRIST_TEMPERATURE,
];

const List<HealthDataType> _featuredHealthDataTypes = [
  HealthDataType.STEPS,
  HealthDataType.ACTIVE_ENERGY_BURNED,
  HealthDataType.DISTANCE_WALKING_RUNNING,
  HealthDataType.BLOOD_OXYGEN,
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.HEART_RATE,
];

const Set<HealthDataType> _hiddenHealthDataTypes = {
  HealthDataType.BIRTH_DATE,
  HealthDataType.FLIGHTS_CLIMBED,
};
