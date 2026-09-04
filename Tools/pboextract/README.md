# pboextract — Arma 3 PBO extractor

A reusable Python tool for inspecting and extracting Arma 3 PBO archives.
Handles both plain PBOs and PBOs with a `sreV` properties header.

Requires only the Python standard library (no third-party packages).

---

## Quick start

```powershell
# List the contents of a PBO
py Tools/pboextract/pboextract.py path/to/file.pbo --list

# Extract SQF / HPP / CPP files to a directory
py Tools/pboextract/pboextract.py path/to/file.pbo output_dir --exts sqf,hpp,cpp --verbose

# Extract everything (no --exts filter)
py Tools/pboextract/pboextract.py path/to/file.pbo output_dir

# Default output path when dest is omitted: <file_stem>_extracted/ next to the PBO
py Tools/pboextract/pboextract.py path/to/file.pbo --exts sqf
```

## Command-line reference

```
pboextract <source.pbo> [dest_dir] [options]

  --exts EXT,…    Comma-separated extensions to extract, e.g. sqf,hpp,cpp.
                  Omit to extract every file in the PBO.
  --list          Print the file listing and exit; no files are written.
  --verbose / -v  Print each file as it is extracted.
  --quiet  / -q   Suppress all output except errors.
```

## Library API

```python
from Tools.pboextract.pboextract import PboReader

# Parse once
reader = PboReader("path/to/file.pbo").parse()

# Inspect sreV properties (dict, may be empty)
print(reader.properties)          # e.g. {'prefix': 'BuildAndRessources'}

# Walk entries
for entry in reader.entries:
    print(entry.name, entry.data_size, entry.ext)

# Extract filtered set to disk
reader.extract("output/dir", exts=["sqf", "hpp"], verbose=True)

# Read one file's bytes without writing to disk
data = reader.read_entry(reader.entries[0])

# Iterate (entry, bytes) pairs
for entry, data in reader.iter_entries(exts=["sqf"]):
    process(entry.name, data)
```

## PBO format summary

| Section | Notes |
|---|---|
| **sreV block** (optional) | Empty-name entry with packing `0x56657273`; followed by null-terminated key=value pairs until an empty key. Present in most Arma 3 addon PBOs. |
| **Header entries** | `name\0` + 5 × uint32 LE (packing_method, original_size, reserved, timestamp, data_size). Terminated by an empty-name boundary entry. |
| **Data section** | Concatenated file data in header order, `data_size` bytes each. Packing `0x00000000` = uncompressed (standard for Arma 3 addons). |

See the module docstring in `pboextract.py` for the full format notes.

## Common use-case: inspecting a workshop mod

```powershell
# BAR mod
$pbo = "C:\Program Files (x86)\Steam\steamapps\common\Arma 3\!Workshop\@BuildAndRessources\addons\BuildAndRessources.pbo"
py Tools/pboextract/pboextract.py $pbo build/bar_extracted --exts sqf,hpp,cpp -v
```

## Companion: `derapify.py` — reading binarised configs

`pboextract.py` gets you the files; `derapify.py` reads a binarised
`config.bin` (any `\0raP` file) so you can check a **vanilla** class's real
values instead of guessing at them.

```bash
ARMA="/mnt/c/Program Files (x86)/Steam/steamapps/common/Arma 3"
python3 Tools/pboextract/pboextract.py "$ARMA/Addons/structures_f_ind.pbo" out --exts bin
python3 Tools/pboextract/derapify.py out/WindPowerPlant/config.bin PowerGenerator_F
```

It prints one `path | name = value` line per entry, plus a synthetic
`>>parent` line per class, and takes an optional case-insensitive filter.
That parent chain is usually the answer: it is what tells you whether a class
is a PhysX `ThingX` or a `House_*` static, which decides whether the object can
fall, be slung, or be pushed.

## History

- 2026-08-19: Created, replacing the ad-hoc `build/extract_bar.py` and `build/extract_bar2.py`.
- 2026-09-04: Added `derapify.py`.

