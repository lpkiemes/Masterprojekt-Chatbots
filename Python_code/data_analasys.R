##########################################
### Datenanalyse Skript###################
##########################################
base_path   <- "/home/theo/PycharmProjects/Masterprojekt-Chatbots"
data_path   <- file.path(base_path, "data/processed/analysis_dataset.rds")
plot_dir    <- file.path(base_path, "plots")
setwd(base_path)
#Daten laden

data <- readRDS(data_path)
   
############################
#Packete installieren######
###########################

pakete <- c("cluster", "ggplot2", "patchwork", "labelled")

for (p in pakete) {
  if (!requireNamespace(p, quietly = TRUE)) {
    install.packages(p)
  }
  library(p, character.only = TRUE)
}

library(cluster)
library(ggplot2)

# Ausgabeordner für Grafiken
dir.create("plots", showWarnings = FALSE)
SEED <- 404
#################################
# 0) STICHPROBENBESCHREIBUNG#####
#############################

library(patchwork)

# Faktoren mit lesbaren Labels versehen
data$gender_f <- factor(data$gender, levels = c(1,2,3,-1),
                        labels = c("männlich","weiblich","non-binär/divers","keine Angabe"))
data$degree_f <- factor(data$degree, levels = c(1,2,3,4,5),
                        labels = c("Bachelor","Master","Staatsex./Lehramt","Promotion","anderer"))
field_labels <- c("Geistes-/Kultur","Sprach-/Lit.","Sozialwiss.","Recht/Wirtschaft",
                  "Mathe/Naturwiss.","Medizin/Gesundheit","Ingenieurwiss.","Informatik",
                  "Kunst/Musik","Lehramt","anderes")
data$field_f <- factor(data$field, levels = 1:11, labels = field_labels)

BLUE <- "#4C72B0"

p1 <- ggplot(data, aes(x = gender_f)) +
  geom_bar(fill = BLUE) +
  geom_text(stat = "count", aes(label = after_stat(count)), vjust = -0.3, size = 3.5) +
  labs(title = "Geschlecht", x = NULL, y = "Anzahl") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

p2 <- ggplot(data, aes(x = age)) +
  geom_histogram(binwidth = 1, fill = BLUE, colour = "white") +
  labs(title = paste0("Alter (M = ", round(mean(data$age),1),
                      ", SD = ", round(sd(data$age),1), ")"),
       x = "Alter in Jahren", y = "Anzahl") +
  theme_minimal(base_size = 11)

p3 <- ggplot(data, aes(y = field_f)) +
  geom_bar(fill = BLUE) +
  geom_text(stat = "count", aes(label = after_stat(count)), hjust = -0.3, size = 3) +
  labs(title = "Fächergruppe", x = "Anzahl", y = NULL) +
  theme_minimal(base_size = 11)

p4 <- ggplot(data, aes(x = degree_f)) +
  geom_bar(fill = BLUE) +
  geom_text(stat = "count", aes(label = after_stat(count)), vjust = -0.3, size = 3.5) +
  labs(title = "Angestrebter Abschluss", x = NULL, y = "Anzahl") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

combined <- (p1 | p2) / (p3 | p4) +
  plot_annotation(title = paste0("Stichprobenbeschreibung (N = ", nrow(data), ")"),
                  theme = theme(plot.title = element_text(size = 15, face = "bold")))

ggsave("plots/00_stichprobe.png", combined, width = 11, height = 8, dpi = 150)

#descriptives der diskrepanzmaße

## 1a) Mittlere Diskrepanz + MAD pro Person -------
D_cols <- c("D_info","D_schreiben","D_praktisch","D_technisch","D_lernen")
data$D_mean <- rowMeans(data[, D_cols])                 # Richtung (Ueber-/Unterschaetzung)
data$D_MAD  <- rowMeans(abs(data[, D_cols]))            # Ausmass, ohne Neutralisierung

## 1b) Verteilung von D_mean und MAD (Histogramme) ---------------------
p_dmean <- ggplot(data, aes(x = D_mean)) +
  geom_histogram(bins = 15, fill = "#4C72B0", colour = "white") +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey30") +
  labs(title = "Mittlere Diskrepanz pro Person (SA - BE)",
       subtitle = "> 0: Ueberschaetzung, < 0: Unterschaetzung",
       x = "Mittlere Diskrepanz", y = "Anzahl Personen") +
  theme_minimal(base_size = 12)
ggsave("plots/01_hist_Dmean.png", p_dmean, width = 7, height = 4.5, dpi = 150)

p_mad <- ggplot(data, aes(x = D_MAD)) +
  geom_histogram(bins = 15, fill = "#C44E52", colour = "white") +
  labs(title = "Mittlere absolute Diskrepanz (MAD) pro Person",
       x = "MAD", y = "Anzahl Personen") +
  theme_minimal(base_size = 12)
ggsave("plots/02_hist_MAD.png", p_mad, width = 7, height = 4.5, dpi = 150)

## 1c) Diskrepanz je Aufgabe (Boxplots, alle 5 Kategorien) -------------
D_long <- data.frame(
  id   = rep(data$id, times = length(D_cols)),
  task = factor(rep(c("Info","Schreiben","Praktisch","Technisch","Lernen"),
                    each = nrow(data)),
                levels = c("Info","Schreiben","Praktisch","Technisch","Lernen")),
  D    = unlist(data[, D_cols])
)
p_box <- ggplot(D_long, aes(x = task, y = D, fill = task)) +
  geom_boxplot(alpha = 0.7, outlier.size = 1) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey30") +
  labs(title = "Diskrepanz je Aufgabentyp", x = NULL, y = "Diskrepanz (SA - BE)") +
  theme_minimal(base_size = 12) + theme(legend.position = "none")
ggsave("plots/03_box_tasks.png", p_box, width = 8, height = 4.5, dpi = 150)

## 1d) Verteilung der kategorialen Diskrepanzen (Balken) ---------------
p_sent <- ggplot(data, aes(x = S_Diskrepanz_Label)) +
  geom_bar(fill = "#55A868") +
  labs(title = "Sentiment-Diskrepanz", x = NULL, y = "Anzahl Personen") +
  theme_minimal(base_size = 12)
ggsave("plots/04_bar_sentiment.png", p_sent, width = 6, height = 4, dpi = 150)

p_krit <- ggplot(data, aes(x = K_Diskrepanz_Label)) +
  geom_bar(fill = "#8172B3") +
  labs(title = "Kritik-Diskrepanz", x = NULL, y = "Anzahl Personen") +
  theme_minimal(base_size = 12)
ggsave("plots/05_bar_kritik.png", p_krit, width = 6, height = 4, dpi = 150)

cat("Deskriptiv: D_mean Range [", round(min(data$D_mean),2), ",",
    round(max(data$D_mean),2), "], MAD Mittel", round(mean(data$D_MAD),2), "\n")

############################################
# 2) PAM-CLUSTERANALYSE (Gower-Distanz)#####
###########################################

## 2a) Cluster-Input: 5 kontinuierlich + 2 ordinal (geordnete Faktoren)
cluster_df <- data.frame(
  D_info       = data$D_info,
  D_schreiben  = data$D_schreiben,
  D_praktisch  = data$D_praktisch,
  D_technisch  = data$D_technisch,
  D_lernen     = data$D_lernen,
  S_Diskrepanz = factor(data$S_Diskrepanz, levels = c(-1,0,1), ordered = TRUE),
  K_Diskrepanz = factor(data$K_Diskrepanz, levels = c(-1,0,1), ordered = TRUE)
)

## 2b) Gewichtung: 5 Aufgaben je 0.2, Sentiment & Kritik je 1
gower_weights <- c(0.2, 0.2, 0.2, 0.2, 0.2, 1, 1)

gower_dist <- daisy(cluster_df, metric = "gower", weights = gower_weights)

## 2c) Optimales k ueber durchschnittliche Silhouette (k = 2..6) -------
sil_avg <- sapply(2:10, function(k) {
  pm <- pam(gower_dist, k = k, diss = TRUE)
  pm$silinfo$avg.width
})
names(sil_avg) <- 2:10
k_opt <- as.integer(names(which.max(sil_avg)))

sil_df <- data.frame(k = 2:10, silhouette = sil_avg)
p_sil <- ggplot(sil_df, aes(x = k, y = silhouette)) +
  geom_line(colour = "grey50") +
  geom_point(size = 3, colour = "#4C72B0") +
  geom_point(data = sil_df[sil_df$k == k_opt, ], size = 5, colour = "#C44E52") +
  geom_hline(yintercept = c(0.5, 0.7), linetype = "dotted", colour = "grey60") +
  scale_x_continuous(breaks = 2:6) +
  labs(title = "Durchschnittliche Silhouette je Clusterzahl",
       subtitle = paste("Gewaehltes k =", k_opt),
       x = "Anzahl Cluster (k)", y = "Durchschnittliche Silhouettenweite") +
  theme_minimal(base_size = 12)
ggsave("plots/06_silhouette_k.png", p_sil, width = 7, height = 4.5, dpi = 150)

## 2d) Finales PAM-Modell ---------------------------------------------
set.seed(SEED)
pam_fit <- pam(gower_dist, k = k_opt, diss = TRUE)
data$cluster <- factor(pam_fit$clustering)

cat("Optimales k:", k_opt, "| avg. Silhouette:", round(max(sil_avg),3),
    "| Clustergroessen:", paste(table(data$cluster), collapse="/"), "\n")

## 2e) Silhouette-Plot pro Person -------------------------------------
sil_obj <- silhouette(pam_fit$clustering, gower_dist)
sil_pdf <- data.frame(cluster = factor(sil_obj[,1]),
                      sil_width = sil_obj[,3])
sil_pdf <- sil_pdf[order(sil_pdf$cluster, sil_pdf$sil_width), ]
sil_pdf$idx <- 1:nrow(sil_pdf)
p_silperson <- ggplot(sil_pdf, aes(x = idx, y = sil_width, fill = cluster)) +
  geom_col() +
  geom_hline(yintercept = 0, colour = "grey30") +
  coord_flip() +
  labs(title = "Silhouettenwerte pro Person",
       x = "Person (nach Cluster sortiert)", y = "Silhouettenweite") +
  theme_minimal(base_size = 12)
ggsave("plots/07_silhouette_person.png", p_silperson, width = 7, height = 6, dpi = 150)

## 2f) Cluster-Profile: mittlere Diskrepanz je Variable (Heatmap) -----
prof <- aggregate(cbind(D_info, D_schreiben, D_praktisch, D_technisch, D_lernen) ~ cluster,
                  data = data, FUN = mean)
prof_long <- reshape(prof, direction = "long",
                     varying = D_cols, v.names = "value",
                     timevar = "variable", times = D_cols, idvar = "cluster")
p_heat <- ggplot(prof_long, aes(x = variable, y = cluster, fill = value)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = round(value, 2)), size = 3.5) +
  scale_fill_gradient2(low = "#3B4CC0", mid = "white", high = "#B40426", midpoint = 0) +
  labs(title = "Cluster-Profile: mittlere Diskrepanz je Aufgabe",
       x = NULL, y = "Cluster", fill = "Mittl.\nDiskrepanz") +
  theme_minimal(base_size = 12) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))
ggsave("plots/08_cluster_heatmap.png", p_heat, width = 8, height = 4.5, dpi = 150)

## 2g) MDS-Projektion der Distanzmatrix, eingefaerbt nach Cluste
mds <- cmdscale(gower_dist, k = 2)
mds_df <- data.frame(Dim1 = mds[,1], Dim2 = mds[,2], cluster = data$cluster)
medoid_idx <- pam_fit$id.med
p_mds <- ggplot(mds_df, aes(Dim1, Dim2, colour = cluster)) +
  geom_point(size = 3, alpha = 0.8) +
  geom_point(data = mds_df[medoid_idx, ], size = 6, shape = 1, stroke = 1.5,
             colour = "black") +
  labs(title = "MDS-Projektion der Gower-Distanzen",
       subtitle = "Umkreiste Punkte = Medoide (Cluster-Zentren)",
       x = "MDS-Dimension 1", y = "MDS-Dimension 2") +
  theme_minimal(base_size = 12)
ggsave("plots/09_mds.png", p_mds, width = 7, height = 5, dpi = 150)

## 2h) Kategoriale Diskrepanzen je Cluster (gestapelte Balken) --------
p_sent_cl <- ggplot(data, aes(x = cluster, fill = S_Diskrepanz_Label)) +
  geom_bar(position = "fill") +
  labs(title = "Sentiment-Diskrepanz je Cluster", x = "Cluster",
       y = "Anteil", fill = "Sentiment-\nDiskrepanz") +
  theme_minimal(base_size = 12)
ggsave("plots/10_sentiment_cluster.png", p_sent_cl, width = 7, height = 4.5, dpi = 150)

p_krit_cl <- ggplot(data, aes(x = cluster, fill = K_Diskrepanz_Label)) +
  geom_bar(position = "fill") +
  labs(title = "Kritik-Diskrepanz je Cluster", x = "Cluster",
       y = "Anteil", fill = "Kritik-\nDiskrepanz") +
  theme_minimal(base_size = 12)
ggsave("plots/11_kritik_cluster.png", p_krit_cl, width = 7, height = 4.5, dpi = 150)

# =====================================================================
# 3) CLUSTERVERGLEICH: Kontextvariablen (nicht im Clustering verwendet)
# =====================================================================

## Hilfsfunktion: p-Wert dezent formatieren
fmt_p <- function(p) ifelse(p < 0.001, "< 0.001", sprintf("%.3f", p))

## 3a) Soziale Erwuenschtheit (metrisch-nah) -> ANOVA + Boxplot -------
aov_sd <- oneway.test(social_desir_mean ~ cluster, data = data, var.equal = FALSE)
p_sd <- ggplot(data, aes(x = cluster, y = social_desir_mean, fill = cluster)) +
  geom_boxplot(alpha = 0.7) +
  geom_jitter(width = 0.15, size = 1.5, alpha = 0.6) +
  labs(title = "Soziale Erwuenschtheit je Cluster",
       subtitle = paste0("Welch-ANOVA: p = ", fmt_p(aov_sd$p.value)),
       x = "Cluster", y = "Soziale Erwuenschtheit (Mittelwert)") +
  theme_minimal(base_size = 12) + theme(legend.position = "none")
ggsave("plots/12_context_socialdesir.png", p_sd, width = 7, height = 4.5, dpi = 150)

## 3b) Ordinale Variablen -> Kruskal-Wallis + Boxplots ---------------
ord_vars <- c("ai_experience","freq","info_literacy_where","info_literacy_how")
ord_labels <- c("KI-Erfahrung","Nutzungshaeufigkeit","Info-Literacy (wo)","Info-Literacy (wie)")

for (i in seq_along(ord_vars)) {
  v <- ord_vars[i]
  kw <- kruskal.test(data[[v]] ~ data$cluster)
  p_ord <- ggplot(data, aes(x = cluster, y = .data[[v]], fill = cluster)) +
    geom_boxplot(alpha = 0.7) +
    geom_jitter(width = 0.15, size = 1.5, alpha = 0.6) +
    labs(title = paste(ord_labels[i], "je Cluster"),
         subtitle = paste0("Kruskal-Wallis: p = ", fmt_p(kw$p.value)),
         x = "Cluster", y = ord_labels[i]) +
    theme_minimal(base_size = 12) + theme(legend.position = "none")
  ggsave(sprintf("plots/13_context_%s.png", v), p_ord, width = 7, height = 4.5, dpi = 150)
}

## 3c) Nominale Variablen -> Chi-Quadrat + Mosaik/Balken -------------
nom_vars <- c("gender","field","degree")
nom_labels <- c("Geschlecht","Faechergruppe","Abschluss")

for (i in seq_along(nom_vars)) {
  v <- nom_vars[i]
  tab <- table(data$cluster, data[[v]])
  # Chi-Quadrat mit simuliertem p-Wert (robust bei kleinen erwarteten Haeufigkeiten)
  chi <- suppressWarnings(chisq.test(tab, simulate.p.value = TRUE, B = 2000))
  p_nom <- ggplot(data, aes(x = cluster, fill = factor(.data[[v]]))) +
    geom_bar(position = "fill") +
    labs(title = paste(nom_labels[i], "je Cluster"),
         subtitle = paste0("Chi-Quadrat (simuliert): p = ", fmt_p(chi$p.value)),
         x = "Cluster", y = "Anteil", fill = nom_labels[i]) +
    theme_minimal(base_size = 12)
  ggsave(sprintf("plots/14_context_%s.png", v), p_nom, width = 7, height = 4.5, dpi = 150)
}

cat("Clustervergleich: Grafiken erstellt (soz. Erwuenschtheit, 4 ordinale, 3 nominale)\n")

# =====================================================================
# 4) ROBUSTHEITSCHECKS
# =====================================================================

## 4a) Ausschluss uneindeutiger Sentiment-Faelle ----------------------
# uneindeutig = Gleichstand in den Sentiment-Rohcounts
tie_sent <- apply(data[, c("obs_sent_freundlich_n","obs_sent_neutral_n",
                           "obs_sent_unfreundlich_n")], 1,
                  function(x) sum(x == max(x)) > 1)
data_r1 <- data[!tie_sent, ]

cl_r1 <- data.frame(
  data_r1$D_info, data_r1$D_schreiben, data_r1$D_praktisch,
  data_r1$D_technisch, data_r1$D_lernen,
  S = factor(data_r1$S_Diskrepanz, levels=c(-1,0,1), ordered=TRUE),
  K = factor(data_r1$K_Diskrepanz, levels=c(-1,0,1), ordered=TRUE)
)
gd_r1 <- daisy(cl_r1, metric = "gower", weights = gower_weights)
set.seed(SEED)
pam_r1 <- pam(gd_r1, k = k_opt, diss = TRUE)
cat("Robustheit 1 (ohne", sum(tie_sent), "Tie-Sentiment):",
    "avg.sil =", round(pam_r1$silinfo$avg.width, 3), "\n")

## 4b) Ohne Gewichtung der Aufgaben-Diskrepanzen ----------------------
gd_r2 <- daisy(cluster_df, metric = "gower")   # Default: alle Variablen gleich
sil_r2 <- sapply(2:6, function(k) pam(gd_r2, k=k, diss=TRUE)$silinfo$avg.width)
k_r2 <- (2:6)[which.max(sil_r2)]
set.seed(SEED)
pam_r2 <- pam(gd_r2, k = k_r2, diss = TRUE)
# Vergleich mit Hauptloesung: Uebereinstimmung der Clusterzuordnung
tab_r2 <- table(Haupt = data$cluster, Ungewichtet = factor(pam_r2$clustering))
cat("Robustheit 2 (ohne Gewichtung): k =", k_r2,
    "| avg.sil =", round(max(sil_r2),3), "\n")

## 4c) Hierarchisches Clustering (average linkage) --------------------
hc <- hclust(gower_dist, method = "average")
hc_cl <- cutree(hc, k = k_opt)
tab_hc <- table(PAM = data$cluster, Hierarchisch = hc_cl)

# Dendrogramm als Grafik
png("plots/15_dendrogram_average.png", width = 900, height = 550, res = 120)
plot(hc, labels = data$id, main = "Hierarchisches Clustering (Average Linkage, Gower)",
     xlab = "", sub = "", cex = 0.7)
rect.hclust(hc, k = k_opt, border = "#C44E52")
dev.off()

# Uebereinstimmung PAM vs. hierarchisch als Kreuztabellen-Grafik
tab_df <- as.data.frame(tab_hc)
p_agree <- ggplot(tab_df, aes(x = PAM, y = factor(Hierarchisch), fill = Freq)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = Freq), size = 4) +
  scale_fill_gradient(low = "white", high = "#4C72B0") +
  labs(title = "Uebereinstimmung: PAM vs. Average-Linkage",
       x = "PAM-Cluster", y = "Hierarchisches Cluster", fill = "Anzahl") +
  theme_minimal(base_size = 12)
ggsave("plots/16_agreement_pam_hc.png", p_agree, width = 6.5, height = 5, dpi = 150)

cat("Robustheit 3 (Average-Linkage): Dendrogramm + Uebereinstimmung erstellt\n")

cat("Erzeugte Grafiken:", length(list.files("plots")), "\n")

#######################################
# ANHANG: TABELLEN ZU ALLEN GRAFIKEN##
######################################
tab_dir <- file.path(base_path, "tabs")
dir.create(tab_dir, showWarnings = FALSE, recursive = TRUE)

save_tab <- function(df, name) {
  write.csv(df, file.path(tab_dir, name), row.names = FALSE)
  cat("  ", name, "\n")
}

##Stichprobe (zu Grafik 00) 
save_tab(as.data.frame(table(Geschlecht = data$gender_f)), "T00a_geschlecht.csv")
save_tab(as.data.frame(table(Abschluss  = data$degree_f)), "T00b_abschluss.csv")
save_tab(as.data.frame(table(Fach       = data$field_f)),  "T00c_fach.csv")
save_tab(data.frame(Statistik = c("N","Mittelwert","SD","Min","Max"),
                    Alter = c(nrow(data), round(mean(data$age),1), round(sd(data$age),1),
                              min(data$age), max(data$age))), "T00d_alter.csv")

### Diskrepanz (zu Grafiken 01-05)
save_tab(data.frame(id = data$id, D_mean = round(data$D_mean,3),
                    D_MAD = round(data$D_MAD,3)), "T01_dmean_mad_person.csv")
save_tab(data.frame(
  Aufgabe = c("Info","Schreiben","Praktisch","Technisch","Lernen"),
  Mittel  = round(sapply(data[,D_cols], mean),3),
  SD      = round(sapply(data[,D_cols], sd),3),
  Median  = round(sapply(data[,D_cols], median),3),
  Min     = round(sapply(data[,D_cols], min),3),
  Max     = round(sapply(data[,D_cols], max),3)), "T03_diskrepanz_je_aufgabe.csv")
save_tab(as.data.frame(table(Sentiment_Diskrepanz = data$S_Diskrepanz_Label)), "T04_sentiment_diskrepanz.csv")
save_tab(as.data.frame(table(Kritik_Diskrepanz    = data$K_Diskrepanz_Label)), "T05_kritik_diskrepanz.csv")

###Clustering (zu Grafiken 06-11)
save_tab(data.frame(k = 2:6, avg_silhouette = round(sil_avg,3)), "T06_silhouette_k.csv")
save_tab(data.frame(id = data$id, cluster = data$cluster,
                    silhouette = round(sil_obj[,3],3)), "T07_silhouette_person.csv")
save_tab(aggregate(cbind(D_info,D_schreiben,D_praktisch,D_technisch,D_lernen) ~ cluster,
                   data = data, FUN = function(x) round(mean(x),3)), "T08_cluster_profile.csv")
save_tab(data.frame(cluster = levels(data$cluster),
                    groesse = as.integer(table(data$cluster)),
                    medoid_id = data$id[pam_fit$id.med]), "T08b_cluster_groessen.csv")
save_tab(cbind(cluster = rownames(table(data$cluster, data$S_Diskrepanz_Label)),
               as.data.frame.matrix(table(data$cluster, data$S_Diskrepanz_Label))),
         "T10_sentiment_je_cluster.csv")
save_tab(cbind(cluster = rownames(table(data$cluster, data$K_Diskrepanz_Label)),
               as.data.frame.matrix(table(data$cluster, data$K_Diskrepanz_Label))),
         "T11_kritik_je_cluster.csv")

### Clustervergleich (zu Grafiken 12-14) ----
sd_summary <- aggregate(social_desir_mean ~ cluster, data = data,
                        FUN = function(x) round(c(M = mean(x), SD = sd(x), n = length(x)),2))
sd_out <- data.frame(cluster = sd_summary$cluster, sd_summary$social_desir_mean)
sd_out$Welch_p <- round(aov_sd$p.value, 4)
save_tab(sd_out, "T12_socialdesir_cluster.csv")

ord_res <- do.call(rbind, lapply(ord_vars, function(v) {
  kw <- kruskal.test(data[[v]] ~ data$cluster)
  data.frame(Variable = v, Chi2 = round(kw$statistic,3),
             df = kw$parameter, KW_p = round(kw$p.value,4))
}))
save_tab(ord_res, "T13_ordinale_kruskal.csv")

nom_res <- do.call(rbind, lapply(nom_vars, function(v) {
  chi <- suppressWarnings(chisq.test(table(data$cluster, data[[v]]),
                                     simulate.p.value = TRUE, B = 2000))
  data.frame(Variable = v, Chi2 = round(chi$statistic,3),
             Chi_p_sim = round(chi$p.value,4))
}))
save_tab(nom_res, "T14_nominale_chi2.csv")

### Robustheit (zu Grafiken 15-16)##

save_tab(data.frame(
  Check = c("1: ohne Tie-Sentiment","2: ohne Gewichtung","3: Average-Linkage"),
  Beschreibung = c(paste(sum(tie_sent),"Faelle ausgeschlossen"),
                   paste("k =", k_r2), paste("k =", k_opt)),
  avg_silhouette = c(round(pam_r1$silinfo$avg.width,3), round(max(sil_r2),3), NA)),
  "T15_robustheit_uebersicht.csv")
save_tab(as.data.frame(table(PAM = data$cluster, Ungewichtet = pam_r2$clustering)),
         "T15b_pam_vs_ungewichtet.csv")
save_tab(as.data.frame(table(PAM = data$cluster, Hierarchisch = hc_cl)),
         "T16_pam_vs_hierarchisch.csv")


