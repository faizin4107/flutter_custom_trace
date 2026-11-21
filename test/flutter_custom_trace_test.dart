import 'dart:convert';

import 'package:flutter_custom_trace/flutter_custom_trace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const keys = ['file', 'value', 'payload', 'date'];

  group('parse stack trace', () {
    test('debug (JIT): file, line, column', () {
      final trace = CustomTrace(StackTrace.fromString(
          '#0      ClockingController.doClocking (package:oranhr/controller/clocking.dart:372:7)\n'
          '#1      main (package:oranhr/main.dart:10:3)'));
      expect(trace.fileName, 'clocking.dart');
      expect(trace.lineNumber, 372);
      expect(trace.columnNumber, 7);
    });

    test('release (AOT): tanpa column tidak throw', () {
      final trace = CustomTrace(StackTrace.fromString(
          '#0      ClockingController.doClocking (package:oranhr/controller/clocking.dart:372)\n'
          '#1      main (package:oranhr/main.dart:10)'));
      expect(trace.fileName, 'clocking.dart');
      expect(trace.lineNumber, 372);
      expect(trace.columnNumber, isNull);
    });

    test('release --split-debug-info / --obfuscate: simpan penanda DWARF', () {
      final trace = CustomTrace(StackTrace.fromString(
          '*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***\n'
          'pid: 1, tid: 2, name DartWorker\n'
          'os: android arch: arm64 comp: yes sim: no\n'
          "build_id: '13c06b791d8f2766911c6d4b25f8b194'\n"
          'isolate_dso_base: 7a00000000, vm_dso_base: 7a00000000\n'
          'isolate_instructions: 7a00320000, vm_instructions: 7a00320000\n'
          '    #00 abs 0000007a00b40000 virt 0000000000b40000 _kDartSnapshotText+0x820000\n'
          '    #01 abs 0000007a00b3ff10 virt 0000000000b3ff10 _kDartSnapshotText+0x81ff10\n'
          '    #02 abs 0000007a00a00000 virt 0000000000a00000 _kDartSnapshotText+0x6e0000'));
      expect(trace.fileName, 'dwarf:build_id=13c06b791d8f2766911c6d4b25f8b194;arch=arm64;virt=b40000,b3ff10');
      expect(trace.lineNumber, isNull);
      expect(trace.dwarfLocation!.virtualAddresses, [0xb40000, 0xb3ff10]);
    });

    test('DWARF tanpa virt: alamat dihitung dari abs - isolate_dso_base', () {
      final loc = DwarfLocation.fromStackTrace(
          "build_id: 'abc123'\n"
          'isolate_dso_base: 1ab527b0000, vm_dso_base: 0\n'
          '    #00 abs 000001ab52819ac2 _kDartSnapshotText+0x35ac2');
      expect(loc!.virtualAddresses, [0x69ac2]);
      expect(loc.arch, isNull);
    });

    test('penanda DWARF bisa dibaca ulang (round trip)', () {
      const loc = DwarfLocation(buildId: 'abc123', arch: 'arm', virtualAddresses: [0x10, 0xff]);
      final back = DwarfLocation.fromToken('${loc.toToken()},line: null')!;
      expect(back.buildId, 'abc123');
      expect(back.arch, 'arm');
      expect(back.virtualAddresses, [0x10, 0xff]);
    });

    test('stack trace tanpa lokasi apa pun: file unknown', () {
      final trace = CustomTrace(StackTrace.fromString('<asynchronous suspension>'));
      expect(trace.fileName, 'unknown');
      expect(trace.dwarfLocation, isNull);
    });

    test('nama file dengan angka', () {
      final trace = CustomTrace(StackTrace.fromString(
          '#0      foo (package:oranhr/api/orange_api_v2.dart:15)'));
      expect(trace.fileName, 'orange_api_v2.dart');
      expect(trace.lineNumber, 15);
    });

    test('trace kosong: tidak throw', () {
      final trace = CustomTrace(StackTrace.fromString(''));
      expect(trace.fileName, 'unknown');
    });

    test('release: saveTrace tetap tersimpan', () async {
      SharedPreferences.setMockInitialValues({'is_debug': true});
      CustomTrace(StackTrace.fromString('#0      foo (package:oranhr/controller/clocking.dart:372)'))
          .saveTrace(value: 'x', payload: 'BSSID');
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getStringList('debug_info')!.single);
      expect(saved['file'], 'clocking.dart,line: 372');
      expect(saved['payload'], 'BSSID');
    });
  });

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
