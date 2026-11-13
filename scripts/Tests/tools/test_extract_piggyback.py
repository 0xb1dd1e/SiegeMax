#!/usr/bin/env python3
"""Self-test for extract_piggyback.py: no gmax needed.

It re-implements the gmax-side encoders in Python (the layouts in scripts/Tests/piggyback.ms)
and checks that the extractor recovers the bytes. Run:  python test_extract_piggyback.py
"""
import io
import os
import struct
import sys
import types
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extract_piggyback as e  # noqa: E402


def f32(x):
    return struct.unpack("<f", struct.pack("<f", x))[0]


def encode_asp_vertices(buf, magic=83, idx=0, cnt=1, scale=0.001):
    """Route A: [seq, hi, lo] vertices as the ASP exporter writes them (positions scaled)."""
    n = len(buf)
    dv = (n + 3) // 4
    total = 2 + dv
    while total % 3:
        total += 1
    v = [(0, magic + 256 * idx, n % 65536), (1, sum(buf) % 256 + 256 * cnt, n // 65536)]
    g = lambda i: buf[i] if i < n else 0  # noqa: E731
    for k in range(dv):
        o = 4 * k
        v.append((2 + k, g(o) + g(o + 1) * 256, g(o + 2) + g(o + 3) * 256))
    while len(v) < total:
        v.append((len(v), 0, 0))
    return [tuple(f32(c * scale) for c in t) for t in v]


def encode_dense(buf, idx=0, cnt=1, flags=0):
    """Route B: map vertices as written into a .gmax Scene stream (float32 triples)."""
    n = len(buf)
    nv = max(3, 2 + (n + 8) // 9)
    chk = sum(buf) % (1 << 24)
    f = [(e.DENSE_MAGIC, n, chk), (idx, cnt, flags)]
    g = lambda i: buf[i] if i < n else 0  # noqa: E731
    for v in range(3, nv + 1):
        b = 9 * (v - 3)
        f.append(tuple(g(b + 3 * k) + g(b + 3 * k + 1) * 256 + g(b + 3 * k + 2) * 65536 for k in range(3)))
    return b"".join(struct.pack("<3f", *map(float, t)) for t in f)


def fake_olefile(scene):
    stream = types.SimpleNamespace(
        openstream=lambda name: io.BytesIO(scene), close=lambda: None)
    return types.SimpleNamespace(OleFileIO=lambda path: stream)


class Rle(unittest.TestCase):
    def test_round_trips(self):
        cases = [b"", b"\x00" * 500, bytes(range(256)) * 3, b"A" * 10 + b"\x03\x06\x09" + b"\xff" * 200,
                 b"\x01\x01\x02\x02\x03\x03\x03", b"\x09", b"z" * 129, b"z" * 130, b"z" * 258, b"z" * 259]
        for c in cases:
            self.assertEqual(e.rle_decompress(e.rle_compress(c)), c)

    def test_zeros_shrink(self):
        self.assertLess(len(e.rle_compress(b"\x00" * 5000)), 100)

    def test_truncated_input_is_an_error(self):
        with self.assertRaises(ValueError):
            e.rle_decompress(bytes([5, 1, 2]))      # literal run cut short
        with self.assertRaises(ValueError):
            e.rle_decompress(bytes([200]))          # run with no byte to repeat


class AspVertices(unittest.TestCase):
    def test_sizes(self):
        for n in (0, 1, 3, 4, 5, 26, 1000, 70000):
            p = e.pattern(n)
            idx, cnt, out, packed = e.decode_verts(encode_asp_vertices(list(p)))
            self.assertEqual((idx, cnt, out, packed), (0, 1, p, False))

    def test_unit_scale_and_order_independence(self):
        verts = encode_asp_vertices(list(e.pattern(300)), scale=1.0)
        verts.reverse()
        self.assertEqual(e.decode_verts(verts)[2], e.pattern(300))

    def test_rle_flag_and_chunk_fields(self):
        packed = e.rle_compress(b"\x00" * 4000)
        idx, cnt, out, flag = e.decode_verts(encode_asp_vertices(list(packed), magic=84, idx=2, cnt=5))
        self.assertEqual((idx, cnt, flag), (2, 5, True))
        self.assertEqual(e.rle_decompress(out), b"\x00" * 4000)

    def test_corruption_is_detected(self):
        verts = encode_asp_vertices(list(e.pattern(100)))
        bad = list(verts)
        bad[5] = (bad[5][0], bad[5][1] + 0.003, bad[5][2])
        with self.assertRaises(ValueError):
            e.decode_verts(bad)                      # checksum mismatch
        with self.assertRaises(ValueError):
            e.decode_verts(verts[:5])                # missing data vertices


class DenseScene(unittest.TestCase):
    def setUp(self):
        self._saved = sys.modules.get("olefile")

    def tearDown(self):
        if self._saved is None:
            sys.modules.pop("olefile", None)
        else:
            sys.modules["olefile"] = self._saved

    def scan(self, scene):
        sys.modules["olefile"] = fake_olefile(scene)
        return e.extract_gmax("x.gmax")

    def test_chunks_inside_other_scene_data(self):
        a, b = e.pattern(5000), e.pattern(5000)[::-1]
        z = e.rle_compress(b"\x00" * 4000)
        scene = (b"junk" * 33 + encode_dense(a, 0, 2) + b"filler" * 9 + encode_dense(b, 1, 2)
                 + b"yy" + encode_dense(z, 0, 1, 1) + encode_dense(b"", 0, 1))
        r = self.scan(scene)
        self.assertEqual(len(r), 4)
        self.assertEqual(r[0][2], a)
        self.assertEqual(r[1][2], b)
        self.assertTrue(r[2][3]["compressed"])
        self.assertEqual(e.rle_decompress(r[2][2]), b"\x00" * 4000)
        self.assertEqual(r[3][2], b"")

    def test_sizes_around_the_9_byte_boundary(self):
        for n in (1, 8, 9, 10, 17, 18, 1000):
            p = e.pattern(n)
            self.assertEqual(self.scan(b"\x01" * 64 + encode_dense(p))[0][2], p)

    def test_checksum_failure_is_skipped(self):
        blob = bytearray(encode_dense(e.pattern(100)))
        blob[40] ^= 0x01
        with self.assertRaises(ValueError):
            self.scan(bytes(blob))

    def test_no_chunks_is_an_error(self):
        with self.assertRaises(ValueError):
            self.scan(b"nothing to see" * 50)


class Pattern(unittest.TestCase):
    def test_matches_the_maxscript_formula(self):
        # PB_TestPattern: (i*7 + (i/256)*13 + 5) mod 256
        self.assertEqual(e.pattern(3), bytes([5, 12, 19]))
        self.assertEqual(e.pattern(258)[256], (256 * 7 + 1 * 13 + 5) % 256)


if __name__ == "__main__":
    unittest.main(verbosity=2)
