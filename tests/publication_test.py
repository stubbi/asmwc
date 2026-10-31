"""Publication checks catch accidental disclosure and measurement corruption."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.export_evidence import export, number_tree, redact


class PublicationTests(unittest.TestCase):
    def test_redaction_removes_identifying_paths_without_changing_measurements(self):
        original = {"binary": "/Users/example/project/bin/ripwc", "other": "/Users/example/work/input.dat",
                    "host": "Darwin example-machine.local 24.6.0 Darwin Kernel Version",
                    "temporary": "/var/folders/aa/bb/T/ripwc-test/data",
                    "samples": [0.012, 0.019, 0.008], "runs": 24, "passed": True,
                    "sha256": "a" * 64}
        published = redact(original, Path("/Users/example/project"))
        self.assertEqual(published["binary"], "$REPO/bin/ripwc")
        self.assertEqual(published["other"], "$LOCAL_PATH")
        self.assertEqual(published["temporary"], "$TMP/data")
        self.assertEqual(published["host"], "Darwin benchmark-host 24.6.0 Darwin Kernel Version")
        self.assertEqual(number_tree(original), number_tree(published))
        self.assertEqual(published["samples"], [0.012, 0.019, 0.008])
        self.assertEqual(published["sha256"], "a" * 64)

    def test_export_refuses_to_replace_existing_reference_results(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, target = root / "results", root / "published"
            source.mkdir()
            (source / "benchmark.json").write_text(json.dumps({"samples": [0.25, 0.5]}))
            export(source, target)
            with self.assertRaises(FileExistsError):
                export(source, target)
            self.assertEqual(json.loads((target / "benchmark.json").read_text())["samples"], [0.25, 0.5])


if __name__ == "__main__":
    unittest.main()
