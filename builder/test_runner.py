#!/usr/bin/env python3
"""Verification test script for Glimpse references scanner."""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURE = os.path.join(HERE, "fixture_extracted")

LABELS = {
    "characters": ["characters", "character list", "cast of characters", "cast", "dramatis personae", "persons of the tale", "dramatis personæ", "list of characters", "people"],
    "glossary": ["glossary", "vocabulary", "terms", "lexicon", "dictionary"],
    "places": ["places", "locations", "gazetteer", "map", "maps"],
    "timeline": ["timeline", "chronology", "chronicle", "history"],
    "reference": ["appendix", "appendices", "pronunciation", "pronunciation guide", "family tree", "genealogy", "notes", "bibliography"],
}

def collapse_ws(s):
    return re.sub(r"\s+", " ", s).strip()

def clean_text(s):
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r" *\n *", "\n", s)
    s = re.sub(r"\n\n\n+", "\n\n", s)
    return s.strip()

def unescape(s):
    s = re.sub(r"&#x([0-9a-fA-F]+);", lambda m: chr(int(m.group(1), 16)) if int(m.group(1), 16) < 128 else "", s)
    s = re.sub(r"&#(\d+);", lambda m: chr(int(m.group(1))) if int(m.group(1)) < 128 else "", s)
    repl = {
        "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&apos;": "'",
        "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…",
        "&lsquo;": "‘", "&rsquo;": "’", "&ldquo;": "“", "&rdquo;": "”"
    }
    for k, v in repl.items():
        s = s.replace(k, v)
    return s

def plain(html):
    html = re.sub(r"<!--.-!-->", " ", html, flags=re.DOTALL)
    html = re.sub(r"<script.*?</script>", " ", html, flags=re.DOTALL | re.IGNORECASE)
    html = re.sub(r"<style.*?</style>", " ", html, flags=re.DOTALL | re.IGNORECASE)
    html = re.sub(r"<br\s*/?>", "\n", html, flags=re.IGNORECASE)
    html = re.sub(r"</p>", "\n\n", html, flags=re.IGNORECASE)
    html = re.sub(r"</h[1-6]>", "\n\n", html, flags=re.IGNORECASE)
    html = re.sub(r"</dt>", "\n", html, flags=re.IGNORECASE)
    html = re.sub(r"</dd>", "\n\n", html, flags=re.IGNORECASE)
    html = re.sub(r"</li>", "\n", html, flags=re.IGNORECASE)
    html = re.sub(r"</tr>", "\n", html, flags=re.IGNORECASE)
    html = re.sub(r"</div>", "\n", html, flags=re.IGNORECASE)
    html = re.sub(r"</section>", "\n", html, flags=re.IGNORECASE)
    html = re.sub(r"</article>", "\n", html, flags=re.IGNORECASE)
    html = re.sub(r"<[^>]+>", " ", html)
    return unescape(html)

def kind_for(label):
    label = collapse_ws(label or "").lower()
    for kind, words in LABELS.items():
        for word in words:
            if label == word or re.match(r"^" + re.escape(word) + r"[\s:\-—]", label):
                return kind
    return None

def main():
    print("Testing fixture references...")
    char_file = os.path.join(FIXTURE, "OEBPS", "text", "characters.xhtml")
    assert os.path.exists(char_file), "characters.xhtml missing"
    with open(char_file, "r") as f:
        html = f.read()

    kind = kind_for("Characters")
    assert kind == "characters", f"Expected 'characters', got '{kind}'"

    # False positive test
    false_kind = kind_for("Chapter 3: Characters of the Night")
    assert false_kind is None, f"Expected None for false positive chapter, got '{false_kind}'"

    text = clean_text(plain(html))
    print(f"Extracted characters text:\n---\n{text}\n---")
    assert "Ada Rowan" in text, "Missing Ada Rowan"
    assert "\n" in text, "Line breaks missing in formatted text"
    assert "\n\n" in text, "Paragraph breaks missing in formatted text"

    # Test X-Ray parsing
    xray_json_path = os.path.join(HERE, "fixture.sdr", "xray.json")
    assert os.path.exists(xray_json_path), "xray.json missing"
    with open(xray_json_path, "r") as f:
        xray_content = f.read()
    assert "Kaelen Vane" in xray_content, "Missing Kaelen Vane in X-Ray data"

    print("All python reference & X-Ray tests passed!")

if __name__ == "__main__":
    main()
