#!/usr/bin/env python3
"""Derapify a binarised Arma 3 config (config.bin / any "\\0raP" file).

Companion to pboextract.py: extract a PBO's .bin files, then read the real
config values out of them. This is how you check a vanilla class's parent,
simulation, editorPreview or slingLoadCargoMemoryPoints against the shipped
game files instead of guessing.

Usage:
    python3 Tools/pboextract/derapify.py <config.bin> [filter]

Prints one "path | name = value" line per config entry, plus a synthetic
">>parent" entry per class. `filter` is an optional case-insensitive substring
applied to the whole line.

Example - what is Land_PowerGenerator_F derived from?
    python3 Tools/pboextract/pboextract.py \
        "<arma>/Addons/structures_f_ind.pbo" out --exts bin
    python3 Tools/pboextract/derapify.py out/WindPowerPlant/config.bin PowerGenerator
"""

import struct
import sys


class Reader:
    def __init__(self, data):
        self.d = data
        self.i = 0

    def u8(self):
        v = self.d[self.i]
        self.i += 1
        return v

    def u32(self):
        v = struct.unpack_from("<I", self.d, self.i)[0]
        self.i += 4
        return v

    def i32(self):
        v = struct.unpack_from("<i", self.d, self.i)[0]
        self.i += 4
        return v

    def f32(self):
        v = struct.unpack_from("<f", self.d, self.i)[0]
        self.i += 4
        return v

    def cstr(self):
        j = self.d.index(b"\0", self.i)
        v = self.d[self.i:j].decode("utf-8", "replace")
        self.i = j + 1
        return v

    def compressed(self):
        """7-bit-per-byte little-endian length."""
        value = 0
        shift = 0
        while True:
            b = self.u8()
            value |= (b & 0x7F) << shift
            shift += 7
            if b < 0x80:
                return value


def read_value(r, vtype):
    if vtype == 0:
        return r.cstr()
    if vtype == 1:
        return r.f32()
    if vtype == 2:
        return r.i32()
    if vtype == 3:
        return [read_value(r, r.u8()) for _ in range(r.compressed())]
    if vtype == 4:                       # expression, stored as a string
        return r.cstr()
    raise ValueError("unknown value type %d at offset %d" % (vtype, r.i))


def read_class_body(r, path, out):
    parent = r.cstr()
    subclasses = []
    for _ in range(r.compressed()):
        entry = r.u8()
        if entry == 0:                   # nested class, body stored at an offset
            subclasses.append((r.cstr(), r.u32()))
        elif entry == 1:                 # scalar token
            vtype = r.u8()
            name = r.cstr()
            out.append((path, name, read_value(r, vtype)))
        elif entry == 2:                 # array token
            name = r.cstr()
            out.append((path, name, [read_value(r, r.u8()) for _ in range(r.compressed())]))
        elif entry in (3, 4):            # extern / delete class declaration
            r.cstr()
        elif entry == 5:                 # array token with flags (+= inheritance)
            r.u32()
            name = r.cstr()
            out.append((path, name, [read_value(r, r.u8()) for _ in range(r.compressed())]))
        else:
            raise ValueError("unknown entry type %d at offset %d" % (entry, r.i))
    out.append((path, ">>parent", parent))
    for name, offset in subclasses:
        r.i = offset
        read_class_body(r, path + "/" + name, out)


def parse(data):
    if data[:4] != b"\0raP":
        raise ValueError("not a rapified config (missing \\0raP signature)")
    r = Reader(data)
    r.i = 4
    r.u32()                              # version
    r.u32()                              # always 8
    r.u32()                              # enum offset
    out = []
    read_class_body(r, "", out)
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    needle = argv[2].lower() if len(argv) > 2 else None
    with open(argv[1], "rb") as fh:
        for path, name, value in parse(fh.read()):
            line = "%s | %s = %s" % (path, name, value)
            if needle is None or needle in line.lower():
                print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
