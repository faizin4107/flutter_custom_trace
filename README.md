# flutter_custom_trace

Menyimpan info debug (file, baris, value, payload, waktu) ke `SharedPreferences`
(`debug_info`) saat `is_debug` aktif. Berfungsi di mode debug maupun release,
termasuk build `--obfuscate --split-debug-info`.

## Pemakaian

```dart
import 'package:flutter_custom_trace/flutter_custom_trace.dart';

// Disarankan
CustomTrace(StackTrace.current).saveTrace(value: data, payload: 'BSSID');

// Cara lama tetap didukung
CustomTrace programInfo = CustomTrace(StackTrace.current);
programInfo.saveError(
  jsonError: jsonEncode({
    'file': '${programInfo.fileName},line: ${programInfo.lineNumber}',
    'value': value.toString(),
    'payload': payload,
    'date': programInfo.orangeDateTime(),
  }),
);
```

Buat `CustomTrace(StackTrace.current)` **di baris yang ingin dicatat**. Jika
dibungkus helper, yang tercatat adalah baris di dalam helper tersebut.

Setiap entri selalu disimpan dengan format `{file, value, payload, date}`.
Key lama `message` otomatis dipetakan ke `value`.

## Isi field `file` per jenis build

| Build | `file` |
|---|---|
| debug | `clocking.dart,line: 372` |
| `flutter build apk --release` | `clocking.dart,line: 372` |
| `--split-debug-info` / `--obfuscate` | `dwarf:build_id=...;arch=arm64;virt=b40000,b3ff10,line: null` |

Pada build `--split-debug-info`, nama file/baris tidak ada di aplikasi.
Yang disimpan adalah `build_id`, arsitektur, dan alamat 2 frame teratas
(lokasi pemanggil dan fungsi yang memanggilnya), yang kemudian diterjemahkan
di komputer developer.

## Menerjemahkan log build `--split-debug-info`

1. Build dan **simpan folder symbols untuk setiap rilis**:
   ```
   flutter build apk --release --obfuscate --split-debug-info=build/symbols/1.2.3
   ```
2. Penguji mengirim log lewat menu Debug Info (email).
3. Salin body email ke file teks, mis. `log.txt`, lalu dari folder project aplikasi:
   ```
   dart run flutter_custom_trace:symbolize -d build/symbols -i log.txt
   ```
   - `-d` boleh berupa satu file `.symbols` atau folder (dicari rekursif).
     File yang cocok dipilih otomatis berdasarkan `build_id`, jadi folder
     berisi banyak versi/arsitektur tidak masalah.
   - Tambahkan `--json hasil.json` untuk menyimpan hasil dengan field `file`
     yang sudah diterjemahkan.

Contoh output:

```
[1] 21/11/2026 10:5:3 | Location Check
    lokasi: clocking.dart:372 (ClockingController.doClocking)
      dari: clocking.dart:120 (ClockingController.onTapClockIn)
    value : [{no: 12, value: 55.7}]
```

Jika muncul `file .symbols untuk build_id ... tidak ditemukan`, berarti APK di
HP penguji berasal dari build yang symbols-nya tidak disimpan / sudah tertimpa.

> `flutter symbolize` tidak dipakai karena pada Flutter versi terbaru crash
> (`Bad state: Future already completed`) dan tidak mengenali nama section
> snapshot yang baru (`_kDartSnapshotText`).
