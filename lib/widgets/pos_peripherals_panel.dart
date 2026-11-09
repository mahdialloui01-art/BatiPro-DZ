import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/app_storage.dart';
import '../data/pos_drawer_service.dart';

/// Windows POS device setup. USB HID barcode scanners act as keyboards.
class PosPeripheralsPanel extends StatefulWidget {
  const PosPeripheralsPanel({super.key});

  @override
  State<PosPeripheralsPanel> createState() => _PosPeripheralsPanelState();
}

class _PosPeripheralsPanelState extends State<PosPeripheralsPanel> {
  static const _printerKey = 'batipro_pos_printer_name';
  static const _modeKey = PosDrawerService.modeKey;
  static const _enabledKey = PosDrawerService.enabledKey;
  static const _pinKey = PosDrawerService.pinKey;
  static const _pulseOnKey = PosDrawerService.pulseOnKey;
  static const _pulseOffKey = PosDrawerService.pulseOffKey;
  static const _portKey = PosDrawerService.portKey;
  static const _baudKey = PosDrawerService.baudKey;
  static const _usbHexKey = PosDrawerService.usbCommandKey;

  final _hexController = TextEditingController();
  List<String> _printers = [];
  List<String> _ports = [];
  String? _selectedPrinter;
  String? _selectedPort;
  String _mode = 'printer';
  String _pin = '2';
  String _baud = '9600';
  String _pulseOn = '25';
  String _pulseOff = '250';
  bool _autoOpen = false;
  bool _loading = true;
  bool _busy = false;
  String _printerStatus = 'لم يتم فحص الأجهزة بعد';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final storage = await AppStorage.getInstance();
    _selectedPrinter = storage.getString(_printerKey);
    _mode = storage.getString(_modeKey) ?? 'printer';
    _autoOpen = storage.getString(_enabledKey) == 'true';
    _pin = storage.getString(_pinKey) ?? '2';
    _pulseOn = storage.getString(_pulseOnKey) ?? '25';
    _pulseOff = storage.getString(_pulseOffKey) ?? '250';
    _selectedPort = storage.getString(_portKey);
    _baud = storage.getString(_baudKey) ?? '9600';
    _hexController.text = storage.getString(_usbHexKey) ?? '';
    await _refreshDevices();
    if (mounted) setState(() => _loading = false);
  }

  Future<String> _runPowerShell(String script) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('إدارة أجهزة نقاط البيع متاحة في نسخة Windows فقط.');
    }
    final encoded = base64Encode(utf8.encode(script));
    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw Exception((result.stderr.toString().trim().isNotEmpty
          ? result.stderr
          : result.stdout).toString().trim());
    }
    return result.stdout.toString().trim();
  }

  Future<void> _refreshDevices() async {
    if (!Platform.isWindows) {
      if (mounted) setState(() => _printerStatus = 'هذا القسم مخصص لنظام Windows.');
      return;
    }
    try {
      final results = await Future.wait([
        _runPowerShell(
          r'$items = Get-CimInstance Win32_Printer | Select-Object -ExpandProperty Name; '
          r'ConvertTo-Json -InputObject @($items) -Compress',
        ),
        PosDrawerService.listComPorts(),
      ]);
      final decoded = jsonDecode(results[0] as String);
      final printers = decoded is List
          ? decoded.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : decoded == null ? <String>[] : [decoded.toString()];
      final storage = await AppStorage.getInstance();
      final savedPrinter = storage.getString(_printerKey);
      final ports = results[1] as List<String>;
      if (!mounted) return;
      setState(() {
        _printers = printers;
        _ports = ports;
        _selectedPrinter = printers.contains(savedPrinter)
            ? savedPrinter
            : (printers.isNotEmpty ? printers.first : null);
        if (!_ports.contains(_selectedPort)) {
          _selectedPort = _ports.isNotEmpty ? _ports.first : null;
        }
        _printerStatus = 'الطابعات: ${printers.length} • منافذ COM: ${ports.length}';
      });
    } catch (error) {
      if (mounted) setState(() => _printerStatus = 'تعذر فحص الأجهزة: $error');
    }
  }

  Future<void> _saveSettings() async {
    final storage = await AppStorage.getInstance();
    await AppStorage.setStrings({
      _modeKey: _mode,
      _enabledKey: _autoOpen ? 'true' : 'false',
      _pinKey: _pin,
      _pulseOnKey: _pulseOn,
      _pulseOffKey: _pulseOff,
      _portKey: _selectedPort ?? '',
      _baudKey: _baud,
      _usbHexKey: _hexController.text.trim(),
      if (_selectedPrinter != null) _printerKey: _selectedPrinter!,
    });
    if (_selectedPrinter == null) await storage.remove(_printerKey);
    if (mounted) setState(() => _printerStatus = 'تم حفظ إعدادات درج النقود.');
  }

  Future<void> _savePrinter(String? value) async {
    setState(() => _selectedPrinter = value);
    final storage = await AppStorage.getInstance();
    if (value == null) {
      await storage.remove(_printerKey);
    } else {
      await storage.setString(_printerKey, value);
    }
    if (mounted) setState(() => _printerStatus = 'تم حفظ الطابعة المختارة.');
  }

  Future<void> _testPrint() async {
    final printer = _selectedPrinter;
    if (printer == null || _busy) return;
    setState(() => _busy = true);
    try {
      final encodedPrinter = base64Encode(utf8.encode(printer));
      await _runPowerShell(
        r'$printer = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("' +
        encodedPrinter +
        r'")); '
        r'if (-not (Get-CimInstance Win32_Printer | Where-Object { $_.Name -eq $printer })) { throw "Printer not found" }; '
        r'@("BatiPro DZ", "TEST PRINT", "Windows POS printer is ready.", (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), "------------------------------") | Out-Printer -Name $printer',
      );
      if (mounted) setState(() => _printerStatus = 'تم إرسال صفحة الاختبار إلى الطابعة.');
    } catch (error) {
      if (mounted) setState(() => _printerStatus = 'فشل إرسال الاختبار: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testDrawer() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختبار فتح درج النقود'),
        content: const Text(
          'تأكد أن الدرج موصول بشكل صحيح ولا توجد أشياء تعيق فتحه. '
          'سيتم إرسال أمر فتح تجريبي للجهاز المحدد.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('فتح الدرج الآن')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _saveSettings();
      await PosDrawerService.testOpen();
      if (mounted) setState(() => _printerStatus = 'تم إرسال أمر فتح الدرج بنجاح إلى نظام التشغيل.');
    } catch (error) {
      if (mounted) setState(() => _printerStatus = 'تعذر فتح الدرج: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _infoTile(IconData icon, String title, String body) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(body),
  );

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    border: const OutlineInputBorder(),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final serialMode = _mode == 'usb_serial';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الأجهزة الطرفية ونقاط البيع (POS)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            const Text('إعداد الطابعة ودرج النقود والأجهزة المتصلة بهذا الكمبيوتر بنظام Windows.',
                style: TextStyle(fontSize: 11)),
            const SizedBox(height: 14),
            const Text('طابعة الفواتير', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _printers.contains(_selectedPrinter) ? _selectedPrinter : null,
              isExpanded: true,
              decoration: _decoration('الطابعة المثبتة في Windows', Icons.print_outlined),
              items: _printers.map((name) => DropdownMenuItem(
                value: name, child: Text(name, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: _busy ? null : _savePrinter,
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _refreshDevices,
                icon: const Icon(Icons.refresh),
                label: const Text('تحديث الأجهزة'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || _selectedPrinter == null ? null : _testPrint,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('طباعة صفحة اختبار'),
              ),
            ]),
            const Divider(height: 26),
            const Text('إعداد درج النقود', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 9),
            DropdownButtonFormField<String>(
              value: _mode,
              decoration: _decoration('طريقة توصيل الدرج', Icons.point_of_sale),
              items: const [
                DropdownMenuItem(value: 'printer', child: Text('عبر الطابعة الحرارية (RJ11/RJ12)')),
                DropdownMenuItem(value: 'usb_serial', child: Text('USB مباشر — وحدة تظهر كمنفذ COM')),
              ],
              onChanged: _busy ? null : (value) => setState(() => _mode = value ?? 'printer'),
            ),
            const SizedBox(height: 8),
            if (!serialMode) ...[
              DropdownButtonFormField<String>(
                value: _pin,
                decoration: _decoration('مخرج درج النقود في الطابعة', Icons.cable_outlined),
                items: const [
                  DropdownMenuItem(value: '2', child: Text('Pin 2 — الافتراضي الشائع')),
                  DropdownMenuItem(value: '5', child: Text('Pin 5 — حسب الطابعة')),
                ],
                onChanged: _busy ? null : (value) => setState(() => _pin = value ?? '2'),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(
                  value: _pulseOn,
                  decoration: const InputDecoration(labelText: 'مدة النبضة ON', border: OutlineInputBorder()),
                  items: const ['10', '20', '25', '30', '40', '50'].map((v) =>
                    DropdownMenuItem(value: v, child: Text('$v × 2 ms'))).toList(),
                  onChanged: _busy ? null : (v) => setState(() => _pulseOn = v ?? '25'),
                )),
                const SizedBox(width: 8),
                Expanded(child: DropdownButtonFormField<String>(
                  value: _pulseOff,
                  decoration: const InputDecoration(labelText: 'مدة النبضة OFF', border: OutlineInputBorder()),
                  items: const ['100', '150', '200', '250', '300'].map((v) =>
                    DropdownMenuItem(value: v, child: Text('$v × 2 ms'))).toList(),
                  onChanged: _busy ? null : (v) => setState(() => _pulseOff = v ?? '250'),
                )),
              ]),
              const SizedBox(height: 8),
              const Text('يرسل البرنامج أمر ESC/POS خاماً عبر Windows Spooler. يلزم أن تدعم الطابعة منفذ درج النقود وأن يطابق Pin إعداد جهازك.',
                  style: TextStyle(fontSize: 10, height: 1.5)),
            ] else ...[
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(
                  value: _ports.contains(_selectedPort) ? _selectedPort : null,
                  decoration: const InputDecoration(labelText: 'منفذ USB / COM', border: OutlineInputBorder()),
                  items: _ports.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: _busy ? null : (v) => setState(() => _selectedPort = v),
                )),
                IconButton(onPressed: _busy ? null : _refreshDevices,
                    tooltip: 'تحديث المنافذ', icon: const Icon(Icons.refresh)),
              ]),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _baud,
                decoration: const InputDecoration(labelText: 'سرعة الاتصال Baud rate', border: OutlineInputBorder()),
                items: const ['1200', '2400', '4800', '9600', '19200', '38400', '57600', '115200'].map((v) =>
                  DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: _busy ? null : (v) => setState(() => _baud = v ?? '9600'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _hexController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'أمر الفتح HEX',
                  hintText: 'مثال شكلي: 1B 70 00 19 FA',
                  helperText: 'أدخل الأمر المحدد في دليل وحدة USB فقط؛ لا تستعمل مثالاً عشوائياً.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 5),
              const Text('هذا الوضع يدعم وحدات USB التي تظهر كمنفذ COM. وحدات USB-HID أو الوحدات ذات بروتوكول خاص تحتاج تعريفاً منفصلاً.',
                  style: TextStyle(fontSize: 10, height: 1.5)),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _autoOpen,
              title: const Text('فتح الدرج تلقائياً بعد استلام الدفع',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              subtitle: const Text('لا يفتح عند البيع على الحساب دون مبلغ مدفوع.',
                  style: TextStyle(fontSize: 10)),
              onChanged: _busy ? null : (value) => setState(() => _autoOpen = value),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: _busy ? null : _saveSettings,
                icon: const Icon(Icons.save_outlined),
                label: const Text('حفظ إعدادات الدرج'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _testDrawer,
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('اختبار فتح الدرج'),
              ),
            ]),
            const SizedBox(height: 8),
            Text(_printerStatus, style: TextStyle(
              fontSize: 11, color: Theme.of(context).colorScheme.secondary)),
            const Divider(height: 26),
            _infoTile(Icons.qr_code_scanner, 'قارئ الباركود',
                'القارئ USB الذي يعمل كلوحة مفاتيح (HID/Keyboard Wedge) يمكنه إدخال الرمز في خانة البحث أو الباركود.'),
            _infoTile(Icons.scale_outlined, 'الميزان الإلكتروني',
                'سيُضاف ربط الميزان كوظيفة مستقلة بعد معرفة الطراز والبروتوكول؛ لا نرسل أوامر عشوائية إلى أجهزة الوزن.'),
            const Divider(height: 20),
            const Text('ملاحظة التوافق', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            const Text(
              'اختيار الطابعة وصفحة الاختبار يعتمدان على تعريف Windows. فتح الدرج عبر USB المباشر يتطلب وحدة تحكم متوافقة ومنفذ COM وأمر HEX موثقاً. لا يمكن ضمان توافق كل أدراج USB العامة.',
              style: TextStyle(fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
