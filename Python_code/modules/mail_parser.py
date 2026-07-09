"""
Parser für SoSci-Benachrichtigungsmails.

Wenn ein Interview mehr Daten erhebt als SoSci speichern kann (64 KB),
verschickt SoSci eine Mail mit den gelöschten Angaben. Diese Mails liegen
als .eml unter data/raw/data_sosci/Mail. Aufbau des Mail-Texts:

    In dem Interview Nr. 257 wurden mehr Daten erhoben (...) ...
    Die folgenden Angaben mussten gelöscht werden:

    CH02s = [ { "role": "user", "content": "..." }, ... ]

    CH08s = [ ... ]

Die CASE-Nummer steht in "dem Interview Nr. <n>", danach folgt pro Zeile
eine Variable mit ihrem Wert (hier ausschließlich JSON-Chatlogs). Die Werte
werden als Roh-Strings in den Survey-DataFrame zurückgeschrieben, bevor die
JSON-Spalten ins Long-Format transformiert werden.
"""
from __future__ import annotations

import email
import email.policy
import re
from pathlib import Path

import pandas as pd
from json_repair import repair_json

# "In dem Interview Nr. 257 wurden mehr Daten erhoben ..."
CASE_RE = re.compile(r"dem Interview Nr\.\s*(\d+)")

# Variablenzeile: "CH02s = [ ... ]" (Wert steht nach QP-Dekodierung in einer Zeile)
VAR_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_]*)\s*=\s*(\S.*)$")


def _read_body(eml_path: Path) -> str:
    msg = email.message_from_bytes(Path(eml_path).read_bytes(),
                                   policy=email.policy.default)
    body = msg.get_body(preferencelist=("plain",))
    if body is None:
        raise ValueError(f"Kein Text-Body in {eml_path}")
    return body.get_content()


def parse_mail(eml_path: Path) -> tuple[int, dict[str, str]]:
    body = _read_body(eml_path)

    m = CASE_RE.search(body)
    if m is None:
        raise ValueError(f"Keine Interview-Nr. in {eml_path} gefunden")
    case = int(m.group(1))

    values: dict[str, str] = {}
    for line in body.splitlines():
        vm = VAR_RE.match(line.strip())
        if vm is None:
            continue
        name, raw = vm.group(1), vm.group(2).strip()
        # Plausibilitätscheck: Wert muss (ggf. nach Reparatur) ein JSON sein.
        # Unescapte Anführungszeichen etc. repariert später ohnehin
        # json_parser_theo.extract_messages via json_repair.
        try:
            repaired = repair_json(raw, return_objects=True)
        except Exception:
            repaired = None
        if not repaired:
            print(f"WARNUNG: {eml_path.name}: {name} ist auch nach Reparatur "
                  f"kein JSON - Wert wird trotzdem übernommen")
        values[name] = raw

    if not values:
        raise ValueError(f"Keine Variablen in {eml_path} gefunden")
    return case, values


def parse_mail_dir(mail_dir: Path) -> dict[int, dict[str, str]]:
    result: dict[int, dict[str, str]] = {}
    for eml in sorted(Path(mail_dir).glob("*.eml")):
        case, values = parse_mail(eml)
        result.setdefault(case, {}).update(values)
    return result


#API

def apply_mail_values(df: pd.DataFrame, mail_dir: Path,
                      case_col: str = "CASE",
                      verbose: bool = True) -> pd.DataFrame:

    df = df.copy()
    for case, values in parse_mail_dir(mail_dir).items():
        mask = df[case_col].astype(int) == case
        if not mask.any():
            print(f"WARNUNG: CASE {case} aus Mail nicht im Survey-Datensatz")
            continue
        for name, raw in values.items():
            if name not in df.columns:
                print(f"WARNUNG: Spalte {name} (CASE {case}) nicht im Datensatz")
                continue
            existing = df.loc[mask, name]
            if existing.notna().any() and (existing.astype(str).str.strip() != "").any():
                print(f"WARNUNG: {name} (CASE {case}) war nicht leer "
                      f"- wird mit Mail-Wert überschrieben")
            df.loc[mask, name] = raw
            if verbose:
                print(f"CASE {case}: {name} aus Mail übernommen "
                      f"({len(raw) / 1024:.0f} KB)")
    return df
