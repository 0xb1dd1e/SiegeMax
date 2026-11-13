#!/usr/bin/env python3
"""Extract data smuggled out of gmax by scripts/Tests/piggyback.ms.

Two routes (see the header comment in piggyback.ms for the layouts):
  A) exported .asp files: the payload rides in the vertex positions (BVTX chunk)
  B) saved .gmax scene files: the payload rides in a map channel ("dense" chunks, found by a
     float32 signature in the OLE 'Scene' stream; needs the 'olefile' package)

Usage:
  extract_piggyback.py FILE_OR_DIR [...] [-o OUT] [--text] [--verify] [--report] [--prefix P]

  FILE_OR_DIR  .asp or .gmax files (a .gmax may hold many chunks), or folders searched
               (non-recursively) for both
  -o OUT       write the recovered bytes to OUT (chunks from all inputs joined, RLE expanded)
  --text       print the recovered bytes as text
  --verify     compare against the PB_TestPattern payload used by LimitTest / LimitTestSave
  --report     per-file report only (no payload output)
  --prefix P   only files whose name starts with P (case-insensitive)

Self-test: python test_extract_piggyback.py
"""
import argparse
import glob
import os
import struct
import sys

MAGIC = 83        # raw payload
MAGIC_RLE = 84    # RLE-compressed payload


def rle_decompress(buf):
    """Inverse of PB_Compress: c<128 -> copy c+1 literals; c>=128 -> repeat next byte c-126 times."""
    out = bytearray()
    i = 0
    n = len(buf)
    while i < n:
        c = buf[i]
        if c < 128:
            if i + c + 2 > n:
                raise ValueError("truncated RLE literal")
            out += buf[i + 1:i + c + 2]
            i += c + 2
        else:
            if i + 2 > n:
                raise ValueError("truncated RLE run")
            out += bytes((buf[i + 1],)) * (c - 126)
            i += 2
    return bytes(out)


def rle_compress(buf):
    """Python mirror of PB_Compress (used by the self-test)."""
    out = bytearray()
    lit = bytearray()
    i = 0
    n = len(buf)

    def flush():
        if lit:
            out.append(len(lit) - 1)
            out.extend(lit)
            lit.clear()

    while i < n:
        j = i
        while j + 1 < n and j - i < 128 and buf[j + 1] == buf[i]:
            j += 1
        r = j - i + 1
        if r >= 3:
            flush()
            out.append(r + 126)
            out.append(buf[i])
            i = j + 1
        else:
            lit.append(buf[i])
            i += 1
            if len(lit) == 128:
                flush()
    flush()
    return bytes(out)


def pattern(n):
    """Same formula as PB_TestPattern in piggyback.ms."""
    return bytes((i * 7 + (i // 256) * 13 + 5) % 256 for i in range(n))


def find_vertex_lists(data):
    """Yield (offset, [(x,y,z), ...]) for every plausible BVTX chunk."""
    pos = 0
    while True:
        i = data.find(b"BVTX", pos)
        if i < 0:
            return
        pos = i + 4
        if i + 12 > len(data):
            continue
        count = struct.unpack_from("<I", data, i + 8)[0]
        end = i + 12 + 12 * count
        if count == 0 or end > len(data):
            continue
        yield i, [struct.unpack_from("<3f", data, i + 12 + 12 * k) for k in range(count)]


def decode_verts(verts):
    """Return (chunk_idx, chunk_count, bytes, is_compressed) or raise ValueError."""
    if len(verts) < 3:
        raise ValueError("fewer than 3 vertices")
    xs = sorted(abs(v[0]) for v in verts)
    if xs[1] <= 0.0:
        raise ValueError("cannot calibrate scale")
    scale = 1.0 / xs[1]

    lookup = {}
    for v in verts:
        seq = int(round(abs(v[0]) * scale))
        lookup[seq] = (int(round(abs(v[1]) * scale)), int(round(abs(v[2]) * scale)))
    if 0 not in lookup or 1 not in lookup:
        raise ValueError("header vertices missing")

    hy, n_low = lookup[0]
    v2, n_high = lookup[1]
    magic = hy % 256
    if magic not in (MAGIC, MAGIC_RLE):
        raise ValueError("bad magic %d" % magic)
    chunk_idx = hy // 256
    checksum = v2 % 256
    chunk_count = v2 // 256
    n = n_low + n_high * 65536

    out = bytearray()
    for k in range((n + 3) // 4):
        if 2 + k not in lookup:
            raise ValueError("missing data vertex seq %d (have %d vertices, need %d)"
                             % (2 + k, len(verts), 2 + (n + 3) // 4))
        hi, lo = lookup[2 + k]
        out += bytes((hi % 256, hi // 256, lo % 256, lo // 256))
    out = bytes(out[:n])
    if sum(out) % 256 != checksum:
        raise ValueError("checksum mismatch")
    return chunk_idx, chunk_count, out, magic == MAGIC_RLE


def extract_file(path):
    """Return (chunk_idx, chunk_count, bytes, info) for one ASP file; bytes are still compressed if info["compressed"]."""
    data = open(path, "rb").read()
    lists = list(find_vertex_lists(data))
    if not lists:
        raise ValueError("no BVTX chunk")
    errors = []
    for offset, verts in lists:
        try:
            idx, cnt, payload, packed = decode_verts(verts)
            return idx, cnt, payload, {"compressed": packed, "verts": len(verts), "bvtx_chunks": len(lists),
                                       "file_size": len(data)}
        except ValueError as e:
            errors.append("BVTX@%d (%d verts): %s" % (offset, len(verts), e))
    raise ValueError("; ".join(errors))


def extract_gmax(path):
    """Scan the Scene stream of a .gmax scene (an OLE compound file) for piggyback chunks.

    No scene chunk parsing: the dense chunk header is a float32 signature that is searched for
    (see find_dense_chunks). Needs the 'olefile' package.
    Returns a list of (idx, cnt, bytes, info).
    """
    try:
        import olefile
    except ImportError:
        raise ValueError("reading .gmax needs: pip install olefile")
    ole = olefile.OleFileIO(path)
    try:
        data = ole.openstream("Scene").read()
    finally:
        ole.close()

    results = find_dense_chunks(data)
    if not results:
        raise ValueError("no piggyback chunks found in the Scene stream")
    return results


DENSE_MAGIC = 5259844   # 'P'*65536 + 'B'*256 + 'D'


def find_dense_chunks(data):
    """Find dense map-channel chunks (see 'Dense mode' in piggyback.ms) in a Scene stream.

    map vert 1: [DENSE_MAGIC, byteCount, checksum]; map vert 2: [chunkIdx, chunkCount, flags];
    then 9 payload bytes per map vertex as three 24-bit integers stored in float32.
    """
    magic = struct.pack("<f", float(DENSE_MAGIC))
    out = []
    pos = 0
    while True:
        i = data.find(magic, pos)
        if i < 0:
            break
        pos = i + 1
        if i + 24 > len(data):
            continue
        m, n, chk = struct.unpack_from("<3f", data, i)
        idx, cnt, flags = struct.unpack_from("<3f", data, i + 12)
        vals = (n, chk, idx, cnt, flags)
        if m != DENSE_MAGIC or any(v != int(v) or v < 0 for v in vals):
            continue
        n, chk, idx, cnt, flags = (int(v) for v in vals)
        if cnt < 1 or idx >= cnt or flags > 1:
            continue
        data_verts = (n + 8) // 9
        end = i + 24 + 12 * data_verts
        if end > len(data):
            continue
        payload = bytearray()
        floats = struct.unpack_from("<%df" % (3 * data_verts), data, i + 24)
        ok = True
        for f in floats:
            if f != int(f) or f < 0 or f >= 1 << 24:
                ok = False
                break
            v = int(f)
            payload += bytes((v & 255, (v >> 8) & 255, v >> 16))
        if not ok:
            continue
        payload = bytes(payload[:n])
        if sum(payload) % (1 << 24) != chk:
            continue
        out.append((idx, cnt, payload, {"compressed": bool(flags & 1), "verts": 2 + data_verts,
                                        "bvtx_chunks": 0, "file_size": len(data)}))
        pos = end
    return out


def extract_any(path):
    """List of (idx, cnt, bytes, info) from an .asp (one chunk) or .gmax (many) file."""
    if path.lower().endswith(".gmax"):
        return extract_gmax(path)
    idx, cnt, payload, info = extract_file(path)
    return [(idx, cnt, payload, info)]


def gather(paths):
    files = []
    for p in paths:
        if os.path.isdir(p):
            files += sorted(glob.glob(os.path.join(p, "*.[aA][sS][pP]")))
            files += sorted(glob.glob(os.path.join(p, "*.[gG][mM][aA][xX]")))
        else:
            files.append(p)
    return files


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("-o", "--out")
    ap.add_argument("--text", action="store_true")
    ap.add_argument("--verify", action="store_true")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--prefix", default="", help="only files whose name starts with this (case-insensitive)")
    args = ap.parse_args()

    files = [f for f in gather(args.inputs)
             if os.path.basename(f).lower().startswith(args.prefix.lower())]
    if not files:
        sys.exit("no .asp files found")

    chunks = []
    failures = 0
    for f in files:
        try:
            found = extract_any(f)
        except (ValueError, OSError) as e:
            failures += 1
            print("FAIL  %-40s %s" % (os.path.basename(f), e))
            continue
        for idx, cnt, payload, info in found:
            status = "ok"
            if info["compressed"]:
                status = "ok (rle)"
            elif args.verify and cnt == 1:
                status = "verified" if payload == pattern(len(payload)) else "PATTERN MISMATCH"
                if status != "verified":
                    failures += 1
            print("%-8s %-40s chunk %d/%d  %8d bytes  %7d verts  %d BVTX  file %d B"
                  % (status, os.path.basename(f), idx + 1, cnt, len(payload), info["verts"],
                     info["bvtx_chunks"], info["file_size"]))
            chunks.append((idx, cnt, payload, info["compressed"]))

    if args.report or not chunks:
        sys.exit(1 if failures else 0)

    # Join chunks in order (only meaningful when all inputs are one payload)
    expected = chunks[0][1]
    ordered = sorted(chunks, key=lambda c: c[0])
    if [c[0] for c in ordered] == list(range(expected)):
        payload = b"".join(c[2] for c in ordered)
        if ordered[0][3]:
            payload = rle_decompress(payload)
            print("decompressed RLE payload to %d bytes" % len(payload))
        if args.verify and not ordered[0][3]:
            if payload == pattern(len(payload)):
                print("verified joined payload: %d bytes match the test pattern" % len(payload))
            else:
                failures += 1
                print("PATTERN MISMATCH in joined payload (%d bytes)" % len(payload))
        if args.out:
            open(args.out, "wb").write(payload)
            print("wrote %d bytes to %s" % (len(payload), args.out))
        if args.text:
            print(payload.decode("utf-8", errors="replace"))
    else:
        print("note: inputs are not one complete chunk set (have %s of %d); not joining"
              % ([c[0] for c in ordered], expected))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
