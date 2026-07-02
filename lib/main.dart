import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:health/health.dart';

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
          seedColor: const Color(0xFF167A5B),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: const CardThemeData(
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
  int _rangeDays = 30;
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

    final endTime = DateTime.now();
    final startTime = endTime.subtract(Duration(days: _rangeDays));
    final types = _iosHealthDataTypes
        .where(_health.isDataTypeAvailable)
        .toList();

    try {
      await _health.configure();
      _authorized = await _health.requestAuthorization(
        types,
        permissions: List.filled(types.length, HealthDataAccess.READ),
      );

      final results = <HealthTypeResult>[];
      for (final type in types) {
        try {
          final points = await _health.getHealthDataFromTypes(
            types: [type],
            startTime: startTime,
            endTime: endTime,
          );
          points.sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
          results.add(HealthTypeResult(type: type, points: points));
        } catch (error) {
          results.add(HealthTypeResult(type: type, error: error.toString()));
        }
      }

      results.sort((a, b) => a.type.label.compareTo(b.type.label));

      setState(() {
        _results = results;
        _lastUpdated = DateTime.now();
        _message = _authorized
            ? null
            : 'HealthKit không cấp quyền đọc. Hãy kiểm tra quyền của app trong Apple Health.';
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalPoints = _results.fold<int>(
      0,
      (sum, result) => sum + result.points.length,
    );
    final filledTypes = _results
        .where((result) => result.points.isNotEmpty)
        .length;
    final failedTypes = _results.where((result) => result.error != null).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apple Health'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Khoảng thời gian',
            initialValue: _rangeDays,
            icon: const Icon(Icons.date_range_rounded),
            onSelected: (days) {
              setState(() {
                _rangeDays = days;
              });
              _loadHealthData();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 1, child: Text('24 giờ')),
              PopupMenuItem(value: 7, child: Text('7 ngày')),
              PopupMenuItem(value: 30, child: Text('30 ngày')),
              PopupMenuItem(value: 365, child: Text('1 năm')),
            ],
          ),
          IconButton(
            tooltip: 'Tải lại',
            onPressed: _isLoading ? null : _loadHealthData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadHealthData,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _SummaryPanel(
                isLoading: _isLoading,
                authorized: _authorized,
                rangeDays: _rangeDays,
                totalPoints: totalPoints,
                filledTypes: filledTypes,
                failedTypes: failedTypes,
                lastUpdated: _lastUpdated,
                message: _message,
              ),
              const SizedBox(height: 12),
              if (_isLoading && _results.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_results.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Center(
                    child: Text(
                      'Chưa có dữ liệu để hiển thị.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              else
                ..._results.map(
                  (result) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: HealthTypeCard(result: result),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.isLoading,
    required this.authorized,
    required this.rangeDays,
    required this.totalPoints,
    required this.filledTypes,
    required this.failedTypes,
    required this.lastUpdated,
    required this.message,
  });

  final bool isLoading;
  final bool authorized;
  final int rangeDays;
  final int totalPoints;
  final int filledTypes;
  final int failedTypes;
  final DateTime? lastUpdated;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  authorized
                      ? Icons.verified_rounded
                      : Icons.health_and_safety_rounded,
                  color: authorized
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isLoading
                        ? 'Đang đọc Apple Health...'
                        : 'Dữ liệu Apple Health',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                  icon: Icons.schedule_rounded,
                  label: '$rangeDays ngày',
                ),
                _MetricChip(
                  icon: Icons.dataset_rounded,
                  label: '$totalPoints bản ghi',
                ),
                _MetricChip(
                  icon: Icons.check_circle_rounded,
                  label: '$filledTypes loại có dữ liệu',
                ),
                _MetricChip(
                  icon: Icons.error_outline_rounded,
                  label: '$failedTypes lỗi',
                ),
              ],
            ),
            if (lastUpdated != null) ...[
              const SizedBox(height: 12),
              Text(
                'Cập nhật: ${lastUpdated!.formatted}',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(message!, style: TextStyle(color: colorScheme.error)),
            ],
            if (isLoading) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class HealthTypeCard extends StatelessWidget {
  const HealthTypeCard({super.key, required this.result});

  final HealthTypeResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final latest = result.points.firstOrNull;

    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          result.type.label,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            result.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: _StatusBadge(result: result),
        children: [
          if (result.error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                result.error!,
                style: TextStyle(color: colorScheme.error),
              ),
            )
          else if (latest == null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Không có bản ghi trong khoảng đã chọn.',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          else ...[
            _PointDetail(point: latest, title: 'Mới nhất'),
            if (result.points.length > 1) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Các bản ghi gần đây',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              ...result.points
                  .skip(1)
                  .take(9)
                  .map(
                    (point) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PointRow(point: point),
                    ),
                  ),
              if (result.points.length > 10)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '+${result.points.length - 10} bản ghi khác',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.result});

  final HealthTypeResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasError = result.error != null;
    final hasData = result.points.isNotEmpty;

    return Container(
      constraints: const BoxConstraints(minWidth: 46),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: hasError
            ? colorScheme.errorContainer
            : hasData
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        hasError ? 'Lỗi' : '${result.points.length}',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: hasError
              ? colorScheme.onErrorContainer
              : hasData
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PointRow extends StatelessWidget {
  const _PointRow({required this.point});

  final HealthDataPoint point;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              point.displayValue,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            point.dateFrom.formatted,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PointDetail extends StatelessWidget {
  const _PointDetail({required this.point, required this.title});

  final HealthDataPoint point;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _InfoLine(label: 'Giá trị', value: point.displayValue),
          _InfoLine(
            label: 'Thời gian',
            value: '${point.dateFrom.formatted} - ${point.dateTo.formatted}',
          ),
          _InfoLine(label: 'Nguồn', value: point.sourceName),
          _InfoLine(
            label: 'Thiết bị',
            value: point.deviceModel ?? point.sourceDeviceId,
          ),
          _InfoLine(label: 'Cách ghi', value: point.recordingMethod.name),
          _InfoLine(
            label: 'UUID',
            value: point.uuid.isEmpty ? '-' : point.uuid,
          ),
          const SizedBox(height: 8),
          Text(
            const JsonEncoder.withIndent('  ').convert(point.toJson()),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: SelectableText(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}

class HealthTypeResult {
  HealthTypeResult({required this.type, this.points = const [], this.error});

  final HealthDataType type;
  final List<HealthDataPoint> points;
  final String? error;

  String get subtitle {
    if (error != null) {
      return error!;
    }
    if (points.isEmpty) {
      return '0 bản ghi';
    }

    final latest = points.first;
    return '${points.length} bản ghi · ${latest.displayValue} · ${latest.dateFrom.formatted}';
  }
}

extension on HealthDataPoint {
  String get displayValue {
    if (value is NumericHealthValue) {
      final numericValue = (value as NumericHealthValue).numericValue;
      return '${numericValue.clean} ${unit.name}';
    }

    return '${value.toString().replaceAll('\n', ' ')} ${unit.name}';
  }
}

extension on num {
  String get clean {
    if (this is int || this == roundToDouble()) {
      return toInt().toString();
    }
    return toStringAsFixed(2);
  }
}

extension on DateTime {
  String get formatted {
    final local = toLocal();
    return '${local.day.twoDigits}/${local.month.twoDigits}/${local.year} '
        '${local.hour.twoDigits}:${local.minute.twoDigits}';
  }
}

extension on int {
  String get twoDigits => toString().padLeft(2, '0');
}

extension on HealthDataType {
  String get label {
    final words = name
        .split('_')
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0]}${word.substring(1).toLowerCase()}',
        );
    return words.join(' ');
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
  HealthDataType.FLIGHTS_CLIMBED,
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
  HealthDataType.BIRTH_DATE,
  HealthDataType.MENSTRUATION_FLOW,
  HealthDataType.WATER_TEMPERATURE,
  HealthDataType.UNDERWATER_DEPTH,
  HealthDataType.UV_INDEX,
  HealthDataType.SLEEP_WRIST_TEMPERATURE,
];
