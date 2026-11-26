## Unreleased

* `CustomTrace.setEnabled(bool)` / `CustomTrace.enabled`: aplikasi bisa
  mengaktifkan / menonaktifkan pencatatan. Saat nonaktif tidak ada akses
  SharedPreferences sama sekali; catatan di antrean dibatalkan. Bila belum
  diatur (`null`), tetap memakai perilaku lama (cek `is_debug`).
* `saveTrace` / `saveError` kini mengembalikan `Future<void>` dan tidak pernah
  melempar (dulu `void async`: kegagalan SharedPreferences lolos sebagai error
  async yang tidak tertangkap).
* Penulisan `debug_info` diantrekan agar penyimpanan bersamaan tidak saling
  menimpa.
* `debug_info` dibatasi `CustomTrace.maxDebugInfo` (default 200, terlama
  dibuang) dan `value` per catatan `CustomTrace.maxValueLength` (default 4000).

## 0.0.1

* TODO: Describe initial release.
