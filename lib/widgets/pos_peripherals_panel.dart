import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/app_storage.dart';

/// Windows POS peripheral setup. USB keyboard-wedge scanners work as keyboard
/// input and do not require a separate driver integration in this screen.
class PosPeripheralsPanel extends StatefulWidget {
  const PosPeripheralsPanel({super.key});

  @override
  State<PosPeripheralsPanel> createState() => _PosPeripheralsPanelState();
}

class _PosPeripheralsPanelState extends State<PosPeripheralsPanel> {
  static const _printerKey = 'batipro_pos_printer_name';
  List<String> _printers = [];
  String? _selectedPrinter;
  bool _loading = true;
  bool _busy = false;
  String _printerStatus = 'لم يتم فحص الطابعات بعد';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = await AppStorage.getInstance();
    _selectedPrinter = storage.getString(_printerKey);
    await _refreshPrinters();
    if (mounted) setState(() => _loading = false);
  }

  Future<String> _runPowerShell(String script) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('إدارة طابعات Windows متاحة في نسخة Windows فقط.');
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

  Future<void> _refreshPrinters() async {
    if (!Platform.isWindows) {
      if (mounted) setState(() => _printerStatus = 'هذا القسم مخصص لنظام Windows.');
      return;
    }
    try {
      final output = await _runPowerShell(
        r'$items = Get-CimInstance Win32_Printer | Select-Object -ExpandProperty Name; '
        r'ConvertTo-Json -InputObject @($items) -Compress',
      );
      final decoded = jsonDecode(output);
      final printers = decoded is List
          ? decoded.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : decoded == null ? <String>[] : [decoded.toString()];
      final storage = await AppStorage.getInstance();
      final saved = storage.getString(_printerKey);
      if (!mounted) return;
      setState(() {
        _printers = printers;
        _selectedPrinter = printers.contains(saved) ? saved : (printers.isNotEmpty ? printers.first : null);
        _printerStatus = printers.isEmpty
            ? 'لم يتم العثور على طابعة مثبتة في Windows.'
            : 'تم العثور على ${printers.length} طابعة.';
      });
    } catch (error) {
      if (mounted) setState(() => _printerStatus = 'تعذر جلب الطابعات: $error');
    }
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

  Widget _infoTile(IconData icon, String title, String body) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(body),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الأجهزة الطرفية ونقاط البيع (POS)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            const Text('إعداد الأجهزة المتصلة بهذا الكمبيوتر بنظام Windows.',
                style: TextStyle(fontSize: 11)),
            const SizedBox(height: 14),
            const Text('طابعة الفواتير', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _printers.contains(_selectedPrinter) ? _selectedPrinter : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'الطابعة المثبتة في Windows',
                prefixIcon: Icon(Icons.print_outlined),
                border: OutlineInputBorder(),
              ),
              items: _printers.map((name) => DropdownMenuItem(
                value: name, child: Text(name, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: _busy ? null : _savePrinter,
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _refreshPrinters,
                icon: const Icon(Icons.refresh),
                label: const Text('تحديث قائمة الطابعات'),
              ),
              FilledButton.icon(
                onPressed: _busy || _selectedPrinter == null ? null : _testPrint,
                icon: _busy
                    ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.receipt_long_outlined),
                label: const Text('طباعة صفحة اختبار'),
              ),
            ]),
            const SizedBox(height: 6),
            Text(_printerStatus, style: TextStyle(
              fontSize: 11, color: Theme.of(context).colorScheme.secondary)),
            const Divider(height: 26),
            _infoTile(Icons.qr_code_scanner, 'قارئ الباركود',
                'القارئ USB الذي يعمل كلوحة مفاتيح (HID/Keyboard Wedge) يمكنه إدخال الرمز في خانة البحث أو الباركود. لا يحتاج تعريفاً خاصاً داخل البرنامج.'),
            _infoTile(Icons.point_of_sale, 'درج النقود',
                'يُوصل عادة بالطابعة الحرارية عبر RJ11/RJ12 ويحتاج أمر فتح متوافقاً مع ESC/POS. لم يتم تفعيل فتح الدرج آلياً في هذه المرحلة.'),
            _infoTile(Icons.scale_outlined, 'الميزان الإلكتروني',
                'يتطلب تحديد الشركة والطراز وطريقة الاتصال (USB-Serial أو RS-232 أو بروتوكول خاص) قبل تفعيل قراءة الوزن المباشرة.'),
            const Divider(height: 20),
            const Text('ملاحظة التوافق', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            const Text(
              'اختيار الطابعة وإرسال صفحة اختبار يعتمدان على تعريف الطابعة المثبت في Windows. أحجام 58/80 مم، قص الورق، درج النقود، وقراءة الميزان تحتاج اختباراً مع موديل الجهاز الفعلي قبل اعتمادها.',
              style: TextStyle(fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
