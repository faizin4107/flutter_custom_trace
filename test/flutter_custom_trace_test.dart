import 'dart:convert';

import 'package:flutter_custom_trace/flutter_custom_trace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const keys = ['file', 'value', 'payload', 'date'];

  group('normalize', () {
    test('format standar tetap sama', () {
      final trace = CustomTrace(StackTrace.current);
      final input = {
        'file': 'clocking.dart,line: 10',
        'value': 'abc',
        'payload': 'BSSID',
        'date': '21/11/2026 9:0:0',
      };
      final result = jsonDecode(trace.normalize(jsonEncode(input)));
      expect(result, input);
    });

    test('key lama "message" dipetakan ke value dan payload ditambahkan', () {
      final trace = CustomTrace(StackTrace.current);
      final result = jsonDecode(trace.normalize(jsonEncode({
        'file': 'auth.dart,line: 5',
        'message': 'error login',
        'date': '21/11/2026 9:0:0',
      })));
      expect(result.keys, keys);
      expect(result['value'], 'error login');
      expect(result['payload'], '');
      expect(result['file'], 'auth.dart,line: 5');
    });

    test('file dan date diisi otomatis jika tidak ada', () {
      final trace = CustomTrace(StackTrace.current);
      final result = jsonDecode(trace.normalize(jsonEncode({'value': 1})));
      expect(result.keys, keys);
      expect(result['value'], '1');
      expect(result['file'], startsWith('flutter_custom_trace_test.dart,line: '));
      expect(result['date'], isNotEmpty);
    });

    test('string non-JSON disimpan sebagai value', () {
      final trace = CustomTrace(StackTrace.current);
      final result = jsonDecode(trace.normalize('bukan json'));
      expect(result.keys, keys);
      expect(result['value'], 'bukan json');
    });
  });

  test('saveTrace menyimpan format standar ke debug_info', () async {
    SharedPreferences.setMockInitialValues({'is_debug': true});
    CustomTrace(StackTrace.current).saveTrace(value: {'a': 1}, payload: 'Location Check');
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getStringList('debug_info')!.single);
    expect(saved.keys, keys);
    expect(saved['value'], '{a: 1}');
    expect(saved['payload'], 'Location Check');
  });

  test('tidak menyimpan jika is_debug tidak aktif', () async {
    SharedPreferences.setMockInitialValues({});
    CustomTrace(StackTrace.current).saveTrace(value: 'x', payload: 'y');
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('debug_info'), isNull);
  });
}
