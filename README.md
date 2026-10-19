<div align="center">

# Klasifikasi Tutupan Lahan Kabupaten Wonogiri

**Analisis indeks spektral Sentinel-2 L2A, klasifikasi berbasis threshold, statistik zonal per kecamatan, dan WebGIS interaktif (R Shiny + Leaflet)**

[![Dashboard](https://img.shields.io/badge/Dashboard-Buka%20Online-2E7D32?style=for-the-badge&logo=r&logoColor=white)](https://adambudi.shinyapps.io/tutupan-lahan-wonogiri/)
![R](https://img.shields.io/badge/R-Shiny-276DC3?style=for-the-badge&logo=r&logoColor=white)
![Sentinel-2](https://img.shields.io/badge/Data-Sentinel--2%20L2A-blue?style=for-the-badge)
![CRS](https://img.shields.io/badge/CRS-UTM%2049S-orange?style=for-the-badge)

Tugas Besar ETS, Pemrograman Spasial A
Teknik Geomatika, Institut Teknologi Sepuluh Nopember (ITS)

</div>

---

## Dashboard Online

Dashboard bisa dibuka siapa saja lewat browser, tanpa instalasi apa pun:

### [Tutupan Lahan](https://adambudi.shinyapps.io/tutupan-lahan-wonogiri/)

```
https://adambudi.shinyapps.io/tutupan-lahan-wonogiri/
```

> Dashboard di-host di shinyapps.io (paket gratis). Jika aplikasi sedang tidak aktif, halaman butuh beberapa detik untuk menyala kembali. Tunggu sampai tampilan muncul.

---

## Latar Belakang dan Tujuan

Informasi tutupan lahan dibutuhkan untuk perencanaan wilayah, pemantauan lingkungan, dan pengelolaan sumber daya. Citra satelit Sentinel-2 menyediakan data multispektral beresolusi 10 sampai 20 m yang gratis dan terbuka, sehingga cocok untuk memetakan tutupan lahan tingkat kabupaten.

Tujuan proyek ini:

1. Menghitung indeks spektral **NDVI, NDBI, NDWI, dan NDCI** dari citra Sentinel-2 L2A untuk Kabupaten Wonogiri.
2. Mengklasifikasikan tutupan lahan menjadi **vegetasi, bangunan, perairan, dan awan** dengan metode threshold.
3. Menghitung **statistik zonal** setiap indeks dan **luas tiap kelas** per kecamatan.
4. Menyajikan hasil dalam **peta cetak** (layout) dan **dashboard interaktif** yang dapat diakses publik.

---

## Data yang Digunakan

| Data | Keterangan | Sumber |
|---|---|---|
| Citra Sentinel-2 L2A | Band B03, B04, B05, B08, B11 (koreksi atmosfer, reflektansi permukaan) | Copernicus Data Space Ecosystem |
| Batas administrasi | RBI 25K 2022 (batas kabupaten dan kecamatan) | BIG melalui Ina-Geoportal |
| Peta dasar dashboard | Google Satellite dan peta dasar lainnya | HCMGIS / Leaflet providers |

Sistem koordinat seluruh analisis: **UTM Zona 49S (EPSG:32749)**.

---

## Alur Kerja

```
Citra Sentinel-2 L2A  +  Batas RBI 25K
              │
              ▼
   Pemotongan ke Kab. Wonogiri
              │
              ▼
 Konversi ke reflektansi (DN - 1000) / 10000
              │
              ▼
 Hitung indeks: NDVI, NDBI, NDWI, NDCI
              │
              ▼
 Klasifikasi threshold (vegetasi, bangunan, perairan, awan)
              │
              ▼
 Statistik zonal per kecamatan (indeks + luas kelas)
              │
              ├──► Tabel (CSV dan Word)
              ├──► Peta layout (QGIS dan R)
              └──► Dashboard Shiny + Leaflet
```

---

## Metode

### 1. Pra-pemrosesan

Nilai piksel Sentinel-2 L2A dikonversi menjadi reflektansi permukaan:

```
reflektansi = (DN - 1000) / 10000      (nilai negatif dibatasi menjadi 0)
```

Seluruh band dipotong sesuai batas Kabupaten Wonogiri dan diproyeksikan ke UTM 49S.

### 2. Indeks Spektral

| Indeks | Rumus | Kegunaan |
|---|---|---|
| NDVI | (B08 - B04) / (B08 + B04) | Kerapatan vegetasi |
| NDBI | (B11 - B08) / (B11 + B08) | Lahan terbangun |
| NDWI | (B03 - B08) / (B03 + B08) | Badan air |
| NDCI | (B05 - B04) / (B05 + B04) | Deteksi awan |

### 3. Klasifikasi Threshold

Aturan diterapkan berurutan. Aturan yang lebih akhir menimpa aturan sebelumnya.

| Urutan | Kelas | Aturan |
|---|---|---|
| 1 | Vegetasi | NDVI >= 0,30 |
| 2 | Bangunan | NDBI > 0,15 |
| 3 | Perairan | NDWI > 0 |
| 4 | Awan | NDCI <= 0,03 **dan** reflektansi band merah >= 0,20 |

### 4. Statistik Zonal

Untuk setiap kecamatan dihitung rata-rata, nilai minimum, dan nilai maksimum tiap indeks. Luas dan persentase tiap kelas tutupan lahan dihitung dari raster klasifikasi.

---

## Hasil

### Proporsi tutupan lahan Kabupaten Wonogiri

| Kelas | Proporsi |
|---|---|
| Vegetasi | 83,74 % |
| Bangunan | 13,93 % |
| Perairan | 1,50 % |
| Awan | 0,83 % |

### Temuan utama

- Wilayah analisis mencakup **25 kecamatan**.
- Kecamatan dengan NDVI rata-rata tertinggi: **Jatipurno (0,610)**.
- Kecamatan dengan NDVI rata-rata terendah: **Baturetno (0,334)**.
- Vegetasi mendominasi wilayah kabupaten, sedangkan perairan yang terdeteksi berkaitan dengan waduk dan badan air besar.

Tabel lengkap tersedia di folder `output/`:

| File | Isi |
|---|---|
| `zonal_statistics_kecamatan.csv` | Statistik zonal indeks per kecamatan |
| `luas_kelas_kecamatan.csv` | Luas dan persentase kelas per kecamatan |

---

## Peta

### Peta layout (QGIS)

![Peta layout QGIS](output/peta_layout_qgis.png)

### Peta klasifikasi (R)

![Peta klasifikasi R](output/peta_klasifikasi_layout.png)

Kelengkapan peta: judul, legenda, skala (meter), panah utara, grid koordinat UTM 49S, dan sumber data.

---

## Fitur Dashboard

Dashboard dibangun dengan **R Shiny**, **shinydashboard**, dan **Leaflet**.

| Menu | Isi |
|---|---|
| **Tutupan Lahan** | Peta klasifikasi interaktif, pilihan peta dasar, dan pengaturan transparansi layer |
| **Zonal Indeks per Kecamatan** | Peta tematik rata-rata NDVI, NDBI, NDWI, dan NDCI per kecamatan |
| **Statistik per Kecamatan** | Tabel statistik zonal dan histogram indeks |
| **Luas Kelas per Kecamatan** | Luas dan persentase tiap kelas tutupan lahan per kecamatan |

---

## Struktur Repository

```
Tutupan lahan/
├── Klasifikasi tutupan lahan.R    # Script analisis: indeks, klasifikasi, zonal, tabel
├── WebGIS.R                       # Script dashboard Shiny
├── app.R                          # Salinan WebGIS.R untuk deploy ke shinyapps.io
├── Tutupan lahan.Rproj            # Project RStudio
├── output/
│   ├── kecamatan_wonogiri.shp     # Batas kecamatan (beserta file pendampingnya)
│   ├── kabupaten_wonogiri.shp     # Batas kabupaten
│   ├── zonal_statistics_kecamatan.csv
│   ├── luas_kelas_kecamatan.csv
│   ├── klasifikasi_50m.tif        # Raster klasifikasi resolusi 50 m (ringan)
│   ├── web/                       # Raster per kelas untuk dashboard
│   ├── peta_layout_qgis.png
│   └── peta_klasifikasi_layout.png
├── README.md
└── .gitignore
```

> Citra Sentinel-2 mentah dan raster beresolusi penuh tidak diunggah ke repository karena melebihi batas ukuran file GitHub (100 MB).

---

## Cara Menjalankan

### Opsi 1: Buka dashboard online

Cukup klik: **https://adambudi.shinyapps.io/tutupan-lahan-wonogiri/**

### Opsi 2: Jalankan dashboard di komputer sendiri

1. Clone repository:
```bash
   git clone https://github.com/adambudi/Tugas-Besar-ETS-Pemrograman-Spasial.git
```
2. Buka folder hasil clone di RStudio.
3. Pasang paket yang dibutuhkan (samakan dengan `library(...)` di `app.R`):
```r
   install.packages(c("shiny", "shinydashboard", "leaflet", "leaflet.extras",
                      "sf", "dplyr", "terra", "raster"))
```
4. Jalankan:
```r
   shiny::runApp("app.R")
```

Pastikan folder `output/` berada di folder yang sama dengan `app.R`.

### Opsi 3: Ulangi seluruh analisis

1. Unduh citra Sentinel-2 L2A area Wonogiri dari Copernicus Data Space Ecosystem dan batas RBI 25K dari Ina-Geoportal.
2. Atur path data di bagian awal `Klasifikasi tutupan lahan.R`.
3. Jalankan script dari atas ke bawah. Hasil akan tersimpan di folder `output/`.

---

## Keterbatasan

- Klasifikasi memakai **threshold tetap** (tanpa training data), sehingga hasilnya bisa tertukar antar kelas pada area yang spektralnya mirip, misalnya lahan terbuka dan bangunan.
- Kelas **awan** dideteksi dari satu tanggal akuisisi. Bayangan awan tidak diklasifikasikan secara khusus.
- Belum ada **uji akurasi** terhadap data referensi lapangan.
- Resolusi dashboard diturunkan (50 m) agar ringan dan cepat dimuat.

---

## Sumber Data dan Atribusi

- Contains modified Copernicus Sentinel data (2026), diunduh dari Copernicus Data Space Ecosystem.
- Batas administrasi: RBI 25K 2022, Badan Informasi Geospasial (BIG), melalui Ina-Geoportal.
- Peta dasar: Google Satellite © Google, melalui HCMGIS.

---

## Anggota Kelompok

| Nama | Program Studi |
|---|---|
| Adam Budi Kusumo | 5016241135 |
| Alif Putra Dewangga | 5016241121 |

Mata kuliah: Pemrograman Spasial A, 2026