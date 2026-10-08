import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../international/language_controller.dart';
import 'odometer_text_recognition_engine.dart';
import 'vehicle_driver_meter_input.dart';
import 'vehicle_driver_meter_repository.dart';

String _label(String ja, String en) => SkoLanguageController.isEnglish ? en : ja;
String _km(Object? value) => value is num ? value.toStringAsFixed(1) : value?.toString() ?? '—';

/// Hidden unless exact company capability and driver ownership are confirmed.
class VehicleDriverMeterEntry extends StatefulWidget {
  const VehicleDriverMeterEntry({super.key, required this.sourceClockInId, this.expectedWorkDate,
    this.expectedSiteId, this.expectedRouteId, this.requireDestinationMatch = false, this.repository});
  final String sourceClockInId;
  final String? expectedWorkDate;
  final String? expectedSiteId;
  final String? expectedRouteId;
  final bool requireDestinationMatch;
  final VehicleDriverMeterRepository? repository;
  @override
  State<VehicleDriverMeterEntry> createState() => _VehicleDriverMeterEntryState();
}

class _VehicleDriverMeterEntryState extends State<VehicleDriverMeterEntry> {
  VehicleDriverMeterRepository? _repository;
  VehicleDriverMeterContext? _context;
  int _generation = 0;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void didUpdateWidget(covariant VehicleDriverMeterEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceClockInId != widget.sourceClockInId || oldWidget.expectedWorkDate != widget.expectedWorkDate ||
        oldWidget.expectedSiteId != widget.expectedSiteId || oldWidget.expectedRouteId != widget.expectedRouteId ||
        oldWidget.requireDestinationMatch != widget.requireDestinationMatch || oldWidget.repository != widget.repository) _load();
  }
  Future<void> _load() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() => _context = null);
    }
    _repository = widget.repository ?? VehicleDriverMeterRepository.maybeCreate();
    VehicleDriverMeterContext? value;
    try { value = await _repository?.load(widget.sourceClockInId); } catch (_) { value = null; }
    if (widget.expectedWorkDate != null && value?.workDate != widget.expectedWorkDate) {
      value = null;
    }
    if (widget.requireDestinationMatch && (value?.siteId != widget.expectedSiteId || value?.routeId != widget.expectedRouteId)) {
      value = null;
    }
    if (mounted && generation == _generation) {
      setState(() => _context = value);
    }
  }
  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final value = _context;
    if (value == null) {
      return const SizedBox.shrink();
    }
    return Card(child: ListTile(
      leading: const Icon(Icons.speed),
      title: Text(_label('運転手のメーター登録', 'Driver meter reading')),
      subtitle: Text(value.event == null
        ? _label('運転手本人が数値を確認して登録します', 'The driver checks and saves the reading')
        : '${_label('走行距離', 'Trip distance')}: ${_km(value.event!['distance_km'])} km'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => VehicleDriverMeterPage(
          sourceClockInId: value.sourceClockInId, repository: _repository,
        )));
        if (mounted) {
          await _load();
        }
      },
    ));
  }
}

class VehicleDriverMeterPage extends StatefulWidget {
  const VehicleDriverMeterPage({super.key, required this.sourceClockInId, this.repository});
  final String sourceClockInId;
  final VehicleDriverMeterRepository? repository;
  @override
  State<VehicleDriverMeterPage> createState() => _VehicleDriverMeterPageState();
}

class _VehicleDriverMeterPageState extends State<VehicleDriverMeterPage> {
  final _current = TextEditingController();
  final _manual = TextEditingController();
  VehicleDriverMeterRepository? _repository;
  VehicleDriverMeterContext? _context;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _current.dispose(); _manual.dispose(); super.dispose(); }

  Future<void> _load() async {
    _repository = widget.repository ?? VehicleDriverMeterRepository.maybeCreate();
    VehicleDriverMeterContext? value;
    try { value = await _repository?.load(widget.sourceClockInId); } catch (_) { value = null; }
    if (!mounted) {
      return;
    }
    setState(() { _context = value; _loading = false; });
  }

  bool get _decreased {
    final previous = _context?.previousKm;
    final current = VehicleDriverMeterInput.parseKilometres(_current.text);
    return previous != null && current != null && current < previous;
  }

  Future<void> _message(String ja, String en) async {
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      content: Text(_label(ja, en)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(_label('確認', 'OK')))],
    ));
  }

  Future<void> _capture() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 92, maxWidth: 2400);
      if (image == null) {
        return;
      }
      final result = await const OdometerTextRecognitionEngine().recognizeImagePath(image.path);
      if (!mounted) {
        return;
      }
      final candidate = result.bestCandidate;
      if (candidate == null) {
        await _message('数値を読み取れませんでした。撮り直すか手入力してください。', 'No reading found. Retake the photo or enter the reading manually.');
      } else {
        setState(() => _current.text = candidate.toStringAsFixed(1));
        await _message('読取結果を表示しました。メーターと合っているか確認し、違う場合は修正してください。', 'Check the suggested reading against the meter and correct it before saving.');
      }
    } catch (_) {
      if (mounted) {
        await _message('写真を読み取れませんでした。撮り直すか手入力してください。', 'The photo could not be read. Retake it or enter the reading manually.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _save() async {
    final value = _context;
    final repository = _repository;
    if (_busy || value == null || repository == null || !value.canRecord) {
      return;
    }
    final input = VehicleDriverMeterInput.parse(previousKm: value.previousKm!,
      currentText: _current.text, manualDistanceText: _manual.text);
    if (input == null) {
      await _message('数値を確認してください。メーターが減った場合、その日の走行距離を手入力してください。', 'Check the reading. If the meter decreased, enter this trip’s distance manually.');
      return;
    }
    setState(() => _busy = true);
    try {
      final event = await repository.save(value, input);
      if (!mounted) {
        return;
      }
      await _message(event['baseline_decreased'] == true
        ? '登録しました。基準値変更の管理者への連絡は処理待ちです。'
        : 'メーターと走行距離を登録しました。', event['baseline_decreased'] == true
        ? 'Saved. The administrator warning about the changed baseline is pending.'
        : 'The meter reading and trip distance were saved.');
      if (mounted) {
        await _load();
      }
    } catch (_) {
      if (mounted) {
        await _message('登録できませんでした。再試行してください。後続の車両利用や登録済み数値の変更は、管理者へ修正を申請してください。',
          'Could not save. Retry, or request an administrator correction if a later trip exists or a saved reading needs changing.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final value = _context;
    final event = value?.event;
    return Scaffold(
      appBar: AppBar(title: Text(_label('メーター登録', 'Meter reading')), actions: [
        IconButton(icon: const Icon(Icons.help_outline), tooltip: _label('使い方', 'Help'), onPressed: () => _message(
          '運転手本人が退勤後に登録します。写真の読取値は必ず確認し、手直しできます。数値が減った場合はその日の走行距離を手入力します。登録済みの変更は管理者へ修正を申請してください。',
          'The driver saves the final reading after checkout. Always check the photo suggestion; you can edit it. If the meter decreased, enter the trip distance manually. Ask an administrator to correct saved readings.')),
      ]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : value == null
        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_label(
            'この勤務のメーター登録は利用できません。現在の入力方法をご利用ください。',
            'Meter registration is unavailable for this shift. Use the current input method.'))))
        : ListView(padding: const EdgeInsets.all(20), children: [
            Text('${_label('勤務日', 'Work date')}: ${value.workDate}'),
            if (value.vehicleLabel != null && value.vehicleLabel!.isNotEmpty) Text(value.vehicleLabel!),
            const SizedBox(height: 12),
            Text('${_label('前回距離', 'Previous reading')}: ${_km(event?['previous_km'] ?? value.previousKm)} km'),
            if (event != null) ...[
              Text('${_label('今回距離', 'Current reading')}: ${_km(event['current_km'])} km'),
              Text('${_label('当日の走行距離', 'Trip distance')}: ${_km(event['distance_km'])} km'),
              const SizedBox(height: 12), Text(_label('登録済みです。変更は管理者へ修正を申請してください。', 'Saved. Request an administrator correction to change it.')),
            ] else if (!value.canRecord) ...[
              const SizedBox(height: 12), Text(_label('退勤後に登録してください。基準値がない場合は管理者へ確認してください。', 'Save after checkout. Ask your administrator if the previous reading is unavailable.')),
            ] else ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: _busy ? null : _capture, icon: const Icon(Icons.camera_alt_outlined), label: Text(_label('写真から読み取る', 'Read from photo'))),
              TextField(controller: _current, enabled: !_busy, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: _label('今回のメーター値', 'Current meter reading'), suffixText: 'km')),
              if (_decreased) ...[
                const SizedBox(height: 12), Text(_label('メーター数値が減っています。その日の走行距離を手入力してください。', 'The meter decreased. Enter this trip’s distance manually.')),
                TextField(controller: _manual, enabled: !_busy, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: _label('当日の走行距離（必須）', 'Trip distance (required)'), suffixText: 'km')),
              ],
              const SizedBox(height: 20), FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? _label('登録中…', 'Saving…') : _label('確認して登録', 'Check and save'))),
            ],
          ]),
    );
  }
}
