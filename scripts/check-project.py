#!/usr/bin/env python3
"""Validate release metadata, local documentation links, and shipped translations."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import sys
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent


def headings(text):
    anchors = set()
    counts = {}
    for title in re.findall(r"^#{1,6}\s+(.+?)\s*#*\s*$", text, re.MULTILINE):
        slug = re.sub(r"[^\w\- ]", "", title.lower()).replace(" ", "-")
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        anchors.add(f"{slug}-{count}" if count else slug)
    return anchors


def check(tag=None):
    errors = []
    with (ROOT / "OnTop/Info.plist").open("rb") as file:
        version = plistlib.load(file)["CFBundleShortVersionString"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        errors.append(f"Invalid app version: {version}")
    if tag is not None and tag != f"v{version}":
        errors.append(f"Release tag {tag!r} must match Info.plist: v{version}")
    if not re.search(rf"^## {re.escape(version)}(?:\s|$)", (ROOT / "CHANGELOG.md").read_text(), re.MULTILINE):
        errors.append(f"CHANGELOG.md needs an entry for {version}")
    notes = ROOT / f"docs/releases/v{version}.md"
    if not notes.is_file():
        errors.append(f"Missing release notes: {notes.relative_to(ROOT)}")
    elif not re.search(r"[\u4e00-\u9fff]", notes.read_text()):
        errors.append("Release notes need a Chinese section as well as English")

    markdown = [ROOT / name for name in ("README.md", "README.zh-CN.md", "CONTRIBUTING.md", "SECURITY.md", "CHANGELOG.md")]
    markdown += list((ROOT / "docs").rglob("*.md"))
    markdown += list((ROOT / ".github").glob("*.md"))
    links_checked = 0
    for file in markdown:
        if not file.is_file():
            errors.append(f"Missing document: {file.relative_to(ROOT)}")
            continue
        text = re.sub(r"```.*?```", "", file.read_text(), flags=re.DOTALL)
        links = re.findall(r"\[[^\]\n]*\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)", text)
        links += re.findall(r"(?:href|src)=[\"']([^\"']+)[\"']", text)
        for link in links:
            parsed = urlsplit(link)
            if parsed.scheme or parsed.netloc:
                continue
            target = (file.parent / unquote(parsed.path)).resolve() if parsed.path else file
            if not target.is_relative_to(ROOT):
                errors.append(f"{file.relative_to(ROOT)}: link leaves repository: {link}")
            elif not target.exists():
                errors.append(f"{file.relative_to(ROOT)}: broken local link: {link}")
            elif parsed.fragment and target.suffix == ".md" and unquote(parsed.fragment) not in headings(target.read_text()):
                errors.append(f"{file.relative_to(ROOT)}: missing heading: {link}")
            links_checked += 1

    tables = {}
    pattern = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', re.MULTILINE)
    for locale in ("en", "zh-Hans"):
        table = {}
        file = ROOT / f"OnTop/Resources/{locale}.lproj/Localizable.strings"
        for match in pattern.finditer(file.read_text()):
            key, value = [json.loads('"' + group + '"') for group in match.groups()]
            if key in table:
                errors.append(f"Duplicate {locale} translation: {key}")
            if not value.strip():
                errors.append(f"Empty {locale} translation: {key}")
            table[key] = value
        tables[locale] = table
    if not tables["en"] or tables["en"].keys() != tables["zh-Hans"].keys():
        errors.append("English and Chinese translation keys differ")
    for file in (ROOT / "OnTop").glob("*.swift"):
        for key in re.findall(r'NSLocalizedString\("((?:[^"\\]|\\.)*)"', file.read_text()):
            key = json.loads('"' + key + '"')
            if key and key not in tables["en"]:
                errors.append(f"{file.name}: missing translation: {key}")
    for file in (ROOT / "scripts").glob("*.sh"):
        if not os.access(file, os.X_OK):
            errors.append(f"Script must be executable: {file.relative_to(ROOT)}")
    for file in (ROOT / ".github/workflows").glob("*.yml"):
        for action, reference in re.findall(r"uses:\s+(actions/[\w-]+)@([^\s]+)", file.read_text()):
            if not re.fullmatch(r"[0-9a-f]{40}", reference):
                errors.append(f"{file.name}: pin {action} to a full commit SHA")
    for file in (ROOT / "docs/assets").glob("*.svg"):
        ET.parse(file)
    if errors:
        print("Project checks failed:\n" + "\n".join(f"- {error}" for error in errors), file=sys.stderr)
        return 1
    print(f"PASS: project v{version}, {links_checked} local links, bilingual translations, release metadata, and action pins")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-tag")
    sys.exit(check(parser.parse_args().release_tag))
