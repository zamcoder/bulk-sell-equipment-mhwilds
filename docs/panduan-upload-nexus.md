# Panduan rilis ke Nexus Mods

Panduan ini untuk maintainer: cara membuat zip rilis lalu meng-upload-nya ke halaman Monster Hunter Wilds di Nexus Mods.

## 1. Siapkan versi

1. Naikkan `VERSION` di `src/reframework/autorun/BulkSell.lua`, misalnya `"0.2.3"` menjadi `"0.3.0"`.
2. Jalankan test, lalu pastikan hasilnya `syntax errors: 0, failing test files: 0`:
   ```powershell
   .venv\Scripts\python.exe -I tools\check.py
   ```
3. Buat zip rilis:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\package.ps1
   ```
   Hasilnya ada di `dist\BulkSellEquipment-<versi>.zip`. Isinya `modinfo.ini` dan folder `reframework/autorun/...`. Probe dev tidak ikut masuk.

## 2. Uji zip-nya seperti pemain baru

1. Hapus dulu file hasil deploy manual dari folder game:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -Remove
   ```
2. Buka **Fluffy Mod Manager**, pilih Monster Hunter Wilds, lalu import zip dari `dist\` (jangan diekstrak) dan aktifkan **Bulk Sell Equipment**.
3. Jalankan game. Di menu REFramework (Insert), buka Script Generated UI → Bulk Sell Equipment, lalu pastikan versinya benar dan **Scan** berjalan.
4. Ambil 2–3 screenshot untuk halaman Nexus. Pakai F12 Steam atau Win+Shift+S:
   - window Bulk Sell setelah Scan;
   - daftar "To sell";
   - konfirmasi atau hasil "Sold N talismans".

   Pastikan tidak ada nama karakter atau info pribadi yang tidak ingin kamu tampilkan.

## 3. Upload ke Nexus Mods

1. Login di https://www.nexusmods.com, lalu buka halaman game **Monster Hunter Wilds**.
2. Klik **Upload** di pojok kanan atas dan pilih **Upload a mod** (atau buka *Mods → Upload a mod*). Urutan tab di Nexus bisa sedikit berbeda, tapi isinya sama seperti di bawah.

**Tab Mod details**

| Kolom | Isi |
|---|---|
| Name | `Bulk Sell Equipment` |
| Summary | `Safely bulk sell appraised talismans you no longer need: duplicates, covered ones, or everything outside your best N per skill, at the game's own price. Protects equipped, loadout, favorite and decorated talismans.` |
| Description | Tempel isi `docs/nexus-description.bbcode`. Editor Nexus menerima BBCode. |
| Category | **Utilities**. Kalau tidak ada, pilih yang paling dekat, misalnya *Gameplay*. |
| Version | Sama dengan `VERSION` |
| Language | English |
| Author | `evilryosaki` |
| Tags | Contoh: Talismans, Charms, Utility, REFramework, Quality of Life |

**Tab Media**

Upload screenshot dari langkah 2. Pilih satu sebagai gambar utama.

**Tab Files**

| Kolom | Isi |
|---|---|
| File | Upload `dist\BulkSellEquipment-<versi>.zip` |
| File name | `Bulk Sell Equipment` |
| Version | Sama dengan `VERSION` |
| Category | **Main Files** |
| Description | Contoh: `Fluffy Mod Manager ready. Requires REFramework.` |
| Mod manager download | Aktifkan kalau ada opsinya |

**Tab Requirements**

- Di **Nexus requirements**, cari dan tambahkan **REFramework** untuk Monster Hunter Wilds.
- Opsional, di **Off-site requirements**, tambahkan link REFramework nightly: https://github.com/praydog/REFramework-nightly/releases

**Tab Permissions**

- Isi **Credits** sesuai bagian Credits di README.
- Pilih izin sesuai keinginan: apakah orang lain boleh memakai ulang aset, mengubah, atau meng-upload ulang.
- Repo memakai lisensi **MIT** (file `LICENSE`), jadi orang lain boleh memakai ulang dan mengubah kodenya. Sesuaikan isian izin di tab ini dengan lisensi itu.

**Publish**

Cek pratinjau halaman, lalu klik **Publish**.

## 4. Merilis update

1. Ubah kode, naikkan `VERSION`, lalu tambah entri baru di `CHANGELOG.md`.
2. Jalankan `tools\check.py` dan `tests\test_tools.ps1`, lalu `tools\package.ps1`.
3. Di halaman mod Nexus, buka **Mod details** dan ubah kolom **Version** ke versi baru. Langkah ini sempat terlewat waktu v0.2.2 di-upload, sehingga kolomnya masih tertulis "1". Kalau versinya tidak diubah, pengecekan update di Nexus/Vortex jadi salah.
4. Buka **Manage → Files**, upload zip baru sebagai **Main Files** dengan versi yang sama, lalu pindahkan file lama ke **Old versions** (atau *Archived*).
5. Isi **Changelog** di halaman mod. Teksnya bisa disalin dari `CHANGELOG.md`.
6. Commit lalu push ke GitHub. Sebaiknya beri tag versi:
   ```powershell
   git tag v1.0.0
   git push origin main --tags
   ```

## 5. Checklist sebelum publish

- [ ] Test lolos (`tools\check.py` dan `tests\test_tools.ps1`)
- [ ] Entri baru di `CHANGELOG.md`
- [ ] Zip sudah diuji lewat Fluffy di instalasi yang bersih (probe dev sudah dilepas)
- [ ] `VERSION` di kode, di `modinfo.ini` (otomatis dari package), dan di Nexus sama
- [ ] README dan deskripsi Nexus sudah sesuai dengan fitur versi ini
- [ ] Screenshot tidak menampilkan info pribadi
- [ ] Requirement REFramework sudah ditambahkan
