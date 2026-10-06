"""Removes Rojo's reference helper attributes (Rojo_Id / Rojo_Target_*) from a built .rbxlx.

Rojo resolves those attributes into real references (Motor6D.Part0, Model.PrimaryPart, ...)
but leaves the attributes behind. They're harmless, just clutter in the Properties window.

    python3 tools/strip_rojo_attrs.py Place1.rbxlx
"""

import base64
import re
import struct
import sys


def rewrite(blob):
    data = base64.b64decode(blob)
    (count,) = struct.unpack_from("<I", data, 0)
    pos = 4
    kept = []
    for _ in range(count):
        (name_len,) = struct.unpack_from("<I", data, pos)
        name = data[pos + 4 : pos + 4 + name_len].decode("utf-8")
        start = pos
        pos += 4 + name_len
        kind = data[pos]
        pos += 1
        if kind == 0x02:  # string
            (n,) = struct.unpack_from("<I", data, pos)
            pos += 4 + n
        elif kind == 0x03:  # bool
            pos += 1
        elif kind == 0x06:  # double
            pos += 8
        else:
            return blob  # unknown type: leave this blob alone
        if not name.startswith("Rojo_"):
            kept.append(data[start:pos])
    if len(kept) == count:
        return blob
    out = struct.pack("<I", len(kept)) + b"".join(kept)
    return base64.b64encode(out).decode("ascii")


def main(path):
    text = open(path, encoding="utf-8").read()
    removed = 0

    def sub(m):
        nonlocal removed
        new = rewrite(m.group(2))
        if new != m.group(2):
            removed += 1
        if new == "AAAAAA==":  # zero attributes
            return ""
        return m.group(1) + new + m.group(3)

    text = re.sub(r'(<BinaryString name="AttributesSerialize">)([^<]*)(</BinaryString>)', sub, text)
    open(path, "w", encoding="utf-8").write(text)
    print("cleaned attributes on %d instances" % removed)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Place1.rbxlx")
