// Menerjemahkan log flutter_custom_trace dari build release
// `--split-debug-info` / `--obfuscate` menjadi nama file & nomor baris.
//
// Pemakaian (dari folder project aplikasi):
//   dart run flutter_custom_trace:symbolize -d <file/folder .symbols> -i <log.txt> [--json <hasil.json>]
//
// <log.txt> boleh berisi body email "Debug Info OranHR Apps" apa adanya,
// list JSON `debug_info`, atau teks apa pun yang memuat penanda `dwarf:...`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_custom_trace/src/dwarf_location.dart';
import 'package:native_stack_traces/native_stack_traces.dart';

const _usage = '''
Pemakaian:
  dart run flutter_custom_trace:symbolize -d <symbols> -i <log> [--json <output.json>]

  -d, --debug-info  File .symbols, atau folder berisi file .symbols
                    (dicari rekursif, dicocokkan otomatis berdasarkan build_id)
  -i, --input       File log (body email Debug Info / list JSON debug_info).
                    Jika tidak diisi, dibaca dari stdin.
      --json        Simpan hasil sebagai list JSON {file, value, payload, date}
                    dengan field file yang sudah diterjemahkan.
  -h, --help        Tampilkan bantuan ini.
''';

Future<void> main(List<String> args) async {
  String? debugInfo;
  String? input;
  String? jsonOut;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String next() {
      if (i + 1 >= args.length) _fail('Nilai untuk $a tidak ada.\n\n$_usage');
      return args[++i];
    }

    switch (a) {
      case '-d' || '--debug-info':
        debugInfo = next();
      case '-i' || '--input':
        input = next();
      case '--json':
        jsonOut = next();
      case '-h' || '--help':
        stdout.write(_usage);
        return;
      default:
        _fail('Argumen tidak dikenal: $a\n\n$_usage');
    }
  }
  if (debugInfo == null) _fail('Wajib mengisi -d <symbols>.\n\n$_usage');

  final text = input == null ? await stdin.transform(utf8.decoder).join() : File(input).readAsStringSync();
  final entries = parseEntries(text);
  if (entries.isEmpty) _fail('Tidak ada entri log yang ditemukan di input.');

  final symbols = _SymbolsIndex(debugInfo);
  final results = <Map<String, String>>[];
  var resolved = 0, missing = 0;

  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final file = e['file']?.toString() ?? '';
    final loc = DwarfLocation.fromToken(file);
    var newFile = file;
    final lines = <String>[];

    if (loc != null) {
      final dwarf = symbols.find(loc.buildId);
      if (dwarf == null) {
        missing++;
        lines.add('lokasi: ? (file .symbols untuk build_id ${loc.buildId}${loc.arch == null ? '' : ' / ${loc.arch}'} tidak ditemukan)');
      } else {
        resolved++;
        for (var f = 0; f < loc.virtualAddresses.length; f++) {
          final call = _resolve(dwarf, loc.virtualAddresses[f]);
          final label = f == 0 ? 'lokasi' : '  dari';
          lines.add('$label: ${call == null ? '? (0x${loc.virtualAddresses[f].toRadixString(16)})' : '${_basename(call.filename)}:${call.line} (${call.function})'}');
          if (f == 0 && call != null) newFile = '${_basename(call.filename)},line: ${call.line}';
        }
      }
    } else {
      lines.add('lokasi: $file');
    }

    results.add({
      'file': newFile,
      'value': e['value']?.toString() ?? e['message']?.toString() ?? '',
      'payload': e['payload']?.toString() ?? '',
      'date': e['date']?.toString() ?? '',
    });

    final r = results.last;
    stdout.writeln('[${i + 1}] ${r['date']}${r['payload']!.isEmpty ? '' : ' | ${r['payload']}'}');
    for (final l in lines) {
      stdout.writeln('    $l');
    }
    stdout.writeln('    value : ${r['value']}');
    stdout.writeln();
  }

  stdout.writeln('Total ${entries.length} entri: $resolved diterjemahkan, $missing tanpa file .symbols yang cocok, '
      '${entries.length - resolved - missing} sudah berisi lokasi.');
  if (missing > 0) {
    stdout.writeln('Build ID yang tersedia: ${symbols.availableBuildIds.join(', ')}');
  }

  if (jsonOut != null) {
    File(jsonOut).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
    stdout.writeln('Hasil JSON disimpan ke $jsonOut');
  }
}

/// Ambil entri log dari body email / list JSON / teks bebas.
List<Map<String, dynamic>> parseEntries(String raw) {
  final text = raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll('&quot;', '"')
      .replaceAll('&#34;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  Map<String, dynamic>? asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String) {
      try {
        final d = jsonDecode(v);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return null;
  }

  // 1. List JSON (format email: jsonEncode(List<String>))
  final start = text.indexOf('[');
  final end = text.lastIndexOf(']');
  if (start != -1 && end > start) {
    try {
      final list = jsonDecode(text.substring(start, end + 1));
      if (list is List) {
        final maps = list.map(asMap).whereType<Map<String, dynamic>>().toList();
        if (maps.isNotEmpty) return maps;
      }
    } catch (_) {}
  }

  // 2. Satu objek JSON per baris
  final perLine = text.split('\n').map((l) => asMap(l.trim())).whereType<Map<String, dynamic>>().toList();
  if (perLine.isNotEmpty) return perLine;

  // 3. Hanya penanda dwarf:... di teks bebas
  return DwarfLocation.tokenRe.allMatches(text).map((m) => <String, dynamic>{'file': m.group(0)}).toList();
}

DartCallInfo? _resolve(Dwarf dwarf, int virt) {
  try {
    final calls = dwarf.callInfoForPCOffset(PCOffset(virt, InstructionsSection.none));
    return calls?.whereType<DartCallInfo>().firstOrNull;
  } catch (_) {
    return null;
  }
}

String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

Never _fail(String message) {
  stderr.writeln(message);
  exit(64);
}

/// Mencari file .symbols yang build_id-nya cocok. File dimuat seperlunya.
class _SymbolsIndex {
  final List<String> _pending;
  final Map<String, Dwarf> _loaded = {};

  _SymbolsIndex(String path) : _pending = _listSymbols(path);

  static List<String> _listSymbols(String path) {
    if (FileSystemEntity.isFileSync(path)) return [path];
    if (FileSystemEntity.isDirectorySync(path)) {
      final files = Directory(path)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.symbols'))
          .toList();
      if (files.isEmpty) _fail('Tidak ada file .symbols di $path');
      return files;
    }
    _fail('Path symbols tidak ditemukan: $path');
  }

  Dwarf? find(String buildId) {
    while (!_loaded.containsKey(buildId) && _pending.isNotEmpty) {
      _load(_pending.removeAt(0));
    }
    return _loaded[buildId];
  }

  Iterable<String> get availableBuildIds {
    while (_pending.isNotEmpty) {
      _load(_pending.removeAt(0));
    }
    return _loaded.keys;
  }

  void _load(String path) {
    try {
      final dwarf = Dwarf.fromFile(path);
      final id = dwarf?.buildId();
      if (dwarf != null && id != null) _loaded[id] = dwarf;
    } catch (_) {
      stderr.writeln('Lewati $path (bukan file symbols yang valid)');
    }
  }
}
