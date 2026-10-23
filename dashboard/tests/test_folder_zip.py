"""Folder and selection zip downloads from Files: round-trip, confinement, symlinks, zip64, no blocking; fixture drop."""
import http.client, io, os, sys, tempfile, threading, unittest, zipfile
from unittest import mock
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server


class FolderZip(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = server.Server(("127.0.0.1", 0), server.Handler)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.drop, out = os.path.join(t, "drop"), os.path.join(t, "outside")
        os.makedirs(os.path.join(self.drop, "proj", "sub", ".git"))
        os.makedirs(out)
        self.files = {"proj/a.txt": b"alpha\n", "proj/sub/b.bin": os.urandom(70000), "proj/ñ é.md": b"# uni\n", "other.txt": b"other"}
        for rel, data in self.files.items():
            open(os.path.join(self.drop, rel), "wb").write(data)
        open(os.path.join(self.drop, "proj", ".env"), "w").write("SECRET")
        open(os.path.join(self.drop, "proj", "sub", ".git", "HEAD"), "w").write("ref")
        open(os.path.join(out, "secret.txt"), "w").write("SECRET")
        os.symlink(os.path.join(out, "secret.txt"), os.path.join(self.drop, "proj", "link_out.txt"))
        os.symlink(out, os.path.join(self.drop, "proj", "dir_out"))
        os.symlink(out, os.path.join(self.drop, "escape"))
        os.symlink(os.path.join(self.drop, "other.txt"), os.path.join(self.drop, "proj", "link_in.txt"))
        self.saved = server.DROP
        server.DROP = self.drop

    def tearDown(self):
        server.DROP = self.saved
        self.tmp.cleanup()

    def get(self, query):
        c = http.client.HTTPConnection("127.0.0.1", self.srv.server_address[1], timeout=20)
        c.request("GET", "/api/files/zip?" + query)
        r = c.getresponse()
        out = r.status, r.getheader("Content-Disposition", ""), r.read()
        c.close()
        return out

    def test_folder_round_trip(self):
        code, disp, body = self.get("p=proj")
        self.assertEqual(code, 200)
        self.assertIn('filename="proj.zip"', disp)
        z = zipfile.ZipFile(io.BytesIO(body))
        self.assertIsNone(z.testzip())
        want = {"proj/a.txt": self.files["proj/a.txt"], "proj/sub/b.bin": self.files["proj/sub/b.bin"],
                "proj/ñ é.md": self.files["proj/ñ é.md"], "proj/link_in.txt": b"other"}
        self.assertEqual(sorted(z.namelist()), sorted(want))
        for name, data in want.items():
            self.assertEqual(z.read(name), data)

    def test_traversal_and_hidden_refused(self):
        for q in ("p=../outside", "p=/etc", "p=proj/../../outside", "p=proj/.env", "p=", "", "p=missing", "p=proj/%00x"):
            self.assertEqual(self.get(q)[0], 400, q)

    def test_symlink_escape_refused(self):
        for q in ("p=escape", "p=proj/dir_out", "p=proj/link_out.txt"):
            self.assertEqual(self.get(q)[0], 400, q)
        body = self.get("p=proj")[2]
        self.assertNotIn(b"SECRET", body)

    def test_selection_zip(self):
        code, disp, body = self.get("p=proj/a.txt&p=proj/sub&p=proj/sub/b.bin")
        self.assertEqual(code, 200)
        self.assertIn('filename="proj-selection.zip"', disp)
        z = zipfile.ZipFile(io.BytesIO(body))
        self.assertEqual(sorted(z.namelist()), ["a.txt", "sub/b.bin"])
        self.assertEqual(z.read("sub/b.bin"), self.files["proj/sub/b.bin"])
        self.assertIn('filename="drop-selection.zip"', self.get("p=proj&p=other.txt")[1])
        self.assertEqual(self.get("p=proj/a.txt&p=escape")[0], 400)

    def test_zip64_past_the_limits(self):
        with mock.patch.object(zipfile, "ZIP64_LIMIT", 1000), mock.patch.object(zipfile, "ZIP_FILECOUNT_LIMIT", 2):
            code, _, body = self.get("p=proj")
        self.assertEqual(code, 200)
        self.assertIn(b"PK\x06\x06", body)
        z = zipfile.ZipFile(io.BytesIO(body))
        self.assertEqual(z.read("proj/sub/b.bin"), self.files["proj/sub/b.bin"])

    def test_stream_does_not_block_other_requests(self):
        with open(os.path.join(self.drop, "proj", "big.bin"), "wb") as f:
            f.truncate(256 << 20)
        c = http.client.HTTPConnection("127.0.0.1", self.srv.server_address[1], timeout=20)
        c.request("GET", "/api/files/zip?p=proj")
        r = c.getresponse()
        self.assertEqual(r.status, 200)
        r.read(1 << 16)
        o = http.client.HTTPConnection("127.0.0.1", self.srv.server_address[1], timeout=5)
        o.request("GET", "/api/ls?p=proj")
        self.assertEqual(o.getresponse().status, 200)
        o.close()
        c.close()


if __name__ == "__main__":
    unittest.main()
