import pandas as pd
from pathlib import Path
from json_repair import repair_json

# ── Hilfsfunktion: Extrahiert alle {role, content}-Dicts aus beliebig
#    verschachtelten Listen/Dicts (rekursiv, Tiefensuche)
def flatten_messages(data) -> list:
    if isinstance(data, dict):
        # Gültiger Message-Node: muss role=user/assistant UND content haben
        if data.get("role") in ("user", "assistant") and "content" in data:
            return [data]
        return []
    if isinstance(data, list):
        # Für jedes Element rekursiv aufrufen und Ergebnisse zusammenführen
        return [msg for item in data for msg in flatten_messages(item)]
    return []  # Alles andere (str, int, …) ignorieren


def extract_messages(raw: str) -> list:
    stripped = raw.strip()

    # ── Fall 1: Datei endet mit ] aber fängt nicht mit [ an
    #    → nur [ vorne anfügen
    if stripped.endswith("]") and not stripped.startswith("["):
        raw = "[" + stripped

    # ── Fall 2: Datei hat weder [ noch ] (nur Objekte mit Kommas)
    #    → [ vorne und ] hinten anfügen
    elif stripped.startswith("{") and not stripped.startswith("["):
        raw = "[" + stripped + "]"

    else:
        # Alles vor dem ersten '[' wegschneiden (Fehlertext, BOM etc.)
        bracket = stripped.find("[")
        if bracket == -1:
            return []
        raw = stripped[bracket:]


    # Stufe 1 – Globale Reparatur
    try:
        valid = flatten_messages(repair_json(raw, return_objects=True))
        if valid:
            return valid
    except Exception:
        pass

    # Stufe 2 – Klammer-Zähler (unverändert)
    candidates, i = [], 0
    while i < len(raw):
        if raw[i] == "[":
            depth = 0
            for j in range(i, len(raw)):
                depth += raw[j] == "["
                depth -= raw[j] == "]"
                if depth == 0:
                    candidates.append(raw[i:j+1])
                    break
        i += 1

    best = []
    for c in candidates:
        try:
            valid = flatten_messages(repair_json(c, return_objects=True))
        except Exception:
            continue
        if len(valid) > len(best):
            best = valid
    return best


# ── Liest alle *.json-Dateien eines Ordners ein und baut einen DataFrame.
#    Jede Zeile = eine Nachricht; chat_id und turn nummerieren Gespräche/Züge.
def load_chats_from_folder(folder_path: str) -> pd.DataFrame:
    dfs, skipped = [], []

    for chat_id, path in enumerate(sorted(Path(folder_path).glob("*.json")), start=1):
        messages = extract_messages(path.read_text(encoding="utf-8"))  # open+read in einem

        if not messages:
            skipped.append(path.name)
            print(f"Keine validen Nachrichten: {path.name}")
            continue

        dfs.append(pd.DataFrame({
            "file_name": path.stem,
            "chat_id":   chat_id,
            "turn":      range(1, len(messages) + 1),
            "role":      [m["role"]    for m in messages],
            "content":   [m["content"] for m in messages],
        }))

    if skipped:
        print(f"\nÜbersprungen ({len(skipped)} Dateien): {skipped}")
    if not dfs:
        raise FileNotFoundError(f"Keine verwertbaren JSON-Dateien in '{folder_path}'.")

    return pd.concat(dfs, ignore_index=True)  # Alle Teil-DataFrames zu einem zusammenführen