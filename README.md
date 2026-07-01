# RWTHCourseFlattener4LLM

A small PowerShell utility that turns a downloaded, deeply-nested university
course archive into a **single flat folder of files with context-rich names** —
ready to drop into any **LLM-based study & tutoring tool** (Claude Projects,
NotebookLM, ChatGPT, and similar) that accepts individual files but not folders.

---

## Objective / Problem Statement

University course material (e.g. downloaded from RWTH Moodle) usually comes as a
`.zip` with a **nested folder hierarchy**:

```
Course.zip
└── 01_Lecture
    └── 1_Lecture 1 Introduction, Markov decision process
        ├── RLLBC-SS26-Lecture1.pdf
        └── RLLBC-SS26-Lecture1_preview.pdf
```

Two problems arise when you want to use these files with an LLM tutor
(Claude Projects, NotebookLM, ChatGPT, etc.):

1. **Most knowledge-base uploaders only accept files, not folders.**
   Uploading loses the hierarchy entirely — you end up with a flat pile of files
   named `1.pdf`, `slides.pdf`, `intro.html` … with no idea which lecture or
   exercise they belong to.
2. **Context lives in the folder names**, not the files. Once flattened, that
   context is gone.

This script solves both: it flattens everything into one folder while **baking
the full folder path into each filename**, so the model (and you) always know
exactly what each file is:

```
DLSD_01_Lecture_1_Lecture-1-Introduction-Markov-decision-process_RLLBC-SS26-Lecture1.pdf
```

---

## How to Run

1. Create a folder (any name).
2. Drop the downloaded course **`.zip`** inside it.
   > **Only one `.zip` may be present in the folder.** If the script detects more
   > than one, it stops and asks you to keep just a single course archive.
3. Drop **`RWTHCourseFlattener4LLM.ps1`** inside it.
4. Run it from a terminal in that folder:

   ```powershell
   powershell -ExecutionPolicy Bypass -File ".\RWTHCourseFlattener4LLM.ps1"
   ```

   (or right-click the script → *Run with PowerShell*)

5. When prompted, enter a short **course name** (max 7 letters), e.g. `DLSD`.

When it finishes, the folder contains only:

```
RWTHCourseFlattener4LLM.ps1
YourCourse.zip
DLSD_Flat/
 ├── DLSD_01_Lecture_..._RLLBC-SS26-Lecture1.pdf
 ├── DLSD_...
 └── DLSD_Files_Mapping.csv   # old path -> new filename, for reference
```

Upload the contents of `DLSD_Flat/` to your LLM tutor (Claude Project,
NotebookLM notebook, ChatGPT, …) and start studying.

### Options

| Option        | Effect                                                                 |
|---------------|------------------------------------------------------------------------|
| `-Course`     | Provide the prefix up front instead of being prompted, e.g. `-Course DLSD` |
| `-NoExtract`  | Skip extraction; flatten subfolders that are already unpacked (no cleanup) |
| `-SkipZip`    | Don't copy nested `.zip` files into the flat folder                     |
| `-DestName`   | Override the output folder name (default: `<Course>_Flat`)              |

---

## Existing Features

- **One-step pipeline:** extract → flatten → cleanup, in a single run.
- **Interactive course prefix:** prompts for a short name used on every file.
- **Context-rich names:** the full source folder path is encoded in each filename.
- **Non-destructive:** the original `.zip` is never modified.
- **Safe cleanup:** extraction happens in a private temp folder that is deleted
  afterward — the script only removes files *it* created this run, never folders
  you already had.
- **Mapping file:** `<Course>_Files_Mapping.csv` records every `old path → new filename`.
- **Per-folder summary:** prints how many files came from each source folder.
- **Collision safety:** duplicate target names get a numeric suffix.

---

## Added Guardrails

- **Single-archive check.** Only one `.zip` may be present in the folder. If more
  than one is found, the script stops and asks you to keep just one, so it never
  guesses which archive you meant.
- **German umlauts & accents transliterated (not deleted).** `ä ö ü ß` become
  `ae oe ue ss` (and common accents are folded to their base letter), so
  `Lösung`/`Übung`/`Größe` become `Loesung`/`Uebung`/`Groesse` instead of losing
  characters. The characters are referenced by Unicode code point in the script,
  so it works regardless of how the `.ps1` file is saved/encoded.
- **Special / illegal symbols removed.** Any *remaining* character that isn't a
  letter, digit, space, hyphen, or underscore is stripped (commas, brackets,
  `&`, `!`, and Windows-illegal characters like `\ / : * ? " < > |`). Spaces
  become hyphens. Existing hyphens/underscores in real filenames are preserved.
- **Path-length limit (whole path, not just the name).** Windows caps the *full*
  path at ~260 characters, so the filename budget is computed against the actual
  output-folder path. If a name would blow the budget, it's shortened by keeping
  the **first half of every word** (separators stay intact), e.g.
  `Introduction-Markov-decision` → `Introd-Mar-deci`; a hard truncation is used
  only as a last resort. The full original path is always preserved in
  `<Course>_Files_Mapping.csv`, so nothing is lost.

---

## Known Issues / Limitations

- **Meant to be run ONCE per folder — no duplicate/idempotency checks.** Heads up,
  and don't be extra smart about this: I deliberately did **not** add re-run
  protection. If you run the script a second time into the same folder, the output
  already exists and files get copied again with `_1`, `_2` suffixes — i.e. you'll
  accumulate duplicates. This is designed for a single clean run. If you want to
  redo it, delete the `<Course>_Flat/` folder first, then run again.
- **No recursive decompression.** If the course archive contains *nested* `.zip`
  files (a zip inside the zip), those inner archives are **not** extracted — they
  are copied as-is (or skipped with `-SkipZip`). You'd need to unzip them
  manually and re-run.
- **Windows / PowerShell only.** Uses `Expand-Archive`, so it targets Windows
  PowerShell 5.1+. Only `.zip` archives are supported (not `.rar`/`.7z`).
- **`Read-Host` prompt.** The course-name prompt requires an interactive
  terminal. In non-interactive contexts, pass `-Course` instead.
- **Pre-existing extracted folders aren't cleaned.** By design the cleanup only
  touches what the script extracted this run; if you already had unpacked folders
  next to the zip, remove those manually.

---

## License

Released under the [Apache License 2.0](LICENSE).
