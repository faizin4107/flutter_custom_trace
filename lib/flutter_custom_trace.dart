import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'src/dwarf_location.dart';

export 'src/dwarf_location.dart';

class CustomTrace {
  final StackTrace _trace;

  String? fileName;
  int? lineNumber;
  int? columnNumber;

  /// Terisi jika stack trace berformat DWARF (build `--split-debug-info` /
  /// `--obfuscate`). Pada kondisi ini [fileName] berisi penanda
  /// `dwarf:build_id=...;arch=...;virt=...` yang bisa diterjemahkan ke
  /// file/baris dengan `dart run flutter_custom_trace:symbolize`.
  DwarfLocation? dwarfLocation;
  // List<String> listDebugInfo = [];

  CustomTrace(this._trace) {
    _parseTrace();
  }

  /// Nama file `.dart`, nomor baris, dan nomor kolom (opsional).
  /// - debug (JIT):   `#0  foo (package:app/a.dart:12:5)`
  /// - release (AOT): `#0  foo (package:app/a.dart:12)` (tanpa kolom)
  static final RegExp _frameRegex = RegExp(r'([A-Za-z0-9_\-]+\.dart):(\d+)(?::(\d+))?');

  /// Parsing stack trace yang tidak pernah throw, agar trace tetap tersimpan
  /// di mode release.
  /// - debug / release biasa: [fileName], [lineNumber], [columnNumber]
  /// - release `--split-debug-info` / `--obfuscate`: [dwarfLocation], dan
  ///   [fileName] berisi penanda DWARF ([lineNumber]/[columnNumber] `null`)
  /// - selain itu: [fileName] = `unknown`
  void _parseTrace() {
    try {
      final trace = _trace.toString();
      for (final line in trace.split('\n')) {
        final match = _frameRegex.firstMatch(line);
        if (match != null) {
          fileName = match.group(1);
          lineNumber = int.tryParse(match.group(2)!);
          final column = match.group(3);
          columnNumber = column == null ? null : int.tryParse(column);
          return;
        }
      }
      dwarfLocation = DwarfLocation.fromStackTrace(trace);
      fileName = dwarfLocation?.toToken();
    } catch (_) {}
    fileName ??= 'unknown';
  }

  /// Jumlah maksimum catatan di `debug_info`; catatan terlama dibuang lebih
  /// dulu. Dulu tidak dibatasi sehingga terus membesar selama `is_debug`
  /// aktif (dan isinya dikirim utuh lewat email Debug Info).
  static int maxDebugInfo = 200;

  /// Panjang maksimum `value` per catatan (karakter); sisanya dipotong.
  static int maxValueLength = 4000;

  /// Antrean penulisan: `debug_info` dibaca-ubah-tulis, sehingga penyimpanan
  /// yang berjalan bersamaan dulu bisa saling menimpa (catatan hilang).
  static Future<void> _queue = Future<void>.value();

  static bool? _enabled;

  /// Status pencatatan yang diatur aplikasi lewat [setEnabled].
  /// `null` = belum diatur: perilaku lama, yaitu mencatat hanya bila
  /// SharedPreferences `is_debug` bernilai `true`.
  static bool? get enabled => _enabled;

  /// Aktifkan / nonaktifkan pencatatan (mis. mengikuti setting Debug app).
  /// Saat nonaktif, [saveTrace] dan [saveError] langsung selesai tanpa
  /// menyentuh SharedPreferences; catatan yang masih di antrean dibatalkan.
  /// Data `debug_info` yang sudah ada tidak dihapus.
  static void setEnabled(bool value) => _enabled = value;

  /// Kembalikan ke perilaku lama (cek `is_debug`). Untuk test.
  static void resetEnabled() => _enabled = null;

  /// Simpan trace dengan format standar: file, value, payload, date.
  ///
  /// Tidak pernah melempar (sinkron maupun async); `Future` boleh diabaikan.
  ///
  /// ```dart
  /// CustomTrace(StackTrace.current).saveTrace(value: data, payload: 'BSSID');
  /// ```
  Future<void> saveTrace({required Object? value, String payload = ''}) {
    if (_enabled == false) return Future<void>.value();
    final String jsonError;
    try {
      jsonError = jsonEncode({
        'file': '$fileName,line: $lineNumber',
        'value': _valueText(value),
        'payload': payload,
        'date': orangeDateTime(),
      });
    } catch (_) {
      return Future<void>.value();
    }
    return saveError(jsonError: jsonError);
  }

  /// Simpan trace ke `debug_info` (SharedPreferences) bila pencatatan aktif:
  /// [enabled] `true`, atau [enabled] belum diatur dan `is_debug` `true`.
  ///
  /// Apa pun isi [jsonError], data yang disimpan selalu dinormalisasi ke format
  /// standar `{file, value, payload, date}`:
  /// - key lama `message` dipetakan ke `value`
  /// - `payload` kosong jika tidak diisi
  /// - `file` dan `date` diisi otomatis jika tidak ada
  ///
  /// Tidak pernah melempar: dulu `void async`, sehingga kegagalan
  /// SharedPreferences (mis. plugin belum siap / isolate latar) lolos dari
  /// `try/catch` pemanggil sebagai error async yang tidak tertangkap.
  Future<void> saveError({required String jsonError}) {
    if (_enabled == false) return Future<void>.value();
    final String entry;
    try {
      entry = _limitValue(normalize(jsonError));
    } catch (_) {
      return Future<void>.value();
    }
    final next = _queue.then((_) async {
      try {
        await _append(entry);
      } catch (_) {}
    });
    _queue = next;
    return next;
  }

  static Future<void> _append(String entry) async {
    // Dicek lagi saat giliran tiba: bisa saja dinonaktifkan selagi mengantre.
    if (_enabled == false) return;
    final prefs = await SharedPreferences.getInstance();
    if (_enabled == null && prefs.getBool('is_debug') != true) return;
    final List<String> list = List<String>.from(prefs.getStringList('debug_info') ?? const <String>[]);
    list.add(entry);
    final int max = maxDebugInfo < 1 ? 1 : maxDebugInfo;
    if (list.length > max) {
      list.removeRange(0, list.length - max);
    }
    await prefs.setStringList('debug_info', list);
  }

  static String _valueText(Object? value) {
    try {
      return value.toString();
    } catch (_) {
      return '<toString gagal: ${value.runtimeType}>';
    }
  }

  /// Potong `value` pada JSON hasil [normalize] bila melebihi [maxValueLength].
  static String _limitValue(String normalized) {
    final data = jsonDecode(normalized) as Map<String, dynamic>;
    final value = data['value']?.toString() ?? '';
    if (maxValueLength > 0 && value.length > maxValueLength) {
      data['value'] = '${value.substring(0, maxValueLength)}… [dipotong ${value.length - maxValueLength} karakter]';
      return jsonEncode(data);
    }
    return normalized;
  }

  /// Ubah [jsonError] ke format standar `{file, value, payload, date}`.
  String normalize(String jsonError) {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(jsonError);
      data = decoded is Map ? Map<String, dynamic>.from(decoded) : {'value': decoded};
    } catch (_) {
      // Bukan JSON: simpan string mentahnya sebagai value
      data = {'value': jsonError};
    }

    final value = data.containsKey('value') ? data['value'] : data['message'];

    return jsonEncode({
      'file': data['file']?.toString() ?? '$fileName,line: $lineNumber',
      'value': value?.toString() ?? '',
      'payload': data['payload']?.toString() ?? '',
      'date': data['date']?.toString() ?? orangeDateTime(),
    });
  }

  String orangeDateTime() {
    var date = DateTime.now();
    String day = '';
    if (date.day.toString().length > 1) {
      day = date.day.toString();
    } else {
      day = '0${date.day.toString()}';
    }
    var myDate =
        '$day/${date.month}/${date.year} ${date.hour}:${date.minute}:${date.second}';

    return myDate;
  }
}
