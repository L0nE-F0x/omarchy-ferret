#!/usr/bin/python3
"""Supply-chain tests for ferret-search: trusted binaries, caps, groups."""

import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from importlib.machinery import SourceFileLoader

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELPER = os.path.join(ROOT, "ferret-search")


def load_backend():
    loader = SourceFileLoader("ferret_search", HELPER)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class ResolveBinTests(unittest.TestCase):
    def setUp(self):
        self.mod = load_backend()

    def test_plocate_is_absolute_and_trusted(self):
        path = self.mod.resolve_bin("plocate")
        self.assertEqual(path, "/usr/bin/plocate")
        self.assertTrue(os.path.isabs(path))

    def test_python3_is_absolute(self):
        path = self.mod.resolve_bin("python3")
        self.assertEqual(path, "/usr/bin/python3")

    def test_rejects_slash_names(self):
        self.assertIsNone(self.mod.resolve_bin("../etc/passwd"))
        self.assertIsNone(self.mod.resolve_bin("/usr/bin/plocate"))
        self.assertIsNone(self.mod.resolve_bin("."))

    def test_ignores_path_shadow(self):
        tmp = tempfile.mkdtemp(prefix="ferret-shadow-")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        shadow = os.path.join(tmp, "plocate")
        with open(shadow, "w", encoding="utf-8") as fh:
            fh.write("#!/bin/sh\necho shadowed\n")
        os.chmod(shadow, 0o755)
        old = os.environ.get("PATH", "")
        os.environ["PATH"] = tmp + ":" + old
        self.addCleanup(os.environ.__setitem__, "PATH", old)
        self.assertEqual(self.mod.resolve_bin("plocate"), "/usr/bin/plocate")

    def test_missing_binary(self):
        self.assertIsNone(self.mod.resolve_bin("ferret-no-such-bin"))


class RunCapTests(unittest.TestCase):
    def setUp(self):
        self.mod = load_backend()
        self.python = "/usr/bin/python3"

    def test_stdout_cap_truncates_and_kills(self):
        script = (
            "import sys, time\n"
            "sys.stdout.write(('A' * 80 + '\\n') * 40000)\n"
            "sys.stdout.flush()\n"
            "time.sleep(30)\n"
        )
        started = time.monotonic()
        paths = self.mod.run([self.python, "-c", script], timeout=4.0)
        elapsed = time.monotonic() - started
        self.assertLess(elapsed, 8.0)
        joined = "\n".join(paths).encode("utf-8")
        self.assertLessEqual(len(joined), self.mod.STDOUT_CAP)
        self.assertGreater(len(paths), 0)
        self.assertTrue(all(p == "A" * 80 for p in paths))

    def test_timeout_kills_process_group(self):
        script = (
            "import os, time, sys\n"
            "if os.fork() == 0:\n"
            "    time.sleep(60)\n"
            "time.sleep(60)\n"
        )
        started = time.monotonic()
        paths = self.mod.run([self.python, "-c", script], timeout=0.4)
        elapsed = time.monotonic() - started
        self.assertEqual(paths, [])
        self.assertLess(elapsed, 3.0)

    def test_rejects_relative_argv0(self):
        self.assertEqual(self.mod.run(["plocate", "ferret"]), [])


class DesktopValidationTests(unittest.TestCase):
    def setUp(self):
        self.mod = load_backend()

    def test_rejects_desktop_id(self):
        self.assertFalse(self.mod._valid_desktop("omawrite.desktop"))
        self.assertFalse(self.mod._valid_desktop("vlc"))

    def test_rejects_missing_file(self):
        self.assertFalse(self.mod._valid_desktop("/tmp/ferret-missing.desktop"))

    def test_accepts_system_desktop_file(self):
        sample = "/usr/share/applications/omawrite.desktop"
        if not os.path.isfile(sample):
            self.skipTest("omawrite.desktop not installed")
        self.assertTrue(self.mod._valid_desktop(sample))


class CliTests(unittest.TestCase):
    def test_search_returns_json(self):
        out = subprocess.check_output(
            ["/usr/bin/python3", HELPER, "--", "ferret-search"],
            timeout=8,
        )
        self.assertTrue(out.startswith(b"[") or out == b"[]")
        self.assertLessEqual(len(out), 1 * 1024 * 1024)

    def test_empty_query(self):
        out = subprocess.check_output(
            ["/usr/bin/python3", HELPER],
            timeout=4,
        )
        self.assertEqual(out, b"[]")

    def test_shebang_is_absolute_python(self):
        with open(HELPER, "r", encoding="utf-8") as fh:
            first = fh.readline().strip()
        self.assertEqual(first, "#!/usr/bin/python3")
        self.assertNotIn("env python", first)


if __name__ == "__main__":
    unittest.main()
