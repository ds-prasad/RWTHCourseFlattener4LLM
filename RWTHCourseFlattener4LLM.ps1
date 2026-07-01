<#
    RWTHCourseFlattener4LLM.ps1
    ---------------------------
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

    WORKFLOW:
        1. Create a course folder (any name)
        2. Drop the downloaded course .zip inside it
        3. Drop this script inside it and run it

    WHAT IT DOES:
        (A) Extracts every .zip into a private temp folder   -> extraction summary
        (B) Copies every file into ONE flat folder, renamed with its full
            folder-path as context                            -> mapping summary
        (C) Deletes the temp extracted files (cleanup)

    You are prompted for a short COURSE NAME (max 7 letters) - that becomes the
    filename prefix and the output folder name. Nothing else is hardcoded and
    the original .zip is never touched.

    RESULT - the folder ends containing only:
        - this script
        - the original .zip
        - <Course>_Flat\   (all files, flat, + <Course>_Files_Mapping.csv inside it)

        (course = DLSD)  01_Lecture\1_Lecture 1 Introduction...\slides.pdf
            -> DLSD_01_Lecture_1_Lecture-1-Introduction_slides.pdf

    Run it:
        powershell -ExecutionPolicy Bypass -File ".\RWTHCourseFlattener4LLM.ps1"

    Options:
        -Course      Provide the prefix up front instead of being prompted
        -NoExtract   Skip extraction; flatten subfolders already present (no cleanup)
        -SkipZip     Do not copy nested .zip files into the flat folder
        -DestName    Override the output folder name (default: <Course>_Flat)
#>

param(
    [string]$Course,          # course prefix; if omitted you'll be prompted (max 7 letters)
    [switch]$NoExtract,
    [switch]$SkipZip,
    [string]$DestName
)

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Clean([string]$s) {
    # Transliterate German + common accented letters instead of deleting them, so
    # names like Loesung / Uebung / Aufgabe_Fuenf survive (o-umlaut, u-umlaut, ...).
    # Chars are referenced by Unicode code point so this script stays pure-ASCII
    # and behaves identically no matter how the .ps1 file is saved/encoded.
    $from = 0x00E4,0x00F6,0x00FC,0x00C4,0x00D6,0x00DC,0x00DF,
            0x00E1,0x00E0,0x00E2,0x00E9,0x00E8,0x00EA,0x00ED,0x00EC,
            0x00F3,0x00F2,0x00F4,0x00FA,0x00F9,0x00FB,0x00F1,0x00E7
    $to   = 'ae','oe','ue','Ae','Oe','Ue','ss',
            'a','a','a','e','e','e','i','i',
            'o','o','o','u','u','u','n','c'
    for ($i = 0; $i -lt $from.Count; $i++) {
        $s = $s.Replace([string][char]$from[$i], $to[$i])
    }

    # then keep only safe characters: letters, digits, space, hyphen, underscore.
    # everything else (commas, brackets, &, illegal Windows chars, etc.) is dropped.
    $s = $s -replace '[^A-Za-z0-9 _-]', ''
    $s = ($s -replace '\s+', ' ').Trim()
    $s = $s -replace ' ', '-'                 # spaces -> hyphens (readable + short)
    return $s
}

# Shorten a name by keeping the first half of every word (run of letters/digits),
# leaving separators (- and _) intact. Used only when a name gets too long.
function HalveWords([string]$s) {
    return [regex]::Replace($s, '[A-Za-z0-9]+', {
        param($m)
        $w = $m.Value
        if ($w.Length -gt 1) { $w.Substring(0, [math]::Ceiling($w.Length / 2)) } else { $w }
    })
}

# Ask for the course name (used as the filename prefix). Must be 1-7 letters.
while ($true) {
    if (-not $Course) { $Course = Read-Host "Enter course name (max 7 letters, e.g. DLSD)" }
    $Course = Clean $Course
    if ($Course.Length -ge 1 -and $Course.Length -le 7) { break }
    Write-Host "  '$Course' is invalid - must be 1 to 7 letters. Try again." -ForegroundColor Red
    $Course = $null
}

$Prefix = $Course
if (-not $DestName) { $DestName = "${Prefix}_Flat" }
$Dest    = Join-Path $Root $DestName
$Staging = Join-Path $Root ".__extract_tmp"   # private temp workspace (deleted at end)

# Windows caps the FULL path at ~260 chars, not just the filename. Budget the
# filename length against the actual output-folder path (plus '\' and a possible
# collision suffix), and also cap at 200 for readability.
$MaxNameLen = [math]::Min(200, 259 - $Dest.Length - 1 - 4)
if ($MaxNameLen -lt 40) { $MaxNameLen = 40 }  # extreme-depth floor; _mapping.csv keeps the full path

# =====================================================================
#  STEP A - EXTRACTION (into private temp folder)
# =====================================================================
$usedStaging = $false
if (-not $NoExtract) {
    $zips = Get-ChildItem -LiteralPath $Root -File -Filter *.zip
    if ($zips.Count -gt 1) {
        Write-Host "ERROR: $($zips.Count) .zip files found in this folder:" -ForegroundColor Red
        $zips | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Red }
        Write-Host "Please keep only ONE course .zip in this folder and run again." -ForegroundColor Red
        exit 1
    }
    if ($zips.Count -eq 0) {
        Write-Host "No .zip found - nothing to extract; flattening existing subfolders." -ForegroundColor DarkYellow
    } else {
        if (Test-Path -LiteralPath $Staging) { Remove-Item -LiteralPath $Staging -Recurse -Force }
        New-Item -ItemType Directory -Path $Staging | Out-Null
        $usedStaging = $true

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        Write-Host "STEP A - Extracting $($zips.Count) archive(s):" -ForegroundColor Cyan
        foreach ($zip in $zips) {
            $fileCount = 0
            try {
                $za = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
                $fileCount = ($za.Entries | Where-Object { $_.Name -ne '' }).Count
                $za.Dispose()
            } catch { }
            Expand-Archive -LiteralPath $zip.FullName -DestinationPath $Staging -Force
            Write-Host ("  {0,-45} {1,4} files" -f $zip.Name, $fileCount)
        }
        Write-Host ""
    }
}

# Where to read the material from:
#   - staging (freshly extracted), or
#   - the current folder's own subfolders (already-unpacked / -NoExtract case)
$relBase = if ($usedStaging) { $Staging } else { $Root }

# =====================================================================
#  STEP B - FLATTEN
# =====================================================================
if (-not (Test-Path -LiteralPath $Dest)) { New-Item -ItemType Directory -Path $Dest | Out-Null }

if ($usedStaging) {
    $sourceFiles = Get-ChildItem -LiteralPath $Staging -Recurse -File
} else {
    # only descend into subfolders (skip loose root files like the zip/script/output)
    $sourceFiles = Get-ChildItem -LiteralPath $Root -Directory |
        Where-Object { $_.FullName -ne $Dest -and $_.FullName -ne $Staging } |
        ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Recurse -File }
}

$copied = 0
$skipped = 0
$log = @()

foreach ($file in $sourceFiles) {
    if ($SkipZip -and $file.Extension -ieq '.zip') { $skipped++; continue }

    $rel   = $file.FullName.Substring($relBase.Length).TrimStart('\')
    $parts = $rel.Split('\')
    $topFolder = if ($parts.Length -gt 1) { $parts[0] } else { '(root)' }
    $folders   = if ($parts.Length -gt 1) { $parts[0..($parts.Length - 2)] } else { @() }
    $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $ext       = $file.Extension

    $pieces  = @($Prefix) + ($folders | ForEach-Object { Clean $_ }) + (Clean $baseName)
    $base    = ($pieces -join '_')

    # keep the whole path within Windows' limit: halve every word if too long,
    # then hard-truncate only as a last resort
    if (($base.Length + $ext.Length) -gt $MaxNameLen) { $base = HalveWords $base }
    if (($base.Length + $ext.Length) -gt $MaxNameLen) { $base = $base.Substring(0, [math]::Max(1, $MaxNameLen - $ext.Length)) }
    $newName = $base + $ext

    $target = Join-Path $Dest $newName
    $n = 1
    while (Test-Path -LiteralPath $target) {                  # collision safety
        $newName = $base + "_$n" + $ext
        $target  = Join-Path $Dest $newName
        $n++
    }

    Copy-Item -LiteralPath $file.FullName -Destination $target
    $copied++
    $log += [PSCustomObject]@{ TopFolder = $topFolder; From = $rel; To = $newName }
}

$MappingName = "${Prefix}_Files_Mapping.csv"
$log | Select-Object From, To | Export-Csv -LiteralPath (Join-Path $Dest $MappingName) -NoTypeInformation -Encoding UTF8

# =====================================================================
#  STEP C - CLEANUP (only the temp files WE extracted this run)
# =====================================================================
if ($usedStaging -and (Test-Path -LiteralPath $Staging)) {
    Remove-Item -LiteralPath $Staging -Recurse -Force
    Write-Host "STEP C - Removed temporary extracted files." -ForegroundColor DarkGray
    Write-Host ""
}

# =====================================================================
#  SUMMARY
# =====================================================================
Write-Host "Done. Course prefix: $Prefix" -ForegroundColor Green
Write-Host ""
Write-Host "Files copied per source folder:" -ForegroundColor Cyan
$log | Group-Object TopFolder | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,-32} {1,4} files" -f $_.Name, $_.Count)
}
Write-Host ("  {0,-32} {1,4} files" -f "TOTAL", $copied) -ForegroundColor White
if ($skipped -gt 0) { Write-Host "  ($skipped .zip file(s) skipped)" -ForegroundColor DarkGray }
Write-Host ""
Write-Host "This folder now contains: this script, the .zip, and '$DestName\'"
Write-Host "Output folder : $Dest"
Write-Host "Full mapping  : $(Join-Path $DestName $MappingName)"
