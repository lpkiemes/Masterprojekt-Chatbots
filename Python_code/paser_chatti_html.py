"""
chat_extractor.py
-----------------
Extrahiert Chat-Verläufe aus ChatGPT-HTML-Exporten und gibt sie als
Python-Objekte zurück – optimiert für den Einsatz in Jupyter Notebooks.

Schnellstart
------------
    from chat_extractor import extract, to_dataframe, to_json

    # Als Liste von Dicts zurückgeben
    history = extract("mein_chat.html")

    # Als pandas DataFrame
    df = to_dataframe("mein_chat.html")

    # In JSON-Datei speichern
    to_json("mein_chat.html", "output.json")

Hinweise zum HTML-Export
------------------------
ChatGPT lädt Nachrichten im Browser lazy – Turns, die beim Speichern
nicht sichtbar waren, werden im HTML als leere Platzhalter-Sections
gespeichert. Diese werden beim Extrahieren übersprungen und als Warnung
ausgegeben. Um alle Nachrichten zu erhalten, vor dem Export bis ganz
oben und unten scrollen, damit alle Nachrichten gerendert wurden.
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import List, Dict, Optional

from bs4 import BeautifulSoup, NavigableString, Tag

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Interne Hilfsfunktionen
# ---------------------------------------------------------------------------

def _code_text_from_viewer(cm_pre: Tag) -> str:
    """
    Rekonstruiert Code-Text aus dem ChatGPT Code-Viewer.

    ChatGPT speichert Code als Folge von <span>-Token, getrennt durch <br>-Tags.
    get_text() liefert dabei kaputte Einrückung – wir iterieren stattdessen
    über alle direkten Kind-Elemente des <code>-Tags.
    """
    code_tag = cm_pre.find("code")
    if not code_tag:
        # Fallback: einfaches get_text mit Newline-Separator
        return cm_pre.get_text(separator="\n", strip=False).strip()

    parts: List[str] = []
    for child in code_tag.children:
        if isinstance(child, NavigableString):
            parts.append(str(child))
        elif isinstance(child, Tag):
            if child.name == "br":
                parts.append("\n")
            else:
                parts.append(child.get_text())

    return "".join(parts).strip()


def _lang_from_code_block(outer_pre: Tag) -> str:
    """
    Liest das Sprachkürzel aus dem Code-Block-Header.

    Struktur: outer <pre> → div.justify-between → linke div mit font-medium → Text + SVG.
    Wir nehmen nur den Text-Node (nicht das SVG-Icon).
    """
    header = outer_pre.find("div", class_=lambda c: "justify-between" in (c or ""))
    if not header:
        return ""
    lang_div = header.find("div", class_=lambda c: "font-medium" in (c or ""))
    if not lang_div:
        return ""
    # Nur Text-Nodes, kein SVG-Text
    text_parts = [
        str(child).strip()
        for child in lang_div.children
        if isinstance(child, NavigableString) and str(child).strip()
    ]
    return text_parts[0] if text_parts else lang_div.get_text(strip=True)


def _parse_chatgpt_code_block(outer_pre: Tag) -> str:
    """Wandelt einen ChatGPT-Code-Block (<pre class='overflow-visible!'>) in Markdown um."""
    lang = _lang_from_code_block(outer_pre)
    cm_pre = outer_pre.find("pre", class_=lambda c: "cm-content" in (c or ""))
    if cm_pre:
        code = _code_text_from_viewer(cm_pre)
    else:
        # Fallback für unbekannte Code-Block-Strukturen
        code = outer_pre.get_text(separator="\n", strip=True)
    return f"```{lang}\n{code}\n```"


def _parse_markdown_div(md_div: Tag) -> str:
    """
    Wandelt den Markdown-Div einer Assistenten-Nachricht in lesbaren Text um.

    Unterstützt: Absätze, Überschriften, Listen, Blockquotes, Tabellen,
    Trennlinien und ChatGPT-spezifische Code-Viewer-Blöcke.
    """
    parts: List[str] = []

    for element in md_div.children:
        if not isinstance(element, Tag):
            continue

        tag = element.name
        if not tag:
            continue

        # ChatGPT Code-Blöcke: <pre class="overflow-visible! px-0!">
        if tag == "pre" and "overflow-visible" in " ".join(element.get("class") or []):
            parts.append(_parse_chatgpt_code_block(element))

        elif tag in ("ul", "ol"):
            items = []
            for i, li in enumerate(element.find_all("li", recursive=False)):
                prefix = "- " if tag == "ul" else f"{i + 1}. "
                items.append(prefix + li.get_text(separator="\n  ", strip=True))
            parts.append("\n".join(items))

        elif tag and tag[0] == "h" and len(tag) == 2 and tag[1].isdigit():
            level = int(tag[1])
            parts.append("#" * level + " " + element.get_text(strip=True))

        elif tag == "blockquote":
            lines = element.get_text(separator="\n", strip=True).split("\n")
            parts.append("\n".join(f"> {line}" for line in lines if line.strip()))

        elif tag == "table":
            parts.append(_parse_table(element))

        elif tag == "hr":
            parts.append("---")

        elif tag == "p":
            # get_text() colliert bei ChatGPT-Export manchmal Inline-Elemente
            # ohne Leerzeichen (z. B. <code>, <strong>). Wir iterieren über
            # Kind-Elemente und fügen fehlende Whitespace ein.
            text_parts: List[str] = []
            for child in element.children:
                chunk = child.get_text() if isinstance(child, Tag) else str(child)
                if text_parts and chunk and not chunk[0].isspace() and not text_parts[-1][-1:].isspace():
                    text_parts.append(" ")
                text_parts.append(chunk)
            parts.append("".join(text_parts).strip())

    return "\n\n".join(p.strip() for p in parts if p.strip())


def _parse_table(table_element: Tag) -> str:
    """Konvertiert eine HTML-Tabelle in Markdown-Format."""
    md_rows: List[str] = []

    thead = table_element.find("thead")
    header_row = thead.find("tr") if thead else table_element.find("tr")

    if header_row:
        header_tags = header_row.find_all(["th", "td"])
        header = [th.get_text(strip=True) for th in header_tags]
        if header:
            md_rows.append("| " + " | ".join(header) + " |")
            md_rows.append("| " + " | ".join(["---"] * len(header)) + " |")

    tbody = table_element.find("tbody") or table_element
    rows = tbody.find_all("tr", recursive=False)

    # Kopfzeile nicht doppelt verarbeiten, wenn kein <thead> vorhanden
    if not thead and rows and rows[0] == header_row:
        rows = rows[1:]

    for row in rows:
        cols = [td.get_text(strip=True) for td in row.find_all("td", recursive=False)]
        if cols:
            md_rows.append("| " + " | ".join(cols) + " |")

    return "\n".join(md_rows)


# ---------------------------------------------------------------------------
# Kern-Parser
# ---------------------------------------------------------------------------

def _parse_html(html_content: str) -> Dict:
    """
    Parst den HTML-Inhalt und gibt Metadaten + Nachrichten zurück.

    Rückgabe
    --------
    dict mit:
        "title"    : str – Titel des Chats (aus <title>)
        "messages" : List[Dict] – Liste der Nachrichten
        "skipped"  : int – Anzahl übersprungener (nicht gerenderte) Turns
    """
    soup = BeautifulSoup(html_content, "html.parser")

    # Titel
    title_tag = soup.find("title")
    chat_title = title_tag.get_text(strip=True) if title_tag else ""

    messages: List[Dict[str, str]] = []
    skipped = 0

    # --- Primäre Methode: <section data-testid="conversation-turn-N"> ---
    # Neues ChatGPT-Export-Format (seit ~2024): sections statt articles
    sections = soup.find_all(
        "section",
        attrs={"data-testid": lambda x: x and x.startswith("conversation-turn-")},
    )

    if sections:
        for section in sections:
            role = section.get("data-turn")  # "user" oder "assistant"
            if role not in ("user", "assistant"):
                continue

            msg_div = section.find("div", attrs={"data-message-author-role": True})

            # Lazy-geladene Turns: Section ist leer (beim Speichern nicht sichtbar)
            if not msg_div:
                turn_id = section.get("data-testid", "?")
                logger.warning(
                    "Überspringe Turn '%s' (nicht gerendert beim Export). "
                    "Scroll vor dem Speichern bis zum Seitenanfang/-ende.",
                    turn_id,
                )
                skipped += 1
                continue

            if role == "user":
                text_div = msg_div.find("div", class_="whitespace-pre-wrap")
                text = text_div.get_text(separator="\n", strip=True) if text_div else None
                if text:
                    messages.append({"speaker": "user", "text": text})

            elif role == "assistant":
                md_div = msg_div.find("div", class_=lambda c: c and "markdown" in c)
                text = _parse_markdown_div(md_div) if md_div else None
                if text:
                    messages.append({"speaker": "assistant", "text": text})

    else:
        # --- Fallback-Methode 1: <article data-testid="conversation-turn-N"> ---
        # Älteres Format
        turns = soup.find_all(
            "article",
            attrs={"data-testid": lambda x: x and x.startswith("conversation-turn-")},
        )

        if turns:
            for turn in turns:
                user_div = turn.find("div", attrs={"data-message-author-role": "user"})
                asst_div = turn.find("div", attrs={"data-message-author-role": "assistant"})

                if user_div:
                    text_div = user_div.find("div", class_="whitespace-pre-wrap")
                    text = text_div.get_text(separator="\n", strip=True) if text_div else None
                    if text:
                        messages.append({"speaker": "user", "text": text})

                elif asst_div:
                    md_div = asst_div.find("div", class_="markdown")
                    text = _parse_markdown_div(md_div) if md_div else None
                    if text:
                        messages.append({"speaker": "assistant", "text": text})

        else:
            # --- Fallback-Methode 2: data-message-author-role direkt ---
            containers = soup.find_all("div", attrs={"data-message-author-role": True})
            for container in containers:
                role = container.get("data-message-author-role")
                if role == "user":
                    text_div = container.find("div", class_="whitespace-pre-wrap")
                    text = text_div.get_text(separator="\n", strip=True) if text_div else None
                elif role == "assistant":
                    md_div = container.find("div", class_="markdown")
                    text = _parse_markdown_div(md_div) if md_div else None
                else:
                    continue

                if text:
                    messages.append({"speaker": role, "text": text})

    return {"title": chat_title, "messages": messages, "skipped": skipped}


# ---------------------------------------------------------------------------
# Öffentliche API
# ---------------------------------------------------------------------------

def extract(html_path: str | Path) -> List[Dict[str, str]]:
    """
    Liest eine HTML-Datei und gibt den Chat-Verlauf als Liste von Dicts zurück.

    Parameter
    ---------
    html_path : str oder Path
        Pfad zur HTML-Datei.

    Rückgabe
    --------
    List[Dict[str, str]]
        Liste mit Einträgen der Form ``{"speaker": "user"|"assistant", "text": "..."}``.

    Raises
    ------
    FileNotFoundError
        Wenn die Datei nicht gefunden wurde.

    Notes
    -----
    ChatGPT rendert Nachrichten lazy im Browser. Turns, die beim Speichern
    des HTML nicht sichtbar waren, werden übersprungen und als Warnung geloggt
    (Logging-Level WARNING). Aktiviere Logging, um diese Warnungen zu sehen::

        import logging
        logging.basicConfig(level=logging.WARNING)
    """
    html_path = Path(html_path)
    if not html_path.exists():
        raise FileNotFoundError(f"HTML-Datei nicht gefunden: {html_path}")

    html_content = html_path.read_text(encoding="utf-8")
    result = _parse_html(html_content)
    return result["messages"]


def extract_with_meta(html_path: str | Path) -> Dict:
    """
    Wie ``extract()``, gibt aber auch Metadaten zurück.

    Rückgabe
    --------
    dict mit:
        "title"    : str  – Titel des Chats
        "messages" : list – Nachrichten (wie bei extract())
        "skipped"  : int  – Anzahl übersprungener Turns (lazy-loaded)

    Beispiel
    --------
    ::

        result = extract_with_meta("chat.html")
        print(result["title"])
        print(f"{result['skipped']} Turns wurden übersprungen.")
        for msg in result["messages"]:
            print(msg["speaker"], msg["text"][:80])
    """
    html_path = Path(html_path)
    if not html_path.exists():
        raise FileNotFoundError(f"HTML-Datei nicht gefunden: {html_path}")

    html_content = html_path.read_text(encoding="utf-8")
    return _parse_html(html_content)


def to_json(
    html_path: str | Path,
    json_path: Optional[str | Path] = None,
    *,
    indent: int = 2,
    ensure_ascii: bool = False,
    include_meta: bool = False,
) -> Path:
    """
    Extrahiert den Chat-Verlauf und speichert ihn als JSON-Datei.

    Parameter
    ---------
    html_path : str oder Path
        Pfad zur HTML-Quelldatei.
    json_path : str, Path oder None
        Zielpfad für die JSON-Datei. Wenn None, wird der gleiche Dateiname
        wie die HTML-Datei mit der Endung ``.json`` verwendet.
    indent : int
        Einrückung für die JSON-Ausgabe (Standard: 2).
    ensure_ascii : bool
        Wenn False, werden Unicode-Zeichen direkt geschrieben (Standard: False).
    include_meta : bool
        Wenn True, wird das komplette Meta-Dict (inkl. Titel und skipped-Zähler)
        gespeichert statt nur die Nachrichten-Liste.

    Rückgabe
    --------
    Path
        Pfad zur geschriebenen JSON-Datei.
    """
    html_path = Path(html_path)
    if json_path is None:
        json_path = html_path.with_suffix(".json")
    json_path = Path(json_path)

    result = extract_with_meta(html_path)
    payload = result if include_meta else result["messages"]

    json_path.write_text(
        json.dumps(payload, ensure_ascii=ensure_ascii, indent=indent),
        encoding="utf-8",
    )
    return json_path


def to_dataframe(html_path: str | Path):
    """
    Extrahiert den Chat-Verlauf und gibt ihn als ``pandas.DataFrame`` zurück.

    Spalten: ``turn`` (beginnt bei 1), ``speaker``, ``text``.

    Parameter
    ---------
    html_path : str oder Path
        Pfad zur HTML-Quelldatei.

    Rückgabe
    --------
    pandas.DataFrame

    Raises
    ------
    ImportError
        Wenn pandas nicht installiert ist.
    """
    try:
        import pandas as pd
    except ImportError as exc:
        raise ImportError(
            "pandas ist nicht installiert. Bitte mit 'pip install pandas' nachinstallieren."
        ) from exc

    history = extract(html_path)
    df = pd.DataFrame(history)
    if not df.empty:
        df.insert(0, "turn", range(1, len(df) + 1))
    return df

