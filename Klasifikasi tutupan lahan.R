# ==============================================================
# Tugas Besar Pemrograman Spasial A
# Klasifikasi tutupan lahan Kabupaten Wonogiri (Sentinel-2 L2A)
# Alur: batas administrasi -> citra -> indeks -> klasifikasi
#       -> zonal statistics -> tabel Word -> data untuk dashboard
# ==============================================================
# Jalankan dari atas ke bawah. Pastikan working directory = folder project
# (folder yang akan berisi output/ dan app.R), mis.:
# setwd("C:/Users/ALIF/Documents/Semester 5/Pemspa")

# 1. Package -----------------------------------------------------------
library(sf)
library(dplyr)
library(terra)
library(flextable)
library(officer)

# 2. Lokasi data --------------------------------------------------------
gdb <- "C:/Users/ALIF/Downloads/Tutupan lahan/Tutupan lahan/Wonogiri zip/Wonogiri/KAB WONOGIRI/2022_RBI25K_KAB_WONOGIRI_KUGI50_20221231.gdb"
folder_s2 <- "C:/Users/ALIF/Downloads/Tutupan lahan/Tutupan lahan"   # folder berisi tile .SAFE

dir.create("output",        showWarnings = FALSE)
dir.create("output/band",   showWarnings = FALSE)
dir.create("output/indeks", showWarnings = FALSE)
dir.create("output/web",    showWarnings = FALSE)

# ==============================================================
# TAHAP 1: Batas administrasi
# ==============================================================

# 3. Cek layer pada geodatabase ----------------------------------------
lyr    <- st_layers(gdb)
daftar <- data.frame(nama = lyr$name, tipe = unlist(lyr$geomtype))
daftar[grepl("ADM|BATAS|KEC|DESA|WILAYAH", daftar$nama, ignore.case = TRUE), ]

# 4. Baca batas kecamatan dan buang dimensi Z ----------------------------
kec <- st_read(gdb, layer = "ADMINISTRASI_AR_KECAMATAN")
kec <- st_zm(kec, drop = TRUE, what = "ZM")

# 5. Cek isi data (RBI memuat beberapa kabupaten) ------------------------
names(kec)
table(kec$WADMKK)

# 6. Filter Kabupaten Wonogiri --------------------------------------------
kec <- kec[kec$WADMKK == "Wonogiri", ]
nrow(kec)                 # 25 kecamatan
sort(kec$WADMKC)

# 7. Batas kabupaten = gabungan seluruh kecamatan ---------------------------
kab <- st_union(kec) |> st_as_sf()
nrow(kab)                 # 1 poligon

# 8. Samakan CRS dengan Sentinel-2 (UTM 49S, EPSG:32749) --------------------
kec_utm <- st_transform(kec, 32749)
kab_utm <- st_transform(kab, 32749)
st_crs(kec_utm)$input

# 9. Simpan ------------------------------------------------------------------
st_write(kec_utm, "output/kecamatan_wonogiri.shp", delete_layer = TRUE)
st_write(kab_utm, "output/kabupaten_wonogiri.shp", delete_layer = TRUE)

# 10. Plot batas administrasi ------------------------------------------------
plot(st_geometry(kec_utm))
plot(st_geometry(kab_utm), add = TRUE, border = "red", lwd = 2)

png("output/plot_administrasi_wonogiri.png", width = 1600, height = 1600, res = 200)
plot(st_geometry(kec_utm), main = "Batas Administrasi Kabupaten Wonogiri")
plot(st_geometry(kab_utm), add = TRUE, border = "red", lwd = 2)
dev.off()

# ==============================================================
# TAHAP 2: Sentinel-2 L2A -> crop, mosaic, mask
# Tile: T49MDM, T49MEM, T49LDL (14 Oktober 2026)
# ==============================================================

# 11. Batas Wonogiri dalam format terra -------------------------------------
kab_v <- vect(kab_utm)

# 12. Fungsi: baca satu band dari semua tile, crop, mosaic -------------------
baca_band <- function(kode, res) {
  pola  <- paste0("_", kode, "_", res, "m\\.jp2$")
  files <- list.files(folder_s2, pattern = pola,
                      recursive = TRUE, full.names = TRUE)
  files <- files[grepl("IMG_DATA", files)]
  
  daftar <- list()
  for (f in files) {
    x <- rast(f)
    # lewati tile yang tidak menyentuh Wonogiri
    if (is.null(terra::intersect(ext(x), ext(kab_v)))) next
    x <- crop(x, ext(kab_v), snap = "out")
    x[x == 0] <- NA                       # 0 = area tanpa data
    daftar[[length(daftar) + 1]] <- x
  }
  cat(kode, ":", length(daftar), "tile dipakai\n")
  
  if (length(daftar) == 1) return(daftar[[1]])
  mosaic(sprc(daftar), fun = "first")
}

# 13. Baca band --------------------------------------------------------------
b03 <- baca_band("B03", 10)   # Green
b04 <- baca_band("B04", 10)   # Red
b08 <- baca_band("B08", 10)   # NIR
b11 <- baca_band("B11", 20)   # SWIR
b11 <- resample(b11, b08, method = "bilinear")   # samakan ke grid 10 m

# 14. Mask ke batas kabupaten -------------------------------------------------
b03 <- mask(b03, kab_v)
b04 <- mask(b04, kab_v)
b08 <- mask(b08, kab_v)
b11 <- mask(b11, kab_v)

# 15. Cek cakupan citra ----------------------------------------------------------
rast_kab <- rasterize(kab_v, b04, field = 1)
total <- global(!is.na(rast_kab), "sum")[1, 1]
valid <- global(!is.na(b04), "sum")[1, 1]
cat("Cakupan citra atas Wonogiri:", round(valid / total * 100, 2), "%\n")

# 16. Cek visual (false color NIR-Red-Green) ---------------------------------------
plotRGB(c(b08, b04, b03), r = 1, g = 2, b = 3, stretch = "lin")
plot(kab_v, add = TRUE, border = "yellow", lwd = 2)

# 17. Simpan band hasil crop ----------------------------------------------------------
writeRaster(b03, "output/band/B03_wonogiri.tif", overwrite = TRUE)
writeRaster(b04, "output/band/B04_wonogiri.tif", overwrite = TRUE)
writeRaster(b08, "output/band/B08_wonogiri.tif", overwrite = TRUE)
writeRaster(b11, "output/band/B11_wonogiri.tif", overwrite = TRUE)

# ==============================================================
# TAHAP 3: Indeks spektral
# ==============================================================

# 18. B05 (Red Edge, 20 m) untuk NDCI --------------------------------------------------
b05 <- baca_band("B05", 20)
b05 <- resample(b05, b08, method = "bilinear")
b05 <- mask(b05, kab_v)

# 19. Reflektansi = (DN - 1000) / 10000, negatif dijadikan 0 ------------------------------
refl <- function(x) clamp((x - 1000) / 10000, lower = 0, upper = Inf, values = TRUE)
g  <- refl(b03); r <- refl(b04); n <- refl(b08)
s  <- refl(b11); re <- refl(b05)

# 20. Hitung indeks ---------------------------------------------------------------------------
ndvi <- (n - r)  / (n + r)     # vegetasi
ndbi <- (s - n)  / (s + n)     # area terbangun
ndwi <- (g - n)  / (g + n)     # perairan
ndci <- (re - r) / (re + r)    # B5 (red edge) dan B4 (red)

# 21. Cek nilai dan visual -----------------------------------------------------------------------
for (nm in c("ndvi", "ndbi", "ndwi", "ndci")) {
  cat(nm, "\n")
  print(global(get(nm), c("min", "mean", "max"), na.rm = TRUE))
}

par(mfrow = c(2, 2))
plot(ndvi, main = "NDVI", range = c(-1, 1))
plot(ndbi, main = "NDBI", range = c(-1, 1))
plot(ndwi, main = "NDWI", range = c(-1, 1))
plot(ndci, main = "NDCI", range = c(-1, 1))
par(mfrow = c(1, 1))

# 22. Simpan indeks ---------------------------------------------------------------------------------
writeRaster(ndvi, "output/indeks/NDVI_wonogiri.tif", overwrite = TRUE)
writeRaster(ndbi, "output/indeks/NDBI_wonogiri.tif", overwrite = TRUE)
writeRaster(ndwi, "output/indeks/NDWI_wonogiri.tif", overwrite = TRUE)
writeRaster(ndci, "output/indeks/NDCI_wonogiri.tif", overwrite = TRUE)

# 23. Sebaran nilai tiap indeks (dasar penentuan ambang) -------------------------------------------------
q <- c(0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99)
par(mfrow = c(2, 2))
for (nm in c("ndvi", "ndbi", "ndwi", "ndci")) {
  smp <- spatSample(get(nm), size = 1e6, method = "regular",
                    na.rm = TRUE, as.df = FALSE)[, 1]
  cat("\n", toupper(nm), "\n")
  print(round(quantile(smp, probs = q), 3))
  hist(smp, breaks = 100, main = toupper(nm), xlab = "Nilai indeks")
}
par(mfrow = c(1, 1))

# ==============================================================
# TAHAP 4: Klasifikasi tutupan lahan (ambang batas)
# Kode: 1 = Vegetasi, 2 = Bangunan, 3 = Perairan, 4 = Awan
# ==============================================================

# 24. Klasifikasi --------------------------------------------------------------------------------------
thr_awan_ndci  <- 0.03    # awan: NDCI rendah ...
thr_awan_merah <- 0.20    # ... dan reflektan merah (B04) tinggi
thr_air_ndwi   <- 0.0     # perairan: NDWI > 0
thr_veg_ndvi   <- 0.30    # vegetasi: NDVI >= 0.30
thr_bgn_ndbi   <- 0.15    # bangunan: NDBI > 0.15

nama_kelas <- c("Vegetasi", "Bangunan", "Perairan", "Awan")
warna      <- c("#2E7D32", "#E53935", "#1E88E5", "#B0BEC5")

kelas <- ifel(ndvi >= thr_veg_ndvi, 1, ifel(ndbi > thr_bgn_ndbi, 2, 1))  # dasar
kelas <- ifel(ndwi > thr_air_ndwi, 3, kelas)                              # perairan menimpa
kelas <- ifel(ndci <= thr_awan_ndci & r >= thr_awan_merah, 4, kelas)      # awan paling akhir
names(kelas) <- "kelas"

tab <- freq(kelas)
tab$persen <- round(tab$count / sum(tab$count) * 100, 2)
print(tab)        # sekitar: 83.7 / 13.9 / 1.5 / 0.8

writeRaster(kelas, "output/klasifikasi_wonogiri.tif",
            overwrite = TRUE, datatype = "INT1U")

# plot cepat (salinan berlabel, objek 'kelas' tetap numerik)
kelas_plot <- kelas
levels(kelas_plot) <- data.frame(id = 1:4, kelas = nama_kelas)
plot(kelas_plot, col = warna, main = "Klasifikasi tutupan lahan Wonogiri")

# 24b. Uji sensitivitas ambang (sampel piksel) ----------------------------------------------------------------
smp <- spatSample(c(ndvi, ndbi, ndwi, ndci, r), size = 1e6,
                  method = "regular", na.rm = TRUE, as.df = TRUE)
names(smp) <- c("ndvi", "ndbi", "ndwi", "ndci", "r")

uji <- function(thr_veg, thr_bgn) {
  k <- ifelse(smp$ndvi >= thr_veg, 1, ifelse(smp$ndbi > thr_bgn, 2, 1))
  k[smp$ndwi > thr_air_ndwi] <- 3
  k[smp$ndci <= thr_awan_ndci & smp$r >= thr_awan_merah] <- 4
  as.numeric(prop.table(table(factor(k, levels = 1:4))) * 100)
}
grid  <- expand.grid(thr_veg = c(0.30, 0.35, 0.40),
                     thr_bgn = c(0, 0.05, 0.10, 0.15))
hasil <- cbind(grid, round(t(mapply(uji, grid$thr_veg, grid$thr_bgn)), 1))
colnames(hasil)[3:6] <- nama_kelas
print(hasil)

# ==============================================================
# TAHAP 5: Zonal statistics per kecamatan
# ==============================================================

# 25. Siapkan data --------------------------------------------------------------------------------------------------
kec_v  <- vect(kec_utm)
indeks <- c(ndvi, ndbi, ndwi, ndci)
names(indeks) <- c("NDVI", "NDBI", "NDWI", "NDCI")

stat_fun <- list(mean = mean, min = min, max = max,
                 median = median, sd = sd)

# 26. Hitung statistik tiap kecamatan (agak lama) ---------------------------------------------------------------------
hasil_list <- lapply(names(stat_fun), function(s) {
  e <- terra::extract(indeks, kec_v, fun = stat_fun[[s]], na.rm = TRUE, ID = FALSE)
  names(e) <- paste0(names(indeks), "_", s)
  e
})

zs <- cbind(Kecamatan = kec_utm$WADMKC, do.call(cbind, hasil_list))
urut <- as.vector(sapply(names(indeks),
                         function(i) paste0(i, "_", names(stat_fun))))
zs <- zs[, c("Kecamatan", urut)]
zs[, -1] <- round(zs[, -1], 3)

# 27. Cek dan simpan -----------------------------------------------------------------------------------------------------
nrow(zs)          # harus 25
write.csv(zs, "output/zonal_statistics_kecamatan.csv", row.names = FALSE)

# 28. Tabel Word (landscape) -------------------------------------------------------------------------------------------------
lab <- c(Kecamatan = "Kecamatan")
for (i in c("NDVI", "NDBI", "NDWI", "NDCI")) {
  lab[paste0(i, "_", c("mean", "min", "max", "median", "sd"))] <-
    c("Mean", "Min", "Max", "Median", "SD")
}

ft <- flextable(zs)
ft <- set_header_labels(ft, values = as.list(lab))
ft <- add_header_row(ft, values = c("", "NDVI", "NDBI", "NDWI", "NDCI"),
                     colwidths = c(1, 5, 5, 5, 5))
ft <- theme_box(ft)
ft <- align(ft, align = "center", part = "header")
ft <- align(ft, j = 2:21, align = "center", part = "body")
ft <- fontsize(ft, size = 7, part = "all")
ft <- padding(ft, padding = 1.5, part = "all")
ft <- bold(ft, part = "header")
ft <- set_table_properties(ft, layout = "fixed")
ft <- width(ft, j = 1, width = 1.0)
ft <- width(ft, j = 2:21, width = 0.4)

# 29. Simpan Word (tutup file .docx di Word terlebih dahulu) ----------------------------------------------------------------------
doc <- read_docx()
doc <- body_add_par(doc, "Tabel Zonal Statistics Indeks Spektral per Kecamatan, Kabupaten Wonogiri",
                    style = "Normal")
doc <- body_add_flextable(doc, ft)
doc <- body_add_par(doc, "Sumber: Citra Sentinel-2 L2A (14 Oktober 2026); batas kecamatan RBI 25K, Ina-Geoportal.",
                    style = "Normal")
doc <- body_end_section_landscape(doc)
print(doc, target = "output/tabel_zonal_statistics.docx")

# 30. Luas tiap kelas per kecamatan -----------------------------------------------------------------------------------------------------
kec_v$id <- seq_len(nrow(kec_v))
kec_id   <- rasterize(kec_v, kelas, field = "id")

ct <- crosstab(c(kec_id, kelas), useNA = FALSE)      # baris = kecamatan, kolom = kelas
m  <- unclass(ct)
m  <- matrix(as.numeric(m), nrow = nrow(m), ncol = ncol(m), dimnames = NULL)

luas_m2 <- matrix(0, nrow = nrow(kec_v), ncol = 4)    # semua kecamatan x 4 kelas
baris   <- as.integer(rownames(unclass(ct)))
kolom   <- as.integer(colnames(unclass(ct)))
luas_m2[baris, kolom] <- m

px_km2   <- prod(res(kelas)) / 1e6                    # luas 1 piksel (km2)
luas_km2 <- luas_m2 * px_km2
persen   <- luas_km2 / rowSums(luas_km2) * 100

lc <- data.frame(Kecamatan = kec_utm$WADMKC,
                 setNames(as.data.frame(round(luas_km2, 3)), paste0(nama_kelas, "_km2")),
                 setNames(as.data.frame(round(persen,   2)), paste0(nama_kelas, "_persen")))
print(lc)
write.csv(lc, "output/luas_kelas_kecamatan.csv", row.names = FALSE)

# ==============================================================
# TAHAP 6: Data ringan untuk dashboard Shiny (resolusi 50 m)
# ==============================================================

# 31. Perkecil resolusi (modus) dan pisahkan per kelas ---------------------------------------------------------------------------------------------
k50 <- aggregate(kelas, fact = 5, fun = "modal", na.rm = TRUE)
writeRaster(k50, "output/klasifikasi_50m.tif", overwrite = TRUE, datatype = "INT1U")

for (i in 1:4) {
  ki <- ifel(k50 == i, 1, NA)
  writeRaster(ki, sprintf("output/web/kelas_%s.tif", nama_kelas[i]),
              overwrite = TRUE, datatype = "INT1U")
}
# ==============================================================
# Peta klasifikasi tutupan lahan Kabupaten Wonogiri (siap cetak)
# File ini berdiri sendiri: membaca data dari folder output/
# Cara pakai: buka file ini, klik "Source" (jangan dijalankan baris per baris)
# Pastikan working directory = folder project (yang berisi output/)
# ==============================================================

library(terra)

# bersihkan sisa fungsi lama dari sesi sebelumnya
if (exists("gambar_peta")) rm(gambar_peta)
graphics.off()

# 1. Baca data -------------------------------------------------------------
kelas_r <- rast("output/klasifikasi_wonogiri.tif")
kec_v   <- vect("output/kecamatan_wonogiri.shp")
kab_v   <- vect("output/kabupaten_wonogiri.shp")

nama_kelas <- c("Vegetasi", "Bangunan", "Perairan", "Awan")
warna      <- c("#2E7D32", "#E53935", "#1E88E5", "#B0BEC5")

kelas_plot <- kelas_r
levels(kelas_plot) <- data.frame(id = 1:4, kelas = nama_kelas)

# 2. Ukuran dan posisi ----------------------------------------------------------
e  <- ext(kab_v)
w  <- e$xmax - e$xmin
h  <- e$ymax - e$ymin
px <- function(f) e$xmin + f * w
py <- function(f) e$ymin + f * h

xl <- c(px(-0.10), px(1.55))   # kiri: label grid; kanan: legenda + panah utara
yl <- c(py(-0.22), py(1.10))   # bawah: skala + sumber; atas: judul

# 3. Panah utara (setengah hitam + huruf N) -------------------------------------------
panah_utara <- function(x, y, len) {
  lebar <- len * 0.14
  polygon(c(x, x - lebar, x), c(y + len, y, y + len * 0.25),
          col = "black", border = "black")
  polygon(c(x, x + lebar, x), c(y + len, y, y + len * 0.25),
          col = "white", border = "black")
  text(x - len * 0.38, y + len * 0.62, "N", cex = 1, font = 2)
}

# 4. Fungsi menggambar peta -------------------------------------------------------------
gambar_peta <- function() {
  par(mar = c(1, 1, 1, 1), xpd = NA)
  plot(NA, xlim = xl, ylim = yl, asp = 1, axes = FALSE, xlab = "", ylab = "")
  
  # peta
  plot(kelas_plot, col = warna, legend = FALSE, axes = FALSE, add = TRUE)
  plot(kec_v, add = TRUE, border = "grey35", lwd = 0.3)
  plot(kab_v, add = TRUE, border = "black", lwd = 1.2)
  
  # reset area gambar supaya legenda/panah di luar peta tidak terpotong
  clip(grconvertX(0, "ndc", "user"), grconvertX(1, "ndc", "user"),
       grconvertY(0, "ndc", "user"), grconvertY(1, "ndc", "user"))
  
  # grid koordinat (UTM 49S, meter) + label di tepi kiri dan bawah
  gx <- pretty(c(e$xmin, e$xmax), n = 5)
  gy <- pretty(c(e$ymin, e$ymax), n = 5)
  gx <- gx[gx >= e$xmin & gx <= e$xmax]
  gy <- gy[gy >= e$ymin & gy <= e$ymax]
  gcol <- adjustcolor("grey30", alpha.f = 0.45)
  segments(gx, e$ymin, gx, e$ymax, col = gcol, lwd = 0.4, lty = 3)
  segments(e$xmin, gy, e$xmax, gy, col = gcol, lwd = 0.4, lty = 3)
  text(gx, e$ymin - 0.025 * h,
       format(gx, big.mark = ".", scientific = FALSE), cex = 0.5)
  text(e$xmin - 0.01 * w, gy,
       format(gy, big.mark = ".", scientific = FALSE), cex = 0.5, adj = 1)
  
  # judul
  text(px(0.5), py(1.06), "Peta Klasifikasi Tutupan Lahan Kabupaten Wonogiri",
       font = 2, cex = 1.3)
  
  # legenda (kanan atas)
  legend(x = px(1.08), y = py(0.98), legend = nama_kelas, fill = warna,
         title = "Kelas Tutupan Lahan", bty = "n", cex = 0.8, y.intersp = 0.9)
  
  # panah utara (jauh di bawah legenda, sejajar tengah legenda)
  panah_utara(px(1.24), py(0.30), len = h * 0.14)
  
  # skala dalam meter (kiri bawah)
  sbar(d = 10000, xy = c(px(0.0), py(-0.13)), type = "bar", divs = 2,
       below = "m", label = c("0", "5000", "10000"), cex = 0.75)
  
  # sumber (kiri bawah)
  text(px(0), py(-0.20),
       "Sumber: Citra Sentinel-2 L2A 14 Oktober 2026 (ESA Copernicus); Batas administrasi RBI 25K (Ina-Geoportal, BIG)",
       adj = 0, cex = 0.6)
}

# 5. Simpan PNG 300 dpi (file inilah yang dipakai di laporan) ---------------------------------
png("output/peta_klasifikasi_layout.png", width = 3000, height = 2400, res = 300)
gambar_peta()
dev.off()

# 6. Tampilkan di panel Plots ------------------------------------------------------------------
gambar_peta()
cat("Selesai. Buka output/peta_klasifikasi_layout.png\n")
# Selesai. Jalankan dashboard dengan membuka app.R lalu klik Run App.

