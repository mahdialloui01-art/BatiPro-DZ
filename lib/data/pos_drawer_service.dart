import 'dart:convert';
import 'dart:io';

import 'app_storage.dart';

/// Windows cash-drawer transport. Printer mode sends a raw ESC/POS pulse;
/// direct USB mode supports USB-to-serial controllers exposing a COM port.
class PosDrawerService {
  PosDrawerService._();

  static const modeKey = 'batipro_drawer_mode';
  static const enabledKey = 'batipro_drawer_auto_open';
  static const printerKey = 'batipro_pos_printer_name';
  static const pinKey = 'batipro_drawer_pin';
  static const pulseOnKey = 'batipro_drawer_pulse_on';
  static const pulseOffKey = 'batipro_drawer_pulse_off';
  static const portKey = 'batipro_drawer_com_port';
  static const baudKey = 'batipro_drawer_baud';
  static const usbCommandKey = 'batipro_drawer_usb_hex';

  static Future<Map<String, String>> _settings() async {
    final storage = await AppStorage.getInstance();
    return {
      'mode': storage.getString(modeKey) ?? 'printer',
      'enabled': storage.getString(enabledKey) ?? 'false',
      'printer': storage.getString(printerKey) ?? '',
      'pin': storage.getString(pinKey) ?? '2',
      'pulseOn': storage.getString(pulseOnKey) ?? '25',
      'pulseOff': storage.getString(pulseOffKey) ?? '250',
      'port': storage.getString(portKey) ?? '',
      'baud': storage.getString(baudKey) ?? '9600',
      'usbHex': storage.getString(usbCommandKey) ?? '',
    };
  }

  static Future<bool> openAfterSale() async {
    final settings = await _settings();
    if (settings['enabled'] != 'true') return false;
    await _send(settings);
    return true;
  }

  /// Explicit test action; caller must obtain user confirmation first.
  static Future<void> testOpen() async {
    await _send(await _settings());
  }

  static Future<List<String>> listComPorts() async {
    final output = await _runPowerShell(
      r'$ports = [System.IO.Ports.SerialPort]::GetPortNames(); '
      r'ConvertTo-Json -InputObject @($ports) -Compress',
    );
    final decoded = jsonDecode(output);
    if (decoded is List) {
      return decoded.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return decoded == null || decoded.toString().isEmpty
        ? <String>[]
        : <String>[decoded.toString()];
  }

  static Future<void> _send(Map<String, String> settings) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('فتح درج النقود متاح في نسخة Windows فقط.');
    }
    if (settings['mode'] == 'printer') {
      final printer = settings['printer']!.trim();
      if (printer.isEmpty) throw StateError('اختر الطابعة أولاً.');
      final pin = settings['pin'] == '5' ? 1 : 0;
      final on = int.tryParse(settings['pulseOn']!) ?? 25;
      final off = int.tryParse(settings['pulseOff']!) ?? 250;
      if (on < 1 || on > 255 || off < 1 || off > 255) {
        throw const FormatException('قيم نبضة الدرج يجب أن تكون بين 1 و255.');
      }
      final payload = base64Encode(<int>[0x1B, 0x70, pin, on, off]);
      final printer64 = base64Encode(utf8.encode(printer));
      final script = r'''
$printer = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('PRINTER64'));
$bytes = [Convert]::FromBase64String('PAYLOAD64');
$source = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class BatiProRawPrinter {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public class DOC_INFO_1 {
    [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
    [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
    [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
  }
  [DllImport("winspool.drv", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern bool OpenPrinter(string name, out IntPtr handle, IntPtr defaults);
  [DllImport("winspool.drv", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern int StartDocPrinter(IntPtr handle, int level, [In] DOC_INFO_1 info);
  [DllImport("winspool.drv", SetLastError=true)]
  static extern bool StartPagePrinter(IntPtr handle);
  [DllImport("winspool.drv", SetLastError=true)]
  static extern bool WritePrinter(IntPtr handle, IntPtr bytes, int count, out int written);
  [DllImport("winspool.drv", SetLastError=true)]
  static extern bool EndPagePrinter(IntPtr handle);
  [DllImport("winspool.drv", SetLastError=true)]
  static extern bool EndDocPrinter(IntPtr handle);
  [DllImport("winspool.drv", SetLastError=true)]
  static extern bool ClosePrinter(IntPtr handle);
  public static void Send(string name, byte[] data) {
    IntPtr printer = IntPtr.Zero;
    IntPtr buffer = IntPtr.Zero;
    bool document = false, page = false;
    try {
      if (!OpenPrinter(name, out printer, IntPtr.Zero))
        throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenPrinter failed");
      var info = new DOC_INFO_1 { pDocName="BatiPro cash drawer", pDataType="RAW", pOutputFile=null };
      if (StartDocPrinter(printer, 1, info) == 0)
        throw new Win32Exception(Marshal.GetLastWin32Error(), "StartDocPrinter failed");
      document = true;
      if (!StartPagePrinter(printer))
        throw new Win32Exception(Marshal.GetLastWin32Error(), "StartPagePrinter failed");
      page = true;
      buffer = Marshal.AllocHGlobal(data.Length);
      Marshal.Copy(data, 0, buffer, data.Length);
      int written;
      if (!WritePrinter(printer, buffer, data.Length, out written) || written != data.Length)
        throw new Win32Exception(Marshal.GetLastWin32Error(), "WritePrinter failed");
    } finally {
      if (buffer != IntPtr.Zero) Marshal.FreeHGlobal(buffer);
      if (page) EndPagePrinter(printer);
      if (document) EndDocPrinter(printer);
      if (printer != IntPtr.Zero) ClosePrinter(printer);
    }
  }
}
'@;
Add-Type -TypeDefinition $source;
[BatiProRawPrinter]::Send($printer, $bytes);
'''.replaceAll('PRINTER64', printer64).replaceAll('PAYLOAD64', payload);
      await _runPowerShell(script);
      return;
    }

    if (settings['mode'] == 'usb_serial') {
      final port = settings['port']!.trim();
      if (port.isEmpty) throw StateError('اختر منفذ COM الخاص بوحدة USB.');
      final hex = settings['usbHex']!.trim();
      final bytes = _parseHex(hex);
      if (bytes.isEmpty) throw StateError('أدخل أمر الفتح بالصيغة السداسية HEX حسب دليل وحدة التحكم.');
      final command64 = base64Encode(bytes);
      final port64 = base64Encode(utf8.encode(port));
      final baud = int.tryParse(settings['baud']!) ?? 9600;
      if (baud < 300 || baud > 921600) throw const FormatException('سرعة COM غير صالحة.');
      final script = r'''
$port = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('PORT64'));
$bytes = [Convert]::FromBase64String('COMMAND64');
$serial = New-Object System.IO.Ports.SerialPort($port, BAUD, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One);
try {
  $serial.WriteTimeout = 2000;
  $serial.Open();
  $serial.Write($bytes, 0, $bytes.Length);
  $serial.BaseStream.Flush();
} finally {
  if ($serial.IsOpen) { $serial.Close(); }
  $serial.Dispose();
}
'''.replaceAll('PORT64', port64).replaceAll('COMMAND64', command64).replaceAll('BAUD', baud.toString());
      await _runPowerShell(script);
      return;
    }
    throw StateError('طريقة توصيل درج النقود غير معروفة.');
  }

  static List<int> _parseHex(String value) {
    final compact = value.replaceAll(RegExp(r'0x', caseSensitive: false), '')
        .replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (compact.isEmpty) return <int>[];
    if (compact.length.isOdd) {
      throw const FormatException('أمر HEX يجب أن يحتوي أزواجاً كاملة مثل 1B 70 00 19 FA.');
    }
    return List<int>.generate(
      compact.length ~/ 2,
      (index) => int.parse(compact.substring(index * 2, index * 2 + 2), radix: 16),
    );
  }

  static Future<String> _runPowerShell(String script) async {
    final encoded = base64Encode(utf8.encode(script));
    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      final message = result.stderr.toString().trim().isNotEmpty
          ? result.stderr.toString().trim()
          : result.stdout.toString().trim();
      throw Exception(message.isEmpty ? 'فشل تنفيذ أمر الجهاز.' : message);
    }
    return result.stdout.toString().trim();
  }
}
