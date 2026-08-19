#!/usr/bin/env python3
"""
pboextract.py — Reusable Arma 3 PBO extractor
==============================================

Can be used as a **library** or run directly from the command line.

Library usage
-------------
    from Tools.pboextract.pboextract import PboReader

    reader = PboReader("path/to/file.pbo")
    reader.parse()

    # Inspect metadata
    print(reader.properties)          # dict of sreV key/value pairs, or {}
    for entry in reader.entries:
        print(entry.name, entry.data_size)

    # Extract everything
    reader.extract("output/dir")

    # Extract only SQF and HPP
    reader.extract("output/dir", exts={"sqf", "hpp"})

    # Read a single file's bytes without writing to disk
    data = reader.read_entry(reader.entries[0])

Command-line usage
------------------
    py Tools/pboextract/pboextract.py <source.pbo> [dest_dir] [options]

    Options:
      --exts sqf,hpp,cpp   Comma-separated list of extensions to extract.
                           Omit to extract every file.
      --list               Print the file listing and exit; do not extract.
      --verbose / -v       Print each file as it is extracted.
      --quiet / -q         Suppress all output except errors.

PBO format notes
----------------
A PBO file has three sections:

1. **Header block** — zero or more entries, each:
       name\x00  (variable length, null-terminated)
       packing_method  (uint32 LE)
       original_size   (uint32 LE)
       reserved        (uint32 LE)
       timestamp       (uint32 LE)
       data_size       (uint32 LE)
   The header ends with a *boundary entry*: empty name + 20 zero bytes.

2. **Properties block** (sreV — optional) — present when the *first* entry has
   an empty name AND packing_method == 0x56657273 ("sreV" reversed).
   After the boundary entry come null-terminated key=value string pairs until
   an empty key terminates the block.  This is processed transparently.

3. **Data section** — the raw bytes for every header entry, in the same order,
   each entry.data_size bytes long.

Packing method 0x43707273 ("Cprs") indicates zlib compression, but Arma 3
addons typically use 0x00000000 (uncompressed).  Compressed extraction is not
yet implemented; the bytes are returned as-is.
"""

from __future__ import annotations

import argparse
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, Iterator, List, Optional, Set


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

PACKING_UNCOMPRESSED = 0x00000000
PACKING_COMPRESSED   = 0x43707273  # "Cprs"
PACKING_VERSION      = 0x56657273  # "sreV" — sreV property sentinel

@dataclass
class PboEntry:
    """Metadata for one file inside a PBO archive."""
    name: str                    # path inside the PBO, using backslash separators
    packing_method: int          # see PACKING_* constants above
    original_size: int           # uncompressed size (0 when uncompressed)
    reserved: int
    timestamp: int
    data_size: int               # bytes occupied in the data section
    _data_offset: int = field(repr=False, default=0)  # byte offset into PBO file

    @property
    def ext(self) -> str:
        """Lower-case extension without the leading dot, e.g. ``'sqf'``."""
        stem, _, tail = self.name.lower().rpartition(".")
        return tail if stem else ""

    @property
    def is_compressed(self) -> bool:
        return self.packing_method == PACKING_COMPRESSED


# ---------------------------------------------------------------------------
# Reader
# ---------------------------------------------------------------------------

class PboReader:
    """
    Parse and extract an Arma 3 PBO file.

    Parameters
    ----------
    path:
        Path to the ``.pbo`` file.

    Raises
    ------
    FileNotFoundError
        If *path* does not exist.
    ValueError
        If the file cannot be parsed as a valid PBO.
    """

    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)
        if not self.path.exists():
            raise FileNotFoundError(f"PBO not found: {self.path}")

        self._data: bytes = self.path.read_bytes()
        self._pos: int = 0

        self.properties: Dict[str, str] = {}
        """Key/value metadata from the sreV block, or an empty dict."""

        self.entries: List[PboEntry] = []
        """File entries in header order.  Populated after :meth:`parse`."""

        self._parsed: bool = False

    # ------------------------------------------------------------------
    # Low-level byte helpers
    # ------------------------------------------------------------------

    def _read_str(self) -> str:
        end = self._data.index(b"\x00", self._pos)
        s = self._data[self._pos:end].decode("utf-8", errors="replace")
        self._pos = end + 1
        return s

    def _read_u32(self) -> int:
        value = struct.unpack_from("<I", self._data, self._pos)[0]
        self._pos += 4
        return value

    def _skip(self, n: int) -> None:
        self._pos += n

    # ------------------------------------------------------------------
    # Header parsing
    # ------------------------------------------------------------------

    def _parse_srev_properties(self) -> None:
        """Read key=value pairs until an empty key is encountered."""
        while True:
            key = self._read_str()
            if not key:
                break
            val = self._read_str()
            self.properties[key] = val

    def parse(self) -> "PboReader":
        """
        Parse the PBO header.

        Must be called before :meth:`entries`, :meth:`extract`, or
        :meth:`read_entry`.  Safe to call multiple times (no-op after the
        first call).

        Returns *self* for chaining: ``reader = PboReader(p).parse()``.
        """
        if self._parsed:
            return self

        self._pos = 0
        srev_seen = False

        # ---- header entries ------------------------------------------------
        # A PBO may optionally start with a sreV block:
        #   empty-name entry where packing_method == PACKING_VERSION
        #   followed immediately by null-terminated key=value property pairs.
        # After the sreV block (or immediately, if none), the real file entries
        # follow and are terminated by another empty-name boundary entry.
        while True:
            name = self._read_str()

            # Read the 5 uint32 fields for this entry slot
            packing   = self._read_u32()
            orig_size = self._read_u32()
            reserved  = self._read_u32()
            timestamp = self._read_u32()
            data_size = self._read_u32()

            if not name:
                if not srev_seen and packing == PACKING_VERSION:
                    # This is the sreV metadata entry — read the properties
                    # that follow it, then continue to the real file entries.
                    self._parse_srev_properties()
                    srev_seen = True
                    continue   # ← keep looping; real entries come next
                else:
                    # True header-end boundary — stop reading entries.
                    break

            self.entries.append(PboEntry(
                name=name,
                packing_method=packing,
                original_size=orig_size,
                reserved=reserved,
                timestamp=timestamp,
                data_size=data_size,
            ))

        # ---- record data offsets ------------------------------------------
        offset = self._pos
        for entry in self.entries:
            entry._data_offset = offset
            offset += entry.data_size

        self._parsed = True
        return self

    # ------------------------------------------------------------------
    # Data access
    # ------------------------------------------------------------------

    def read_entry(self, entry: PboEntry) -> bytes:
        """
        Return the raw bytes for *entry*.

        If the entry is stored uncompressed (the common case for Arma 3
        addons) the bytes are the file's exact content.  Compressed entries
        are returned as-is; decompression is not yet implemented.
        """
        self._ensure_parsed()
        return self._data[entry._data_offset : entry._data_offset + entry.data_size]

    # ------------------------------------------------------------------
    # Extraction
    # ------------------------------------------------------------------

    def _matches_filter(self, entry: PboEntry, exts: Optional[Set[str]]) -> bool:
        return exts is None or entry.ext in exts

    def extract(
        self,
        dest: str | Path,
        *,
        exts: Optional[Iterable[str]] = None,
        verbose: bool = False,
    ) -> int:
        """
        Extract files from the PBO to *dest*.

        Parameters
        ----------
        dest:
            Output directory.  Created (with parents) if it does not exist.
        exts:
            Iterable of lower-case extensions **without** a leading dot, e.g.
            ``["sqf", "hpp", "cpp"]``.  Pass ``None`` (the default) to extract
            every file.
        verbose:
            If ``True``, print each extracted path to stdout.

        Returns
        -------
        int
            Number of files written.
        """
        self._ensure_parsed()
        dest = Path(dest)
        dest.mkdir(parents=True, exist_ok=True)
        ext_filter: Optional[Set[str]] = (
            {e.lstrip(".").lower() for e in exts} if exts is not None else None
        )

        count = 0
        for entry in self.entries:
            if not self._matches_filter(entry, ext_filter):
                continue
            content = self.read_entry(entry)
            out = dest / entry.name.replace("\\", "/")
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(content)
            count += 1
            if verbose:
                print(f"  {entry.name}  ({entry.data_size} B)")

        return count

    def iter_entries(
        self,
        exts: Optional[Iterable[str]] = None,
    ) -> Iterator[tuple[PboEntry, bytes]]:
        """
        Yield ``(entry, data)`` pairs, optionally filtered by extension.

        Parameters
        ----------
        exts:
            Same semantics as :meth:`extract`.
        """
        self._ensure_parsed()
        ext_filter: Optional[Set[str]] = (
            {e.lstrip(".").lower() for e in exts} if exts is not None else None
        )
        for entry in self.entries:
            if self._matches_filter(entry, ext_filter):
                yield entry, self.read_entry(entry)

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _ensure_parsed(self) -> None:
        if not self._parsed:
            self.parse()

    def __repr__(self) -> str:
        status = f"{len(self.entries)} entries" if self._parsed else "unparsed"
        return f"PboReader({self.path.name!r}, {status})"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="pboextract",
        description="Extract files from an Arma 3 PBO archive.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("source", help="Path to the .pbo file.")
    p.add_argument(
        "dest",
        nargs="?",
        default=None,
        help="Output directory.  Defaults to <source_stem>_extracted/ next to the PBO.",
    )
    p.add_argument(
        "--exts",
        default=None,
        metavar="EXT,…",
        help="Comma-separated extensions to extract (e.g. sqf,hpp,cpp).  "
             "Omit to extract all files.",
    )
    p.add_argument(
        "--list",
        action="store_true",
        help="List PBO contents and exit without extracting.",
    )
    p.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Print each file as it is extracted.",
    )
    p.add_argument(
        "--quiet", "-q",
        action="store_true",
        help="Suppress all output except errors.",
    )
    return p


def main(argv: Optional[List[str]] = None) -> int:
    """Entry point for CLI use.  Returns an exit code."""
    parser = _build_parser()
    args = parser.parse_args(argv)

    verbose = args.verbose and not args.quiet
    quiet   = args.quiet

    try:
        reader = PboReader(args.source).parse()
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except ValueError as exc:
        print(f"error: could not parse PBO — {exc}", file=sys.stderr)
        return 1

    # --list
    if args.list:
        if not quiet:
            if reader.properties:
                print("Properties:")
                for k, v in reader.properties.items():
                    print(f"  {k} = {v}")
            print(f"{'Name':<60} {'Size':>10}  {'Method':>10}")
            print("-" * 84)
            for e in reader.entries:
                method_str = (
                    "compressed" if e.is_compressed
                    else "stored" if e.packing_method == PACKING_UNCOMPRESSED
                    else f"0x{e.packing_method:08x}"
                )
                print(f"  {e.name:<58} {e.data_size:>10}  {method_str:>10}")
            print(f"\n{len(reader.entries)} entries total.")
        return 0

    # --extract
    dest = Path(args.dest) if args.dest else Path(args.source).parent / (Path(args.source).stem + "_extracted")
    exts = [e.strip() for e in args.exts.split(",")] if args.exts else None

    count = reader.extract(dest, exts=exts, verbose=verbose)

    if not quiet:
        print(f"Extracted {count} file(s) to {dest}")

    return 0


if __name__ == "__main__":
    sys.exit(main())


