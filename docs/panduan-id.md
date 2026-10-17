# Bulk Sell Equipment: panduan pemula (Bahasa Indonesia)

Panduan ini menjelaskan cara memakai mod, langkah demi langkah, dengan contoh. Kamu tidak perlu membaca semuanya. Mulai dari **Bagian 1**, lalu buka bagian lain kalau perlu. Nama tombol ditulis dalam bahasa Inggris, persis seperti di game.

- [Bagian 1: penjualan pertama dalam 6 langkah](#bagian-1-penjualan-pertama-dalam-6-langkah)
- [Bagian 2: pilih opsi Keep yang mana?](#bagian-2-pilih-opsi-keep-yang-mana)
- [Bagian 3: cara membaca window](#bagian-3-cara-membaca-window)
- [Bagian 4: cara melakukan... (resep)](#bagian-4-cara-melakukan-resep)
- [Bagian 5: konfirmasi](#bagian-5-konfirmasi)
- [Bagian 6: pesan dan yang harus dilakukan](#bagian-6-pesan-dan-yang-harus-dilakukan)
- [Bagian 7: arti istilah](#bagian-7-arti-istilah)

---

## Bagian 1: penjualan pertama dalam 6 langkah

**Sebelum mulai:** backup save dulu (ada di `Steam\userdata\<id kamu>\2246340\remote`). Penjualan tidak bisa dibatalkan, dan game tidak punya fitur beli kembali. Main sendiri (bukan co-op), berdiri di camp atau di lapangan, dan tutup semua menu game.

1. **Buka window.** Tekan **Insert** (menu REFramework). Buka **Script Generated UI → Bulk Sell Equipment**, lalu klik **Show window**.
2. **Scan.** Klik **Scan Equipment Box**. Ini hanya membaca talisman, tidak menjual apa pun. Akan muncul baris seperti:
   > Scanned 11:53:38 · 1029 appraised (13 protected) · Box 2087 / 2400 (313 free)

   Artinya: ada 1.029 talisman appraised, 13 di antaranya dilindungi, dan box terisi 2.087 dari 2.400 (sisa 313).
3. **Pilih apa yang disimpan.** Buka daftar **Keep**. Setiap pilihan langsung menunjukkan berapa yang akan terjual dan berapa zenny-nya, misalnya:
   > Keep the best 10 per skill - 273 to sell (1,363,000 z)

   Untuk percobaan pertama, pilih **Keep every unique talisman**. Pilihan ini hanya menjual duplikat dan talisman yang kalah total dari talisman lain yang disimpan.
4. **Lihat daftarnya.** Setiap baris menunjukkan apa yang akan terjadi dan alasannya. Kalau ada yang ingin kamu simpan, hapus centang di barisnya. Belum ada yang terjual.
5. **Tes satu dulu.** Klik **Sell just 1 (test)**, lalu **Yes, sell**. Mod akan menjual satu talisman yang paling murah di daftar. Cek bahwa zenny-mu bertambah.
6. **Jual sisanya.** Klik **Sell N talismans**, centang kotak yang diminta konfirmasi, lalu klik **Yes, sell**. Setelah itu biarkan game melakukan autosave, misalnya dengan fast travel sekali. Penjualan baru tersimpan permanen setelah autosave.

Sudah, selesai. Bagian lain di bawah membantu kalau kamu ingin menjual lebih banyak, atau ingin mengatur dengan tepat apa yang disimpan.

---

## Bagian 2: pilih opsi Keep yang mana?

| Kamu ingin... | Pilih | Yang dijual |
|---|---|---|
| Hanya menjual yang kamu centang sendiri | **Keep everything (sell only what I tick)** | Tidak ada, kecuali yang kamu centang |
| Bersih-bersih yang aman | **Keep every unique talisman** | Duplikat, dan talisman yang kalah total dari talisman lain yang disimpan (semua skill dan slot-nya sama atau lebih jelek) |
| Sedikit ruang | **Keep the best 10 per skill** | Semua yang tidak masuk 10 terbaik di skill mana pun dan di bentuk slot-nya |
| Banyak ruang | **Keep the best 5** atau **3 per skill** | Lebih banyak lagi; hanya 5 (atau 3) terbaik per skill dan per bentuk slot yang disimpan |
| Ruang sebanyak mungkin | **Keep the best 2** atau **1 per skill** | Hampir semua, kecuali yang paling bagus per skill dan bentuk slot |

**Contoh dari box asli (1.029 talisman, box terisi 2.087 / 2.400):**

| Opsi Keep | Terjual | Zenny | Box setelahnya |
|---|---|---|---|
| Keep every unique talisman | 0 | 0 z | 2.087 / 2.400 |
| Keep the best 10 per skill | 273 | 1.363.000 z | 1.814 / 2.400 |
| Keep the best 5 per skill | 563 | 2.878.000 z | 1.524 / 2.400 |
| Keep the best 3 per skill | 735 | 3.852.500 z | 1.352 / 2.400 |
| Keep the best 1 per skill | 914 | 4.831.500 z | 1.173 / 2.400 |

Di box ini sudah tidak ada duplikat atau talisman yang kalah total, jadi "Keep every unique talisman" menjual 0.

**Tips: jual bertahap.** Pilih best 10, jual, lalu lihat sisanya. Setelah itu best 5 (di box ini artinya 290 talisman lagi), dan seterusnya. Setiap tahap kamu bisa mengecek daftarnya dulu.

**Kenapa aman?** Untuk setiap skill, talisman terbaikmu selalu disimpan, jadi level terbaik setiap skill tidak pernah hilang dari box. Hal yang sama berlaku untuk setiap bentuk slot, misalnya talisman terbaik dengan slot ukuran 3. Penjelasan lengkap cara mengurutkannya, beserta contoh tabel Poison Resistance, ada di [README](../README.md#how-keep-the-best-n-per-skill-works).

**Slider rarity.** Untuk opsi *best N* juga ada slider **Sell unique talismans only up to rarity**. Kalau di angka **8**, semua rarity bisa dijual. Kalau di **6**, talisman unik yang dijual hanya R5 dan R6, sedangkan R7 dan R8 disimpan. Duplikat dan talisman yang kalah total tetap dijual.

---

## Bagian 3: cara membaca window

Dari atas ke bawah, window-nya terdiri dari bagian berikut.

**A. Baris scan**
> Scanned 11:53:38 · 1029 appraised (13 protected) · Box 2087 / 2400 (313 free)

Baris ini berubah kuning kalau sisa slot box kurang dari 50, dan merah kalau kurang dari 10.

**B. Opsi Keep dan panel Skills**
- Daftar **Keep**, slider **rarity** (untuk opsi *best N*), dan tanda **(?)** yang menjelaskan cara kerjanya.
- **Skills: 0 keep all · 0 custom · 0 don't care**: klik untuk membuka pengaturan per skill (lihat Bagian 4).

**C. Ringkasan**
> Sell 273 · keep 756 · about 1,363,000 z · box after the sale 1814 / 2400
> Duplicates 0 · covered 0 · unique 273 · your picks 0 (sell 0 / keep 0) · protected 13
> To sell by rarity: R5 1 · R6 60 · R7 147 · R8 65
> Your best 10 for every skill and slot shape stay. No skill level leaves your box.

- **Garis hijau** adalah janji mod: tidak ada yang penting yang hilang dari box.
- **Garis kuning** muncul kalau pilihanmu sendiri (centang, atau skill yang kamu set Don't care) akan menghilangkan sebuah level skill. Konfirmasi nanti menunjukkan detailnya.
- **Last change: ...** menjelaskan apa yang berubah karena klik terakhir atau scan terakhir. Tombol **Show changed** menampilkan talisman-talisman yang berubah itu.

**D. Tombol jual**
- **Sell N talismans**: menjual semua yang direncanakan.
- **Sell the N shown**: hanya menjual baris yang sedang tampil di filter (lihat E).
- **Sell just 1 (test)**: menjual satu baris termurah yang sedang tampil.

**E. Tools** (klik untuk membuka): bintang dan export (lihat Bagian 4).

**F. Daftar**
- **Show**: To sell, To keep, All, Your picks, Unique sales, Changed by last edit, Last of their kind.
- **Find**: ketik nama skill (misalnya `attack`) atau nomor box (`#857`).
- **R5 R6 R7 R8**: hanya tampilkan rarity ini.
- **Mark shown: Sell / Keep / Auto**: centang, hapus centang, atau kembalikan ke aturan semua baris yang sedang tampil. **Undo** membatalkan satu langkah.

Kolom-kolomnya:

| Kolom | Artinya |
|---|---|
| Sell | Tercentang = akan dijual. Klik untuk mengubah keputusan (muncul `*` di nomor box) |
| Box | Posisi talisman di Equipment Box |
| Talisman, Slots, Price | Talismannya, slot-nya, dan harga jualnya |
| Verdict | **Sell · duplicate**, **Sell · covered**, **Sell · unique**, **Sell · your pick**, atau **Keep · ...** |
| Why | Alasannya, misalnya "Same as #1032 (kept)" atau "Ambush #1 of 21" |

**Cara membaca kolom Why, dengan contoh:**

| Tulisan di Why | Artinya |
|---|---|
| Same as #1032 (kept) | Ada talisman yang persis sama dan disimpan (box 1032) |
| Covered by #875 R8 Critical Eye 3, Flayer 1 | Box 875 punya semua skill-nya dengan level sama atau lebih tinggi, dan slot yang minimal sama bagus |
| Not in your best 3 · closest Item Prolonger #10 of 12 | Talisman ini unik, tapi tidak masuk 3 besar di skill mana pun. Posisi terbaiknya ke-10 dari 12 untuk Item Prolonger |
| Ambush #1 of 21 | Disimpan: ini talisman Ambush terbaikmu (dari 21) |
| Slot shape A3 #2 of 18 | Disimpan: ini talisman terbaik kedua dengan slot ukuran 3 |
| Favorite: remove the star in game to sell it | Dilindungi karena berbintang, tidak pernah dijual |

---

## Bagian 4: cara melakukan... (resep)

### Menyimpan satu talisman yang mau dijual mod
Hapus centang di kotak **Sell**-nya. Baris itu berubah jadi **Keep · your pick** dan diberi tanda `*`. Centang dan hapus-centang darimu disimpan, dan selalu menang atas aturan.

### Menjual satu talisman yang mau disimpan mod
Centang kotak **Sell**-nya, maka baris itu jadi **Sell · your pick**. Kalau talisman itu satu-satunya pemilik level skill tertentu, kolom Why memberi tahu dengan warna merah, misalnya "Your pick · LAST Fire Resistance 3". Konfirmasi nanti juga meminta kamu menyetujui kehilangan itu.

### Membatalkan semua centangmu
Pilih **Show → Your picks**, lalu klik **Mark shown: Auto**. Semua pick dihapus, dan aturan yang menentukan lagi.

### Menyimpan semua talisman yang punya skill tertentu
Buka **Skills**, cari skill-nya lewat **Find skill**, lalu set Keep-nya ke **Keep all**. Talisman dengan skill itu tidak akan pernah dijual sebagai talisman unik. Pilihan "Keep all Lv2+" sama, tapi hanya untuk level 2 ke atas. Catatan: duplikat dan salinan yang kalah total tetap dijual, karena talisman yang lebih bagus dengan skill yang sama tetap ada di box.

### Menyimpan lebih banyak (atau lebih sedikit) untuk satu skill
Di **Skills**, set skill itu ke **Best 10** (atau Best 1, dan seterusnya). Contoh: semua skill pakai best 3, tapi khusus Attack Boost best 10.

### Mengabaikan sebuah skill (misalnya resistance)
Di **Skills**, ketik `Resistance` di **Find skill**, lalu klik **Don't care** di baris "Set the N shown to". Kalau perubahan menyentuh lebih dari 10 skill, mod akan bertanya dulu.

Don't care artinya skill itu tidak dihitung lagi saat talisman dibandingkan. Talisman yang kelebihannya hanya di skill itu sekarang dianggap kalah total atau duplikat, lalu dijual. Kalau karena itu level terbaik sebuah skill Don't care ikut hilang, ringkasan menampilkan garis kuning, dan konfirmasi menampilkannya di blok merah. Contohnya:
> Fire Resistance 3 (best left 2) #2292 - Don't care

Berubah pikiran? Klik **Undo** di panel Skills, atau **Reset all**.

### Menjual semua talisman R5, seperti aturan rarity yang lama
Pilih **Show → All**, hapus centang **R6 R7 R8** sehingga hanya R5 yang tersisa, lalu klik **Mark shown: Sell**. Talisman yang dilindungi otomatis dilewati. Konfirmasi akan menunjukkan apa saja yang hilang.

### Mengosongkan box dengan aman, bertahap
1. Pilih **Keep the best 10 per skill**, jual, lalu biarkan game autosave.
2. Lain kali, pilih **best 5**, cek daftarnya, lalu jual.
3. Kalau masih butuh ruang, lanjut ke **best 3**.

### Menandai yang disimpan dengan bintang game
Buka **Tools**, klik **Star the N kept...**, lalu **Yes**. Semua talisman yang disimpan diberi bintang favorite dari game. Bulk Sell tidak pernah menjual favorite, mod lain seperti Talisman Analyser juga melewatinya, dan bintangnya terlihat di menu game, jadi jadi pengingat kalau kamu jual atau melding sendiri. Tombol **Remove stars Bulk Sell added (N)...** menghapus tepat bintang-bintang itu lagi. Bintang yang kamu pasang sendiri tidak pernah disentuh.

### Export talisman ke mhwilds.wiki-db.com
1. Buka **Tools**. Pilih **Export** (semua talisman, yang tersisa setelah penjualan, atau hanya yang akan dijual) dan **Names** (sesuaikan dengan bahasa situsnya).
2. Klik **Copy for mhwilds.wiki-db.com**. Teksnya masuk ke clipboard, dan juga disimpan di `reframework/data/BulkSell/export/`.
3. Buka https://mhwilds.wiki-db.com/sim/?hl=en, masuk ke tab **Talisman**, tempel di **Import/Export Charms**, lalu tekan **Import**.

Hati-hati: import **mengganti** seluruh daftar talisman di situs itu. Kalau mau file spreadsheet, pakai **Save CSV**.

### Membandingkan zenny dengan Melding Pot
Ringkasan menampilkan keduanya, misalnya:
> Selling these gives 1,363,000 z. Melding them would give 1,713 Melding Pot points instead, but melding makes new talismans to appraise, so it does not empty your box.

Artinya: dijual dapat 1.363.000 z. Kalau dimasukkan ke Melding Pot dapat 1.713 poin, tapi melding menghasilkan talisman baru yang harus di-appraise, jadi box tidak jadi lebih kosong.

---

## Bagian 5: konfirmasi

Saat kamu klik tombol Sell, mod tidak langsung menjual. Yang muncul adalah konfirmasi:

> Sell 273 talismans for 1,363,000 z? This cannot be undone.
> 273 are unique: no identical or better talisman stays. For each of their skills and slot shapes you keep at least 10 that rank higher.
> [ ] I understand that unique talismans are sold.

- **Centang unik:** wajib kalau penjualan berisi talisman unik. Mod mengingat centang ini selama setting-nya sama. Mod akan bertanya lagi kalau setting berubah, atau kalau jumlah talisman unik yang dijual lebih banyak dari sebelumnya.
- **Blok merah** ("This sale removes: ...") berisi setiap level skill atau bentuk slot yang akan hilang dari box, beserta nomor box-nya. Blok ini hanya muncul karena centangmu sendiri atau karena setting Don't care. Centang **I accept losing these** hanya kalau kamu memang mau.
- Tombol **Yes, sell** baru muncul setelah semua kotak wajib dicentang. Konfirmasi hangus setelah 20 detik. Kalau ada yang berubah, konfirmasi ditarik dengan pesan "The list changed; review and press Sell again".
- Selama penjualan berjalan, tombol **Stop** menghentikannya setelah talisman yang sedang dijual. Setiap penjualan juga menulis receipt di `reframework/data/BulkSell/receipts/`.

---

## Bagian 6: pesan dan yang harus dilakukan

| Pesan | Yang harus dilakukan |
|---|---|
| The box may have changed. Rescanning... | Tidak perlu apa-apa. Mod scan ulang karena kamu menutup menu atau membuka menu game. Tunggu sebentar. |
| Close the game menu first. / Close the equipment menu first. | Tutup menu game. Penjualan menunggu sampai tidak ada menu yang terbuka. |
| Waiting for the game to finish saving. | Tunggu sebentar. |
| Nothing more to sell: every talisman is unique. | Box-mu sudah tidak punya duplikat atau talisman yang kalah total. Pilih opsi *Keep the best N* kalau ingin menjual lebih banyak. |
| RNG Charm Crafting file ... could not be read | Penjualan dimatikan supaya talisman bonus tidak ikut terjual. Tutup game, perbaiki atau hapus file itu, lalu buka game lagi. |
| Your saved Sell/Keep ticks could not be read | Klik **Continue without my picks** (centang yang tersimpan akan hilang), atau tutup game lalu pulihkan file-nya. |
| Held back by a safety check - please report | Mod menolak menjual satu talisman karena ada pengecekan yang gagal. Tolong laporkan beserta file-file di bawah. |
| Some names were not available in that language | Beberapa nama skill di file export memakai bahasa game. |

**Kalau ada masalah:** centang **Write debug files** (di Script Generated UI → Bulk Sell Equipment), lalu scan lagi. Lampirkan tiga file ini:
- file terbaru dari `reframework/data/BulkSell/debug/`;
- receipt terakhir;
- `re2_framework_log.txt` dari folder game.

---

## Bagian 7: arti istilah

| Istilah | Artinya |
|---|---|
| Appraised talisman | Unknown, Historical, Secret, atau Golden Age Charm (R5 sampai R8). Hanya jenis ini yang diurus mod |
| Protected (dilindungi) | Talisman yang sedang dipakai, ada di loadout, berbintang, berdekorasi, atau punya bonus RNG Charm Crafting. Tidak pernah dijual |
| Duplicate (duplikat) | Salinan persis (skill, level, dan slot sama) dari talisman yang disimpan |
| Covered (kalah total) | Ada talisman lain yang disimpan dengan semua skill-nya sama atau lebih tinggi, dan slot yang bisa menampung semua slot-nya |
| Unique (unik) | Bukan duplikat dan tidak kalah total: tidak ada talisman tersimpan yang lebih bagus di semua hal |
| Slot shape (bentuk slot) | Susunan slot, misalnya A3, A2 A1, atau W1 A1 A1 (W = slot weapon, A = slot armor) |
| Best N | N talisman dengan peringkat tertinggi untuk sebuah skill atau bentuk slot |
| Pick | Centang atau hapus-centang darimu di sebuah baris. Selalu menang atas aturan (ditandai `*`) |
| Keep all | Setting skill: talisman dengan skill ini tidak pernah dijual sebagai talisman unik |
| Don't care | Setting skill: skill ini diabaikan saat talisman dibandingkan |
