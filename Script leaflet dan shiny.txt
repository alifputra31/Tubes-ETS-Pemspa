library(shiny)
library(shinydashboard)
library(leaflet)
library(leaflet.extras)
library(raster)
library(sf)

# ==============================================================
# Dashboard Tutupan Lahan - Sentinel-2 L2A
# Semua data dibaca dari folder output/ (hasil script analisis)
# ==============================================================

wil <- "Wonogiri"          # nama wilayah (dipakai untuk judul dan nama file)
sfx <- tolower(wil)

# ---- 1. Data vektor ----------------------------------------------------
kec <- st_read(sprintf("output/kecamatan_%s.shp", sfx), quiet = TRUE) |> st_transform(4326)
kab <- st_read(sprintf("output/kabupaten_%s.shp", sfx), quiet = TRUE) |> st_transform(4326)

kol_nama <- intersect(c("WADMKC", "KECAMATAN"), names(kec))[1]
kec$nama <- trimws(as.character(kec[[kol_nama]]))

pusat <- suppressWarnings(st_coordinates(st_point_on_surface(st_geometry(kec))))
bb    <- st_bbox(kab)

# ---- 2. Data tabel -----------------------------------------------------
zs <- read.csv("output/zonal_statistics_kecamatan.csv", check.names = FALSE)
lc <- read.csv("output/luas_kelas_kecamatan.csv",       check.names = FALSE)
zs$Kecamatan <- trimws(zs$Kecamatan)
lc$Kecamatan <- trimws(lc$Kecamatan)

# ---- 3. Pengaturan kelas dan indeks ------------------------------------
nama_kelas <- c("Vegetasi", "Bangunan", "Perairan", "Awan")
warna      <- c("#2E7D32", "#E53935", "#1E88E5", "#B0BEC5")

idx_nama  <- c("NDVI", "NDBI", "NDWI", "NDCI")
idx_warna <- c(NDVI = "#2E7D32", NDBI = "#E53935", NDWI = "#1E88E5", NDCI = "#7B1FA2")
idx_pal   <- c(NDVI = "YlGn",    NDBI = "YlOrRd",  NDWI = "Blues",   NDCI = "Purples")

kol_km2   <- paste0(nama_kelas, "_km2")
kol_persen <- paste0(nama_kelas, "_persen")

tot_km2 <- colSums(lc[, kol_km2])
tot_pct <- tot_km2 / sum(tot_km2) * 100

tabel_total <- data.frame(Kelas = nama_kelas,
                          `Luas (km2)` = round(tot_km2, 2),
                          `Persen (%)` = round(tot_pct, 2),
                          check.names = FALSE)

tabel_lc <- cbind(Kecamatan = lc$Kecamatan,
                  setNames(lc[, kol_km2], paste0(nama_kelas, " (km2)")),
                  `Total (km2)` = round(rowSums(lc[, kol_km2]), 2),
                  setNames(lc[, kol_persen], paste0(nama_kelas, " (%)")))

# ---- 4. Raster klasifikasi (ringan, 100 m) -----------------------------
kelas50  <- raster("output/klasifikasi_50m.tif")
kelas100 <- aggregate(kelas50, fact = 2, fun = modal, na.rm = TRUE)

r_kelas <- lapply(seq_along(nama_kelas), function(i) {
  calc(kelas100, function(x) ifelse(x == i, 1, NA))
})
# ---- 5. Fungsi bantu peta ----------------------------------------------
dasar_nama <- c("OpenStreetMap", "Citra Satelit")

dasar <- function(m) {
  m %>%
    addProviderTiles(providers$OpenStreetMap,     group = dasar_nama[1]) %>%
    addProviderTiles(providers$Esri.WorldImagery, group = dasar_nama[2]) %>%
    fitBounds(bb[["xmin"]], bb[["ymin"]], bb[["xmax"]], bb[["ymax"]]) %>%
    addFullscreenControl() %>%
    addScaleBar(position = "bottomleft")
}

tambah_nama <- function(m) {
  addLabelOnlyMarkers(m, lng = pusat[, 1], lat = pusat[, 2], label = kec$nama,
                      group = "Nama Kecamatan",
                      labelOptions = labelOptions(
                        noHide = TRUE, textOnly = TRUE, direction = "center",
                        style = list("font-weight" = "bold", "font-size" = "11px",
                                     "text-shadow" = "0 0 3px #ffffff")))
}

batas_kab <- function(m) {
  addPolygons(m, data = kab, fill = FALSE, color = "#000000", weight = 3,
              group = "Batas Kabupaten")
}

# popup statistik tiap kecamatan (klik pada peta tutupan lahan)
popup_kec <- vapply(seq_len(nrow(kec)), function(i) {
  nm <- kec$nama[i]
  z  <- zs[zs$Kecamatan == nm, , drop = FALSE]
  l  <- lc[lc$Kecamatan == nm, , drop = FALSE]
  if (nrow(z) == 0 || nrow(l) == 0) return(paste0("<b>Kecamatan ", nm, "</b>"))
  
  b_idx <- vapply(idx_nama, function(n)
    sprintf("<tr><td>%s</td><td>%.3f</td><td>%.3f</td><td>%.3f</td></tr>", n,
            z[[paste0(n, "_mean")]], z[[paste0(n, "_min")]], z[[paste0(n, "_max")]]),
    character(1))
  b_kls <- vapply(nama_kelas, function(n)
    sprintf("<tr><td>%s</td><td>%.2f</td><td>%.1f</td></tr>", n,
            l[[paste0(n, "_km2")]], l[[paste0(n, "_persen")]]),
    character(1))
  
  paste0("<b>Kecamatan ", nm, "</b>",
         "<table style='width:100%;font-size:11px;margin-top:6px'>",
         "<tr><th>Indeks</th><th>Mean</th><th>Min</th><th>Max</th></tr>",
         paste(b_idx, collapse = ""), "</table>",
         "<table style='width:100%;font-size:11px;margin-top:6px'>",
         "<tr><th>Kelas</th><th>km2</th><th>%</th></tr>",
         paste(b_kls, collapse = ""), "</table>")
}, character(1))

# ==============================================================
# Tampilan
# ==============================================================
ui <- dashboardPage(
  dashboardHeader(title = "Tutupan Lahan"),
  dashboardSidebar(
    sidebarMenu(
      menuItem("Maps", tabName = "maps", icon = icon("globe"), startExpanded = TRUE,
               menuSubItem("Tutupan Lahan", tabName = "m_klas", icon = icon("map")),
               menuSubItem("Zonal Indeks per Kecamatan", tabName = "m_zonal",
                           icon = icon("layer-group")),
               menuSubItem("Statistik per Kecamatan", tabName = "m_stat",
                           icon = icon("table")),
               menuSubItem("Luas Kelas per Kecamatan", tabName = "m_luas",
                           icon = icon("chart-bar")))
    )
  ),
  dashboardBody(
    tags$style(type = "text/css",
               "#peta_klas, #peta_zonal {height: calc(100vh - 80px) !important;}"),
    tabItems(
      # 1. peta klasifikasi tutupan lahan
      tabItem(tabName = "m_klas", leafletOutput("peta_klas")),
      
      # 2. peta zonal indeks per kecamatan
      tabItem(tabName = "m_zonal", leafletOutput("peta_zonal")),
      
      # 3. statistik per kecamatan
      tabItem(tabName = "m_stat",
              fluidRow(
                box(title = "Luas Tiap Kelas Tutupan Lahan", width = 4,
                    status = "primary", solidHeader = TRUE,
                    tableOutput("tbl_total")),
                box(title = "Zonal Statistics per Kecamatan", width = 8,
                    status = "primary", solidHeader = TRUE,
                    selectInput("indeks", "Pilih indeks:", idx_nama),
                    div(style = "overflow-x:auto", tableOutput("tbl_zonal")))
              ),
              fluidRow(
                box(title = "Histogram Nilai Indeks", width = 6,
                    status = "primary", solidHeader = TRUE,
                    plotOutput("hist_idx", height = "420px")),
                box(title = "Rata-rata Indeks per Kecamatan", width = 6,
                    status = "primary", solidHeader = TRUE,
                    plotOutput("bar_idx", height = "650px"))
              )
      ),
      
      # 4. luas kelas per kecamatan
      tabItem(tabName = "m_luas",
              fluidRow(
                box(title = "Luas Kelas Tutupan Lahan per Kecamatan", width = 12,
                    status = "primary", solidHeader = TRUE,
                    div(style = "overflow-x:auto", tableOutput("tbl_luas")))
              ),
              fluidRow(
                box(title = "Komposisi Tutupan Lahan per Kecamatan (%)", width = 12,
                    status = "primary", solidHeader = TRUE,
                    plotOutput("komposisi", height = "650px"))
              )
      )
    )
  )
)

# ==============================================================
# Server
# ==============================================================
server <- function(input, output, session) {
  
  # ---- peta tutupan lahan ----
  output$peta_klas <- renderLeaflet({
    m <- leaflet() %>% dasar()
    
    for (i in seq_along(nama_kelas)) {
      pal_i <- colorNumeric(c(warna[i], warna[i]), domain = c(0, 2),
                            na.color = "transparent")
      m <- m %>% addRasterImage(r_kelas[[i]], colors = pal_i, method = "ngb",
                                opacity = 0.9, group = nama_kelas[i],
                                maxBytes = 4 * 1024 * 1024)
    }
    
    m %>%
      addPolygons(data = kec, fill = TRUE, fillOpacity = 0, color = "#333333",
                  weight = 1, label = ~nama, popup = popup_kec,
                  highlightOptions = highlightOptions(weight = 3, color = "#000000"),
                  group = "Batas Kecamatan") %>%
      batas_kab() %>%
      tambah_nama() %>%
      addLegend(position = "bottomright", colors = warna, opacity = 1,
                labels = paste0(nama_kelas, " (", round(tot_pct, 2), "%)"),
                title = "Kelas Tutupan Lahan") %>%
      addLayersControl(
        baseGroups    = dasar_nama,
        overlayGroups = c("Batas Kabupaten", "Batas Kecamatan",
                          "Nama Kecamatan", nama_kelas),
        options = layersControlOptions(collapsed = FALSE))
  })
  
  # ---- peta zonal indeks (rata-rata per kecamatan) ----
  output$peta_zonal <- renderLeaflet({
    m <- leaflet() %>% dasar()
    
    for (n in idx_nama) {
      v   <- zs[[paste0(n, "_mean")]][match(kec$nama, zs$Kecamatan)]
      pal <- colorNumeric(idx_pal[[n]], domain = v)
      m <- m %>%
        addPolygons(data = kec, fillColor = pal(v), fillOpacity = 0.8,
                    color = "#FFFFFF", weight = 1, group = n,
                    label = paste0(kec$nama, ": ", n, " = ", round(v, 3)),
                    highlightOptions = highlightOptions(weight = 3, color = "#000000")) %>%
        addLegend(position = "bottomright", pal = pal, values = v, opacity = 1,
                  title = paste0(n, " (rata-rata)"), group = n)
    }
    
    m %>%
      addPolygons(data = kec, fill = FALSE, color = "#555555", weight = 1,
                  group = "Batas Kecamatan") %>%
      batas_kab() %>%
      tambah_nama() %>%
      addLayersControl(
        baseGroups    = dasar_nama,
        overlayGroups = c("Batas Kabupaten", "Batas Kecamatan",
                          "Nama Kecamatan", idx_nama),
        options = layersControlOptions(collapsed = FALSE)) %>%
      hideGroup(idx_nama[-1])          # NDVI tampil dulu, lainnya dinyalakan manual
  })
  
  # ---- tabel ----
  output$tbl_total <- renderTable(tabel_total, striped = TRUE, digits = 2)
  
  output$tbl_zonal <- renderTable({
    n <- input$indeks
    d <- zs[, c("Kecamatan", paste0(n, c("_mean", "_min", "_max", "_median", "_sd")))]
    names(d) <- c("Kecamatan", "Mean", "Min", "Max", "Median", "Std. Deviasi")
    d
  }, striped = TRUE, digits = 4)
  
  output$tbl_luas <- renderTable(tabel_lc, striped = TRUE, digits = 2)
  
  # ---- histogram nilai indeks (sampel piksel dari raster 10 m) ----
  sampel <- reactive({
    n <- input$indeks
    f <- sprintf("output/indeks/%s_%s.tif", n, sfx)
    validate(need(file.exists(f), paste("File tidak ditemukan:", f)))
    v <- as.numeric(sampleRegular(raster(f), size = 2e5, useGDAL = TRUE))
    v[is.finite(v)]
  }) |> bindCache(input$indeks)
  
  output$hist_idx <- renderPlot({
    n <- input$indeks
    hist(sampel(), breaks = 80, col = idx_warna[[n]], border = NA,
         main = paste("Histogram", n, "Kabupaten", wil),
         xlab = paste("Nilai", n), ylab = "Frekuensi")
  })
  
  # ---- grafik batang rata-rata indeks per kecamatan ----
  output$bar_idx <- renderPlot({
    n   <- input$indeks
    kol <- paste0(n, "_mean")
    d   <- zs[order(zs[[kol]]), ]
    par(mar = c(4, 9, 3, 1))
    barplot(d[[kol]], names.arg = d$Kecamatan, horiz = TRUE, las = 1,
            col = idx_warna[[n]], cex.names = 0.8,
            xlab = paste("Rata-rata", n),
            main = paste("Rata-rata", n, "per Kecamatan"), cex.main = 1)
  })
  
  # ---- komposisi tutupan lahan per kecamatan ----
  output$komposisi <- renderPlot({
    d <- lc[order(lc$Vegetasi_persen), ]
    m <- t(as.matrix(d[, kol_persen]))
    par(mar = c(4, 9, 5, 1))
    barplot(m, names.arg = d$Kecamatan, horiz = TRUE, las = 1, col = warna,
            border = "white", cex.names = 0.8, xlim = c(0, 100),
            xlab = "Persentase luas (%)")
    mtext("Komposisi Tutupan Lahan per Kecamatan", side = 3, line = 3, font = 2)
    legend("top", inset = c(0, -0.1), horiz = TRUE, xpd = NA, bty = "n",
           fill = warna, legend = nama_kelas)
  })
}

shinyApp(ui, server)