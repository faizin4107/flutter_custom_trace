## Unreleased

* Redaksi permanen sebelum disimpan (`normalize`) dan lewat
  `CustomTrace.redact(text)`: nilai kunci password (`CustomTrace.passwordKeys`,
  mis. `password`, `new_password`) menjadi `*****`; kredensial
  (`CustomTrace.sensitiveKeys`, mis. `x-orange-token`, `x-orange-signature`,
  `fcm_token`, `secret_key`, `x-ai-apikey`, `Authorization: Bearer`) disamarkan
  sebagian (6 karakter awal + `…` + 4 akhir; ≤ 12 karakter → `***`).

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
