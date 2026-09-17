#!/usr/bin/env python3
"""dsstore_iloc.py - print the Iloc (icon centre) records of a .DS_Store file.

Experiment E5 in docs/FEASIBILITY.md: could Finder's stored desktop icon
positions serve as a layout source? Run it against a COPY of the Desktop's file:

    cp ~/Desktop/.DS_Store "$TMPDIR/Desktop.DS_Store"
    python3 dsstore_iloc.py "$TMPDIR/Desktop.DS_Store"

The file is opened read-only and the script refuses paths inside ~/Desktop, so
it can never write there. Apple does not document the format; this follows the
reverse-engineered description in Mac::Finder::DSStore (DSStoreFormat.pod) and
the ds_store Python package. All integers are big-endian.

  header  : uint32 1, "Bud1", uint32 root offset, uint32 root size,
            uint32 root offset again, 16 unknown bytes. Block offsets are
            relative to byte 4 of the file.
  root    : block table (uint32 count, uint32 unknown, addresses padded to a
            multiple of 256 entries; address = offset | log2(size)),
            table of contents (uint32 count, then {uint8 len, name, uint32 block}),
            32 free lists (uint32 count, count offsets each).
  DSDB    : uint32 root node, uint32 levels, uint32 records, uint32 nodes,
            uint32 page size.
  node    : uint32 P, uint32 count. P == 0: a leaf with count records.
            P != 0: count pairs of (uint32 child block, record), then child P.
  record  : uint32 name length (UTF-16 units), UTF-16BE name, 4-char structure
            id (e.g. Iloc), 4-char type, value.
  value   : long/shor 4 bytes; bool 1 byte; blob uint32 length + bytes;
            type 4 chars; ustr uint32 length + UTF-16BE; comp/dutc 8 bytes.
  Iloc    : 16-byte blob: uint32 x, uint32 y of the icon centre, 8 trailing
            bytes (documented as 6 x 0xFF then 2 x 0x00; printed as hex here).
"""

import argparse
import collections
import os
import struct
import sys


class Reader:
    """Sequential big-endian reader over one block of the file."""

    def __init__(self, data, start, size):
        self.data = data
        self.pos = start
        self.end = start + size

    def read(self, fmt):
        n = struct.calcsize(fmt)
        if self.pos + n > self.end:
            raise ValueError("read past the end of a block at offset %d" % self.pos)
        out = struct.unpack_from(fmt, self.data, self.pos)
        self.pos += n
        return out

    def bytes(self, n):
        if self.pos + n > self.end:
            raise ValueError("read past the end of a block at offset %d" % self.pos)
        out = self.data[self.pos:self.pos + n]
        self.pos += n
        return out


def read_record(r):
    (nlen,) = r.read(">I")
    name = r.bytes(2 * nlen).decode("utf-16-be")
    sid, typ = r.read(">4s4s")
    if typ in (b"long", b"shor"):
        (val,) = r.read(">I")
    elif typ == b"bool":
        (val,) = r.read(">?")
    elif typ == b"blob":
        (vlen,) = r.read(">I")
        val = r.bytes(vlen)
    elif typ == b"type":
        (val,) = r.read(">4s")
    elif typ == b"ustr":
        (vlen,) = r.read(">I")
        val = r.bytes(2 * vlen).decode("utf-16-be")
    elif typ in (b"comp", b"dutc"):
        (val,) = r.read(">Q")
    else:
        raise ValueError("unknown record type %r (structure %r)" % (typ, sid))
    return name, sid.decode("ascii", "replace"), typ.decode("ascii", "replace"), val


def parse(data):
    magic, bud, root_off, root_size, root_off2 = struct.unpack_from(">I4sIII", data, 0)
    if magic != 1 or bud != b"Bud1":
        raise ValueError("not a .DS_Store file (missing Bud1 header)")
    if root_off != root_off2:
        raise ValueError("the two copies of the root block offset differ")

    root = Reader(data, root_off + 4, root_size)
    count, _unknown = root.read(">II")
    padded = (count + 255) & ~255
    addrs = list(root.read(">%dI" % padded))[:count]
    (toc_count,) = root.read(">I")
    toc = {}
    for _ in range(toc_count):
        (nlen,) = root.read(">B")
        name = root.bytes(nlen)
        (toc[name],) = root.read(">I")
    # The 32 free lists follow; they are not needed to read records.

    def block(num):
        addr = addrs[num]
        return Reader(data, (addr & ~0x1F) + 4, 1 << (addr & 0x1F))

    if b"DSDB" not in toc:
        raise ValueError("table of contents has no DSDB entry: %r" % sorted(toc))
    dsdb = block(toc[b"DSDB"])
    root_node, levels, nrecords, nnodes, page_size = dsdb.read(">IIIII")

    def walk(num):
        r = block(num)
        p, n = r.read(">II")
        if p == 0:
            for _ in range(n):
                yield read_record(r)
        else:
            for _ in range(n):
                (child,) = r.read(">I")
                yield from walk(child)
                yield read_record(r)
            yield from walk(p)

    info = {
        "blocks": count,
        "toc": {k.decode("ascii", "replace"): v for k, v in toc.items()},
        "root_node": root_node,
        "levels": levels,
        "records": nrecords,
        "nodes": nnodes,
        "page_size": page_size,
    }
    return info, list(walk(root_node))


def main():
    ap = argparse.ArgumentParser(description="Print the Iloc records of a copied .DS_Store file.")
    ap.add_argument("path", help="path to a COPY of the .DS_Store file (not inside ~/Desktop)")
    ap.add_argument("--no-names", action="store_true", help="print positions only, without item names")
    ap.add_argument("--types", action="store_true", help="also print a count of every structure/type pair")
    args = ap.parse_args()

    path = os.path.realpath(args.path)
    desktop = os.path.realpath(os.path.expanduser("~/Desktop"))
    if path == desktop or path.startswith(desktop + os.sep):
        sys.exit("refusing to open a file inside ~/Desktop; copy it elsewhere first")

    with open(path, "rb") as f:
        data = f.read()
    try:
        info, records = parse(data)
    except (ValueError, struct.error, IndexError, UnicodeDecodeError) as e:
        sys.exit("parse error: %s" % e)

    print("file: %s (%d bytes)" % (path, len(data)))
    print("allocator: %d blocks; toc: %s" % (info["blocks"], info["toc"]))
    print("DSDB: root node %d, levels %d, records %d, nodes %d, page size %d"
          % (info["root_node"], info["levels"], info["records"], info["nodes"], info["page_size"]))
    if len(records) != info["records"]:
        print("warning: DSDB says %d records but %d were read" % (info["records"], len(records)))

    iloc = [(name, val) for name, sid, typ, val in records if sid == "Iloc" and typ == "blob"]
    names = {name for name, _, _, _ in records}
    print("records read: %d (%d distinct item names); Iloc records: %d" % (len(records), len(names), len(iloc)))

    if args.types:
        counts = collections.Counter((sid, typ) for _, sid, typ, _ in records)
        print("structure/type counts:")
        for (sid, typ), n in sorted(counts.items()):
            print("  %s %s  %d" % (sid, typ, n))

    print()
    print("     x      y  trailing          %s" % ("" if args.no_names else "name"))
    for name, blob in iloc:
        if len(blob) < 8:
            print("  (short Iloc blob, %d bytes)  %s" % (len(blob), "" if args.no_names else name))
            continue
        x, y = struct.unpack_from(">II", blob, 0)
        trailing = blob[8:].hex()
        print("%6d %6d  %-16s  %s" % (x, y, trailing, "" if args.no_names else name))


if __name__ == "__main__":
    main()
