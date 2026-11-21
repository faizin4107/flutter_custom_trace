/// Lokasi kode dari stack trace "non-symbolic" (DWARF), yaitu stack trace
/// build release dengan `--split-debug-info` (dan/atau `--obfuscate`).
///
/// Stack trace seperti ini tidak memuat nama file/baris, hanya alamat memori:
/// ```
/// *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
/// os: android arch: arm64 comp: yes sim: no
/// build_id: '13c06b791d8f2766911c6d4b25f8b194'
/// isolate_dso_base: 7a00000000, vm_dso_base: 7a00000000
/// isolate_instructions: 7a00320000, vm_instructions: 7a00320000
///     #00 abs 0000007a00b40000 virt 0000000000b40000 _kDartSnapshotText+0x820000
/// ```
/// Yang disimpan cukup `build_id`, `arch`, dan alamat `virt` beberapa frame
/// teratas. Alamat ini diterjemahkan ke file/baris di komputer developer dengan
/// file `.symbols` dari build yang sama:
/// `dart run flutter_custom_trace:symbolize -d <folder symbols> -i <log>`.
///
/// File ini sengaja pure Dart (tanpa Flutter) agar bisa dipakai oleh tool CLI.
class DwarfLocation {
  /// Build ID snapshot, dipakai untuk mencocokkan file `.symbols`.
  final String buildId;

  /// Arsitektur CPU (mis. `arm64`, `arm`, `x64`), jika tersedia.
  final String? arch;

  /// Alamat virtual frame teratas. Index 0 = pemanggil `StackTrace.current`,
  /// index 1 = pemanggil fungsi tersebut, dst.
  final List<int> virtualAddresses;

  const DwarfLocation({required this.buildId, this.arch, required this.virtualAddresses});

  /// Jumlah frame yang disimpan.
  static const int maxFrames = 2;

  static final RegExp _buildIdRe = RegExp(r"build_id(?:=|: )'([\da-f]+)'");
  static final RegExp _archRe = RegExp(r'arch(?:=|: )(\w+)');
  static final RegExp _dsoBaseRe = RegExp(r'isolate_dso_base(?:=|: )([\da-f]+)');
  static final RegExp _frameRe = RegExp(r'#(\d+) abs ([\da-f]+)(?: unit \d+)?(?: virt ([\da-f]+))?');

  /// Penanda yang disimpan di field `file`, mis.
  /// `dwarf:build_id=13c0...;arch=arm64;virt=b40000,b3ff10`.
  static final RegExp tokenRe = RegExp(r'dwarf:build_id=([\da-f]+);arch=(\w*);virt=([\da-f,]+)');

  /// Baca dari teks stack trace. Mengembalikan `null` jika bukan format DWARF.
  static DwarfLocation? fromStackTrace(String trace) {
    final buildId = _buildIdRe.firstMatch(trace)?.group(1);
    if (buildId == null) return null;
    final arch = _archRe.firstMatch(trace)?.group(1);
    final dsoBase = int.tryParse(_dsoBaseRe.firstMatch(trace)?.group(1) ?? '', radix: 16);

    final addresses = <int>[];
    for (final m in _frameRe.allMatches(trace)) {
      int? virt = m.group(3) == null ? null : int.tryParse(m.group(3)!, radix: 16);
      if (virt == null && dsoBase != null) {
        final abs = int.tryParse(m.group(2)!, radix: 16);
        if (abs != null) virt = abs - dsoBase;
      }
      if (virt != null) addresses.add(virt);
      if (addresses.length >= maxFrames) break;
    }
    if (addresses.isEmpty) return null;
    return DwarfLocation(buildId: buildId, arch: arch, virtualAddresses: addresses);
  }

  /// Baca penanda [tokenRe] dari teks (mis. field `file`).
  static DwarfLocation? fromToken(String text) {
    final m = tokenRe.firstMatch(text);
    if (m == null) return null;
    final addresses = m
        .group(3)!
        .split(',')
        .where((s) => s.isNotEmpty)
        .map((s) => int.parse(s, radix: 16))
        .toList();
    final arch = m.group(2)!;
    return DwarfLocation(buildId: m.group(1)!, arch: arch.isEmpty ? null : arch, virtualAddresses: addresses);
  }

  /// Penanda untuk disimpan di field `file`.
  String toToken() =>
      'dwarf:build_id=$buildId;arch=${arch ?? ''};virt=${virtualAddresses.map((a) => a.toRadixString(16)).join(',')}';

  @override
  String toString() => toToken();
}
