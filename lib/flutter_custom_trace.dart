import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CustomTrace {
  final StackTrace _trace;

  String? fileName;
  int? lineNumber;
  int? columnNumber;
  // List<String> listDebugInfo = [];

  CustomTrace(this._trace) {
    _parseTrace();
  }

  void _parseTrace() {
    var traceString = _trace.toString().split('\n')[0]; // Get the first line of the stack trace
    var indexOfFileName = traceString.indexOf(RegExp(r'[A-Za-z_]+\.dart'));
    var fileInfo = traceString.substring(indexOfFileName);
    var listOfInfos = fileInfo.split(':');

    fileName = listOfInfos[0];
    lineNumber = int.parse(listOfInfos[1]);
    columnNumber = int.parse(listOfInfos[2].replaceAll(')', ''));
  }

  /// Simpan trace dengan format standar: file, value, payload, date.
  ///
  /// ```dart
  /// CustomTrace(StackTrace.current).saveTrace(value: data, payload: 'BSSID');
  /// ```
  void saveTrace({required Object? value, String payload = ''}) {
    saveError(
      jsonError: jsonEncode({
        'file': '$fileName,line: $lineNumber',
        'value': value.toString(),
        'payload': payload,
        'date': orangeDateTime(),
      }),
    );
  }

  /// Simpan trace ke `debug_info` (SharedPreferences) jika `is_debug` aktif.
  ///
  /// Apa pun isi [jsonError], data yang disimpan selalu dinormalisasi ke format
  /// standar `{file, value, payload, date}`:
  /// - key lama `message` dipetakan ke `value`
  /// - `payload` kosong jika tidak diisi
  /// - `file` dan `date` diisi otomatis jika tidak ada
  void saveError({required String jsonError}) async {
    final prefs = await SharedPreferences.getInstance();
    final bool? isDebug = prefs.getBool('is_debug');
    if (isDebug == true) {
      final List<String> list = List<String>.from(prefs.getStringList('debug_info') ?? []);
      list.add(normalize(jsonError));
      prefs.setStringList('debug_info', list);
    }
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
