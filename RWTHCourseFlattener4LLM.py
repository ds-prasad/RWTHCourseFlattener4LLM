#!/usr/bin/env python3
"""
RWTHCourseFlattener4LLM.py
--------------------------
Author : Prasad Dinesha Shyamala
         M.Sc. Software Systems Engineering, RWTH Aachen
Date   : July 2026

Copyright 2026 Prasad Dinesha Shyamala
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

One-step tool for prepping any nested course archive into a flat,
context-named file set for LLM-based study & tutoring tools
(Claude Projects, NotebookLM, ChatGPT, and similar).

This is the Python port of RWTHCourseFlattener4LLM.ps1 - identical behaviour.

WORKFLOW:
    1. Create a course folder (any name)
    2. Drop the downloaded course .zip inside it
    3. Drop this script inside it and run it:

        python RWTHCourseFlattener4LLM.py

WHAT IT DOES:
    (A) Extracts the single .zip into a private temp folder  -> extraction summary
    (B) Copies every file into ONE flat folder, renamed with its full
        folder-path as context                               -> mapping summary
    (C) Deletes the temp extracted files (cleanup)

RESULT - the folder ends containing only:
    - this script
    - the original .zip
    - <Course>_Flat/   (all files, flat, + <Course>_Files_Mapping.csv inside it)

Options:
    --course NAME   Provide the prefix up front instead of being prompted
    --no-extract    Skip extraction; flatten subfolders already present (no cleanup)
    --skip-zip      Do not copy nested .zip files into the flat folder
    --dest-name X   Override the output folder name (default: <Course>_Flat)
"""

import argparse
import csv
import os
import re
import shutil
import sys
import zipfile
from pathlib import Path

# --- German + common accented letters -> ASCII (transliterate, don't delete) ---
TRANSLITERATE = {
    "ä": "ae", "ö": "oe", "ü": "ue",
    "Ä": "Ae", "Ö": "Oe", "Ü": "Ue", "ß": "ss",
    "á": "a", "à": "a", "â": "a",
    "é": "e", "è": "e", "ê": "e",
    "í": "i", "ì": "i",
    "ó": "o", "ò": "o", "ô": "o",
    "ú": "u", "ù": "u", "û": "u",
    "ñ": "n", "ç": "c",
}


def clean(s: str) -> str:
    """Transliterate accents, drop unsafe symbols, spaces -> hyphens."""
    for k, v in TRANSLITERATE.items():
        s = s.replace(k, v)
    # keep only letters, digits, space, hyphen, underscore
    s = re.sub(r"[^A-Za-z0-9 _-]", "", s)
    s = re.sub(r"\s+", " ", s).strip()
    s = s.replace(" ", "-")
    return s


def halve_words(s: str) -> str:
    """Keep the first half of every alphanumeric run; separators stay intact."""
    def _half(m):
        w = m.group(0)
        return w[: -(-len(w) // 2)] if len(w) > 1 else w  # ceil division
    return re.sub(r"[A-Za-z0-9]+", _half, s)


def ask_course(course: str) -> str:
    """Prompt for a 1-7 letter course name unless one was passed in."""
    while True:
        if not course:
            course = input("Enter course name (max 7 letters, e.g. DLSD): ")
        course = clean(course)
        if 1 <= len(course) <= 7:
            return course
        print(f"  '{course}' is invalid - must be 1 to 7 letters. Try again.")
        course = ""


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True, description="Flatten a nested course archive for LLM study tools.")
    ap.add_argument("--course", default="", help="course prefix (max 7 letters); prompted if omitted")
    ap.add_argument("--no-extract", action="store_true", help="skip extraction; flatten existing subfolders")
    ap.add_argument("--skip-zip", action="store_true", help="do not copy nested .zip files")
    ap.add_argument("--dest-name", default="", help="override output folder name")
    args = ap.parse_args()

    root = Path(__file__).resolve().parent

    prefix = ask_course(args.course)
    dest_name = args.dest_name or f"{prefix}_Flat"
    dest = root / dest_name
    staging = root / ".__extract_tmp"

    # Windows caps the FULL path at ~260 chars, not just the filename. Budget the
    # filename length against the actual output-folder path (plus separator and a
    # possible collision suffix), and also cap at 200 for readability.
    max_name_len = min(200, 259 - len(str(dest)) - 1 - 4)
    if max_name_len < 40:
        max_name_len = 40  # extreme-depth floor; the mapping CSV keeps the full path

    # =============================================================
    #  STEP A - EXTRACTION (into private temp folder)
    # =============================================================
    used_staging = False
    if not args.no_extract:
        zips = sorted(root.glob("*.zip"))
        if len(zips) > 1:
            print(f"ERROR: {len(zips)} .zip files found in this folder:")
            for z in zips:
                print(f"  - {z.name}")
            print("Please keep only ONE course .zip in this folder and run again.")
            return 1
        if not zips:
            print("No .zip found - nothing to extract; flattening existing subfolders.")
        else:
            if staging.exists():
                shutil.rmtree(staging)
            staging.mkdir()
            used_staging = True
            print(f"STEP A - Extracting {len(zips)} archive(s):")
            for z in zips:
                with zipfile.ZipFile(z) as zf:
                    file_count = sum(1 for n in zf.namelist() if not n.endswith("/"))
                    zf.extractall(staging)
                print(f"  {z.name:<45} {file_count:>4} files")
            print()

    rel_base = staging if used_staging else root

    # =============================================================
    #  STEP B - FLATTEN
    # =============================================================
    dest.mkdir(exist_ok=True)

    if used_staging:
        source_files = [p for p in staging.rglob("*") if p.is_file()]
    else:
        # only descend into subfolders (skip loose root files like the zip/script/output)
        source_files = []
        for d in root.iterdir():
            if d.is_dir() and d != dest and d != staging:
                source_files.extend(p for p in d.rglob("*") if p.is_file())

    copied = 0
    skipped = 0
    log = []  # (top_folder, rel, new_name)

    for f in source_files:
        if args.skip_zip and f.suffix.lower() == ".zip":
            skipped += 1
            continue

        rel = f.relative_to(rel_base)
        parts = rel.parts
        top_folder = parts[0] if len(parts) > 1 else "(root)"
        folders = parts[:-1]
        base_name = f.stem
        ext = f.suffix

        pieces = [prefix] + [clean(x) for x in folders] + [clean(base_name)]
        base = "_".join(pieces)

        # keep the whole path within the limit: halve words, then truncate as a last resort
        if len(base) + len(ext) > max_name_len:
            base = halve_words(base)
        if len(base) + len(ext) > max_name_len:
            base = base[: max(1, max_name_len - len(ext))]
        new_name = base + ext

        target = dest / new_name
        n = 1
        while target.exists():  # collision safety
            new_name = f"{base}_{n}{ext}"
            target = dest / new_name
            n += 1

        shutil.copy2(f, target)
        copied += 1
        log.append((top_folder, str(rel), new_name))

    mapping_name = f"{prefix}_Files_Mapping.csv"
    with open(dest / mapping_name, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["From", "To"])
        for top, frm, to in log:
            w.writerow([frm, to])

    # =============================================================
    #  STEP C - CLEANUP (only the temp files WE extracted this run)
    # =============================================================
    if used_staging and staging.exists():
        shutil.rmtree(staging)
        print("STEP C - Removed temporary extracted files.\n")

    # =============================================================
    #  SUMMARY
    # =============================================================
    print(f"Done. Course prefix: {prefix}\n")
    print("Files copied per source folder:")
    counts = {}
    for top, _, _ in log:
        counts[top] = counts.get(top, 0) + 1
    for top in sorted(counts):
        print(f"  {top:<32} {counts[top]:>4} files")
    print(f"  {'TOTAL':<32} {copied:>4} files")
    if skipped:
        print(f"  ({skipped} .zip file(s) skipped)")
    print()
    print(f"This folder now contains: this script, the .zip, and '{dest_name}/'")
    print(f"Output folder : {dest}")
    print(f"Full mapping  : {os.path.join(dest_name, mapping_name)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
