# Workflow-Dokumentation: Masterprojekt Chatbots

Diese Datei beschreibt den kompletten Daten- und Analyse-Workflow des Projekts.
Er besteht aus zwei Phasen: Zuerst wird der LLM-Klassifikator entwickelt
und validiert (Goldstandard + Evaluations-Pipeline), danachläuft die
eigentliche Erhebung über SoSci Survey mit Parsing, Klassifikation und
statistischer Analyse in R. Ziel des Projekts ist der Vergleich von
**Selbstauskunft (SA)** und **beobachtetem Verhalten (BE)** bei der
ChatGPT-Nutzung Studierender (Aufgabentypen, Ton/Sentiment, kritisches
Nachfragen).

---

## 1. Überblick

```
 PHASE A — Klassifikator-Validierung (VOR der eigentlichen Erhebung)
 ┌──────────────────────  Gold_standard.ipynb  ────────────────────────┐
 │ 30 selbst gesammelte Chats -> mischen -> 3 Coder codieren           │
 │ -> Intercoder-Reliabilität (Krippendorff / Cohen)                   │
 │ -> konsolidierter Goldstandard: gs_merged.csv                       │
 └────────────────────────────────┬────────────────────────────────────┘
                                  ▼
 ┌───────────────  llm_pipeline_openai_gold.ipynb  ────────────────────┐
 │ Testet Prompt-Strategien (separat vs. kombiniert) und Modelle       │
 │ gegen den Goldstandard (Accuracy, F1, ...)                          │
 │ -> validierter kombinierter Prompt + Modellwahl für Phase B         │
 └────────────────────────────────┬────────────────────────────────────┘
                                  │
 PHASE B — Haupterhebung und Analyse
                                  ▼
                         ┌──────────────────────────────┐
                         │   SoSci Survey (Erhebung)    │   
                         │  Fragebogen + Chat-Uploads   │
                         └──────────────┬───────────────┘
                                        │  (2 APIs)
                                        ▼
 ┌───────────────────────  Data_pipeline.ipynb  ───────────────────────┐
 │ 1. Download Survey-CSV + hochgeladene HTML-Chatlogs                 │
 │ 2. Survey bereinigen  ->  survey_clean.csv                          │
 │ 3. Chats parsen (JSON aus CSV + HTML-Uploads) -> chats_long.csv     │                  ┌───────────────────────┐
 │ 4. Chats klassifizieren (validierter Prompt aus Phase A,            │ ---------------> | Zweite LLM-Evautazion |
 │    modules/classify_chats.py)  ->  chats_labeled.csv                │                  └───────────────────────┘
 │ 5. Auf Personenebene aggregieren + mit Survey mergen                │
 │    -> perp_dataset.csv                                              │
 └────────────────────────────────┬────────────────────────────────────┘
                                  ▼
 ┌────────────────────────  data_prep.R  ──────────────────────────────┐
 │ Operationalisierung: BE-Anteile, Modus-Werte, Diskrepanzmaße,       │
 │ soziale Erwünschtheit, Labels, Fallausschluss                       │
 │ -> analysis_dataset.csv / analysis_dataset.rds                      │
 └────────────────────────────────┬────────────────────────────────────┘
                                  ▼
 ┌────────────────────────  data_analasys.R  ──────────────────────────┐
 │ Deskriptive Statistik, PAM-Clusteranalyse (Gower), Clustervergleich,│
 │ Robustheitschecks  ->  plots/*.png  +  tabs/*.csv                   │
 │                        +  tabs/tabellen_report.md                   │
 └──────────────────────────────────────────────────────────────────────┘
```

---

## 2. Verzeichnisstruktur

| Pfad | Inhalt |
|---|---|
| `Python_code/Gold_standard.ipynb` | Phase A: Erstellung des Goldstandards + Intercoder-Reliabilität |
| `Python_code/llm_pipeline_openai_gold.ipynb` | Phase A: Evaluation des LLM-Klassifikators gegen den Goldstandard |
| `Python_code/Data_pipeline.ipynb` | Phase B: Download, Parsing, Klassifikation, Aggregation |
| `Python_code/modules/json_parser_theo.py` | Parser für JSON-Chat-Exporte (mit Reparatur defekter JSONs) |
| `Python_code/modules/paser_chatti_html.py` | Parser für ChatGPT-HTML-Exporte |
| `Python_code/modules/classify_chats.py` | LLM-Klassifikation der Chats (LangChain + OpenAI) |
| `Python_code/data_prep.R` | Phase B: Datenaufbereitung / Operationalisierung |
| `Python_code/data_analasys.R` | Phase B: Statistische Analyse (Deskriptiv + Clusteranalyse) |
| `Python_code/Inactive/` | Ältere/inaktive Notebook-Versionen (nicht Teil des Workflows) |
| `API_KEYS/` | API-Schlüssel (nicht versioniert!) — siehe Abschnitt 3 |
| `data/raw/json/` | Die 30 selbst gesammelten Chats für den Goldstandard (Phase A) |
| `data/raw/data_sosci/` | Roh-Download: `daten.csv`, `chatlog_mapping.csv`, `uploads/<id>/*.html` |
| `data/processed/control/` | Codierbögen der drei Coder + Goldstandard |
| `data/processed/llm_evaluation/` | Ergebnisse der LLM-Evaluation |
| `data/processed/` | Alle aufbereiteten Datensätze (siehe Abschnitt 8) |
| `plots/` | Alle Grafiken aus `data_analasys.R` |
| `tabs/` | Alle Tabellen (CSV) + `tabellen_report.md` (formatiert) |

---

## 3. Voraussetzungen

**Python** (Conda-Environment `masterprojekt-chatbots`, Python 3.13):
`pandas`, `numpy`, `requests`, `beautifulsoup4`, `json-repair`,
`langchain`, `langchain-openai`, `scikit-learn`, `krippendorff`,
optional `torch`/`transformers` (nur für lokale Modelle in der Evaluation).

**R** (≥ 4.x): `cluster`, `ggplot2`, `patchwork`, `labelled`, `scales`, `knitr`
(werden von `data_analasys.R` bei Bedarf automatisch installiert).

**API-Schlüssel** in `API_KEYS/` (je eine Textdatei, nur der Schlüssel/die URL):

| Datei | Zweck |
|---|---|
| `sosci_data_key.txt` | Komplette URL der einfachen SoSci-Daten-API (projektgebunden, liefert die Survey-CSV) |
| `sosci_per_header.txt` | `Authorization`-Header der SoSci-REST-API (personengebunden, für die Datei-Uploads) |
| `openai_key.txt` | OpenAI-API-Key für die Chat-Klassifikation und die Evaluation |

**Wichtig:** Die Notebooks setzen als Arbeitsverzeichnis `Python_code/` voraus
(`repo = Path(".").resolve().parent`). Beim Ausführen außerhalb von
PyCharm/Jupyter zusätzlich `PYTHONPATH` auf die Repo-Wurzel setzen, damit
`from Python_code.modules import ...` funktioniert.

---

## PHASE A — Klassifikator-Validierung

## 4. Schritt 1 — `Gold_standard.ipynb` (Goldstandard + Intercoder-Reliabilität)

Bevor der LLM-Klassifikator auf die echten Erhebungsdaten losgelassen wird,
wird er an einem manuell codierten Goldstandard validiert. Grundlage sind
**30 selbst gesammelte Chats** in `data/raw/json/`:

1. Alle JSONs einlesen (`load_chats_from_folder`) → 30 Chats, 289 Nachrichten.
2. Nur User-Nachrichten behalten (`df_user`), Chat-Reihenfolge mit festem Seed
   (42) mischen und IDs neu vergeben → `user_shuffel.csv` (Codiervorlage),
   `control.csv` (leerer Codierbogen), `user.csv`.
3. **Drei Coder** (A = Hannah, B = Theo, C = Laura) codieren unabhängig.
   Runde 1 enthält auch `task`; **Runde 2 nur `sentiment` und `critical`**
   (deshalb ist die `task`-Spalte in den Runde-2-Dateien leer):
   - Runde 1: `control_hannah.csv`, `control_theo_2.csv`, `control_laura.csv`
   - Runde 2: `control_hannah_2.csv`, `round_2.csv`, `control_laura_runde2.csv`
4. **Reliabilität:** Krippendorffs Alpha (sentiment: ordinal, critical:
   nominal) für alle Coder-Kombinationen, plus Cohens Kappa paarweise
   (task aus Runde 1, sentiment/critical aus Runde 2). Uneinige Chats werden
   ausgegeben und diskursiv aufgelöst.
5. Der konsolidierte **Goldstandard** (`gs.csv`) wird mit den Chat-Texten
   gemergt → **`gs_merged.csv`** — Input der Evaluations-Pipeline.

Codierung im Goldstandard: `task` 1–5 (Reihenfolge wie in Abschnitt 6.3),
`sentiment` 1 = Unfreundlich, 2 = Neutral, 3 = Freundlich,
`critical` 0 = Nein, 1 = Ja.

---

## 5. Schritt 2 — `llm_pipeline_openai_gold.ipynb` (LLM-Evaluation)

Vergleicht **zwei Prompt-Strategien** über (konfigurierbare) Modelle am
Goldstandard, um Prompt und Modell für die Haupt-Pipeline (Phase B)
festzulegen:

- **Separat:** drei einzelne Prompts (task / sentiment / critical) pro Chat.
- **Kombiniert:** ein Prompt, der alle drei Kriterien gleichzeitig abfragt.

Ablauf: `gs_merged.csv` laden → Export-Prompt-Zeilen entfernen → Nachrichten
pro Chat zu einem Text zusammenfügen (`User_Nachricht_i: …`) → Zahlencodes auf
Label-Strings mappen → Pydantic-Validierung → pro Modell beide Strategien
laufen lassen. Im `llm_registry` können neben OpenAI-Modellen auch lokale
HuggingFace-Modelle (Phi-3, Mistral-7B, Llama-3-8B; GPU nötig) aktiviert
werden — standardmäßig ist nur `gpt-5.5` aktiv.

**Metriken** (scikit-learn): Accuracy, Precision/Recall/F1 (macro),
Unknown-Rate, Latenz; zusätzlich Classification-Reports und ein
Chat-für-Chat-Vergleich. Ergebnisse:
`data/processed/llm_evaluation/eval_results.csv` (Zusammenfassung) und
`eval_results_detail.csv` (pro Chat).

**Ergebnis der Phase A:** Der **kombinierte** Prompt mit `gpt-5.5` wird
übernommen — er läuft wortgleich in `modules/classify_chats.py` produktiv
(Abschnitt 6.3). Die hier gemessene Güte gilt damit für genau den
Klassifikator der Haupterhebung.

---

## PHASE B — Haupterhebung und Analyse

## 6. Schritt 3 — `Data_pipeline.ipynb` (Haupt-Pipeline)

### 6.1 Download über die SoSci-APIs (Zelle 1)

Es werden **zwei verschiedene APIs** verwendet:

1. **Einfache Daten-API** (nur URL, projektgebunden): lädt die komplette
   Survey-CSV herunter → `data/raw/data_sosci/daten.csv`.
2. **REST-API** (personengebunden, `Authorization`-Header): listet die von
   den Teilnehmenden hochgeladenen Dateien
   (`GET /projects/5393/uploads`) und lädt sie einzeln herunter.

Die Dateinamen der Uploads folgen dem Muster `CHxx.0000yy.html`
(Frage-Code + Teilnehmer-ID). Ein Regex zerlegt den Namen, die Dateien werden
pro Person in `data/raw/data_sosci/uploads/<teilnehmer_id>/` abgelegt und eine
Zuordnungstabelle wird geschrieben: `chatlog_mapping.csv`
(Spalten: `teilnehmer_id`, `frage_code`, `dateiname`, `pfad`). Zwischen den
Downloads liegt ein `sleep(0.2)`, um den Server zu schonen; Fehler bei einer
Datei brechen den Lauf nicht ab, sondern werden nur gemeldet.

### 6.2 Survey bereinigen + Chats parsen (Zelle 2)

- **Survey:** Zeit- und Metavariablen (`TIME…`, `MAILSENT`, `LASTPAGE`, …)
  werden entfernt → `data/processed/survey_clean.csv`.
- **Chats aus der CSV (JSON-Direkteingabe):** Die Teilnehmenden konnten Chats
  auch als JSON-Text in Freitextfelder einfügen (`CH02s`, `CH06s`–`CH09s`).
  Diese werden mit `json_parser_theo.extract_messages()` geparst.
- **Chats aus den HTML-Uploads:** über das Mapping mit
  `paser_chatti_html.extract()` geparst.
- Beide Quellen werden zusammengeführt (`quelle` = `json_csv` / `html_upload`),
  jede Person×Frage-Kombination bekommt eine `chat_id`, jede Nachricht eine
  `turn`-Nummer → `data/processed/chats_long.csv`
  (long-Format: 1 Zeile = 1 Nachricht).

**Hinweise zu den Parsern:**

- `json_parser_theo` repariert defekte JSON-Exporte mehrstufig:
  typografische Anführungszeichen normalisieren → fehlende Klammern ergänzen →
  `json_repair` global → notfalls Klammer-Zählung über Teilstrings. Der
  Export-Prompt selbst („…gesamten sichtbaren bisherigen Dialog…") wird
  herausgefiltert, da er kein echter Chat-Inhalt ist.
- `paser_chatti_html` unterstützt drei ChatGPT-Exportformate
  (`<section data-testid="conversation-turn-N">`, älter `<article …>`,
  Fallback über `data-message-author-role`) und rekonstruiert
  Assistenten-Antworten als Markdown (Codeblöcke, Listen, Tabellen, …).
  **Bekannte Einschränkung:** Beim Speichern der Seite nicht gerenderte
  (lazy-geladene) Turns sind im HTML leer und werden mit einer Warnung
  übersprungen („Überspringe Turn … nicht gerendert beim Export").

### 6.3 LLM-Klassifikation (Zelle 3)

`modules/classify_chats.py` klassifiziert jeden Chat (nur die
**User-Nachrichten**) mit dem in Phase A validierten **kombinierten Prompt**
über GPT (Standard: `gpt-5.5`, `temperature=0`) nach drei Kriterien:

| Kriterium | Labels |
|---|---|
| `task` | Informationssuche und Verständnis · Schreiben und Textarbeit · Praktische Unterstützung und Strukturierung · Technische und analytische Unterstützung · Lernen und Prüfungsvorbereitung |
| `sentiment` | Freundlich · Neutral · Unfreundlich |
| `critical` | Ja · Nein (3-Schritt-Prüfschema im Prompt) |

Antworten werden zeilenweise geparst (`TASK:` / `SENTIMENT:` / `CRITICAL:`);
nicht zuzuordnende Antworten erhalten das Label `unknown`.
Ergebnis: `data/processed/chats_labeled.csv` (1 Zeile = 1 Chat).

### 6.4 Aggregation auf Personenebene (Zellen 4–5)

`aggregate_to_person()` zählt pro Person die Rohcounts je Label
(`obs_info_n`, …, `obs_sent_freundlich_n`, …, `obs_kritisch_ja_n`, …) plus
`n_chats_valid`. Chats mit `unknown`-Labels werden (optional, Standard: ja)
entfernt. **Konsistenzchecks** (asserts): Die Counts jeder der drei
Kategoriengruppen müssen sich pro Person zu `n_chats_valid` summieren.

### 6.5 Mapping + Merge (Zelle 6)

`map_survey()` benennt die SoSci-Spalten in sprechende Namen um
(`CASE`→`id`, `DE01`→`gender`, `info_use_*`, `sd_*`, …), rekodiert:

- `age`: Dropdown-Index → echtes Alter (Index + 15),
- KI-Tool-Mehrfachauswahl (`NU02_*`): `T/F` bzw. `2/1` → `0/1`,
- SoSci-Missing-Codes `-1`/`-9` → `NA`.

`merge_survey_chatlogs()` verbindet Survey und Chat-Counts über `id`
(inner join) → **`data/processed/perp_dataset.csv`** — der finale
Personendatensatz für R.

---

## 7. Schritte 4–5 — R-Analyse

### 7.1 `data_prep.R` (Operationalisierung)

> **Achtung:** Aktuell arbeitet das Skript mit einem **simulierten Datensatz**
> (n = 30, direkt im Skript definiert), weil die echte Erhebung noch läuft.
> Für die echten Daten den `data.frame(...)`-Block entfernen und stattdessen
> die auskommentierte Zeile `read.csv(".../perp_dataset.csv")` aktivieren —
> die Spaltennamen sind identisch.

Schritte:

1. **Konsistenzchecks:** Rohcounts jeder Kategoriengruppe = `n_chats_valid`.
2. **Beobachtete Anteile (BE):** `BE_i = obs_i_n / n_chats_valid` für die
   fünf Aufgabentypen.
3. **Modus-Sentiment** über alle Chats einer Person (−1 = freundlich,
   0 = neutral, 1 = unfreundlich); Tie-Break: bei Gleichstand gewinnt die
   neutralere Kategorie.
4. **Modus-Kritik** (0/1); bei Gleichstand `NA` (= uneindeutig).
5. **Diskrepanzmaße:**
   - Aufgaben: Selbstauskunft `info_use_i` (1–5) auf [0,1] reskaliert
     (`SA_i = (x−1)/4`), dann `D_i = SA_i − BE_i`
     (> 0 = Überschätzung, < 0 = Unterschätzung).
   - Sentiment: `inter_style` (1–5) auf 3 Kategorien rekodiert, dann
     `S_Diskrepanz = sign(SA − BE)` mit Labels
     *unfreundlicher / korrekt / freundlicher*.
   - Kritik: `crit_visible_chat` dichotomisiert (≥ 3 = Ja), dann
     `K_Diskrepanz = BE − SA` mit Labels
     *falsches positiv / korrekt / falsches negativ*.
6. **Soziale Erwünschtheit:** 3 negativ gepolte Items umpolen, Summen- und
   Mittelwertscore über 6 Items (KSE-G-Logik).
7. **Labels:** Variablen- und Wertelabels über das `labelled`-Paket.
8. **Fallausschluss:** nur Personen mit exakt 5 gültigen Chats bleiben im
   Analysedatensatz → `analysis_dataset.csv` + `analysis_dataset.rds`.

### 7.2 `data_analasys.R` (Analyse, Grafiken, Tabellen)

Das Skript lädt `analysis_dataset.rds` und erzeugt alle Grafiken (`plots/`)
und Tabellen (`tabs/`).

**Design-System (am Skriptanfang):** Eine feste, farbfehlsichtigkeits-geprüfte
Palette (`PAL_CAT`, 8 Slots — Reihenfolge nie ändern), divergierende Skala
blau ↔ grau ↔ rot für Diskrepanzen (blau = Unterschätzung,
rot = Überschätzung, grau = korrekt), ein gemeinsames `theme_projekt()`
und einheitliche Aufgaben-Labels. Alle Faktoren tragen Klartext-Labels
(Geschlecht, Fach, Abschluss, Antwortskalen) statt Zahlencodes;
uneindeutige Fälle (Ties) erscheinen als eigene Kategorie „uneindeutig".

Die Analyse selbst ist in fünf Blöcke gegliedert:

1. **Stichprobenbeschreibung** (Grafik 00, Tabellen T00a–d).
2. **Deskriptive Diskrepanzmaße:** `D_mean` (Richtung) und `D_MAD` (Ausmaß)
   pro Person, Verteilungen, Boxplots je Aufgabentyp, Häufigkeiten der
   kategorialen Diskrepanzen (Grafiken 01–05, Tabellen T01–T05).
3. **PAM-Clusteranalyse** auf Gower-Distanz: 5 metrische `D_i` (Gewicht je
   0.2) + 2 ordinale Diskrepanzen (Gewicht je 1). Wahl von k über die
   durchschnittliche Silhouette (k = 2…10), Silhouetten pro Person,
   Cluster-Profil-Heatmap, MDS-Projektion, kategoriale Diskrepanzen je
   Cluster (Grafiken 06–11, Tabellen T06–T11). Seed: 404.
4. **Clustervergleich** mit nicht im Clustering verwendeten Kontextvariablen:
   soziale Erwünschtheit (Welch-ANOVA), ordinale Variablen (Kruskal-Wallis),
   nominale Variablen (Chi²-Test mit simuliertem p-Wert; Kategorien > 8
   werden nur für die Darstellung zu „andere" gebündelt)
   (Grafiken 12–14, Tabellen T12–T14).
5. **Robustheitschecks:** (a) ohne Tie-Sentiment-Fälle, (b) ohne Gewichtung,
   (c) hierarchisches Clustering (Average Linkage) inkl. Dendrogramm und
   Kreuztabellen-Vergleich mit PAM (Grafiken 15–16, Tabellen T15–T16).

Alle Tabellen werden doppelt geschrieben: einzeln als CSV **und** gesammelt,
formatiert und beschriftet in **`tabs/tabellen_report.md`**.

---


### Wichtigste Zwischen- und Endprodukte

| Datei | Erzeugt von | Inhalt |
|---|---|---|
| `data/processed/control/gs_merged.csv` | Gold_standard (Phase A) | Goldstandard mit Chat-Texten |
| `data/processed/llm_evaluation/eval_results*.csv` | llm_pipeline (Phase A) | Güte des Klassifikators |
| `data/raw/data_sosci/daten.csv` | Data_pipeline (Z.1) | Roh-Survey (SoSci-Export, Tab-getrennt) |
| `data/raw/data_sosci/chatlog_mapping.csv` | Data_pipeline (Z.1) | Zuordnung Person ↔ Upload-Datei |
| `data/processed/survey_clean.csv` | Data_pipeline (Z.2) | Survey ohne Meta-/Zeitvariablen |
| `data/processed/chats_long.csv` | Data_pipeline (Z.2) | Alle Chat-Nachrichten, long-Format |
| `data/processed/chats_labeled.csv` | Data_pipeline (Z.3) | 1 Zeile pro Chat mit task/sentiment/critical |
| `data/processed/perp_dataset.csv` | Data_pipeline (Z.6) | Personendatensatz: Survey + Chat-Counts |
| `data/processed/analysis_dataset.rds/.csv` | data_prep.R | Finaler Analysedatensatz |
| `plots/00…16_*.png` | data_analasys.R | Alle Grafiken |
| `tabs/T00…T16_*.csv`, `tabs/tabellen_report.md` | data_analasys.R | Alle Tabellen |

---
