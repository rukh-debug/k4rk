"""Regressions for English documentation claims and explicit lint coverage."""

import contextlib
import io
import pathlib
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import api as api_checker
import docs_check


class NumericClaimTests(unittest.TestCase):
    def setUp(self):
        self.sources = {
            docs_check.RAIZ / "tools/plugins.py": "ICONO_MINIMO = 64\nICONO_MAXIMO_MB = 1\n",
            docs_check.RAIZ / "core/Theme.qml": "readonly property int maxIslandHeight: 880\n",
        }

    def check(self, text):
        with patch.object(pathlib.Path, "read_text", autospec=True,
                          side_effect=lambda path: self.sources[path]):
            return docs_check.revisar_numeros("docs/PLUGINS.md", text)

    def test_current_guide_claims_are_recognized_and_match_sources(self):
        """A green result must include recognition of the actual English prose."""
        text = (docs_check.RAIZ / "docs/PLUGINS.md").read_text()
        for pattern, source, _, description in docs_check.NUMEROS:
            if source == "tools/plugins.py":
                with self.subTest(claim=description):
                    self.assertRegex(text, pattern)
        self.assertEqual(docs_check.revisar_numeros("docs/PLUGINS.md", text), [])

    def test_changed_current_guide_claims_fail(self):
        """Mutate each live claim, so an obsolete recognizer cannot pass silently."""
        text = (docs_check.RAIZ / "docs/PLUGINS.md").read_text()
        for pattern, source, _, description in docs_check.NUMEROS:
            if source != "tools/plugins.py":
                continue
            with self.subTest(claim=description):
                match = re.search(pattern, text)
                self.assertIsNotNone(match)
                changed = (text[:match.start(1)] + str(int(match.group(1)) + 1)
                           + text[match.end(1):])
                errors = docs_check.revisar_numeros("docs/PLUGINS.md", changed)
                self.assertTrue(any(description in error for error in errors), errors)

    def test_matching_english_claims_pass(self):
        self.assertEqual(self.check("PNG **64×64**, less than 1 MB; height (880 today)."), [])

    def test_each_dimension_and_limit_is_checked(self):
        for text, description in (
            ("PNG **128×64**", "minimum PNG icon width"),
            ("PNG **64×128**", "minimum PNG icon height"),
            ("less than 2 MB", "maximum icon size"),
            ("Maximum island height (900 today)", "maximum island height"),
        ):
            with self.subTest(text=text):
                errors = self.check(text)
                self.assertEqual(len(errors), 1, errors)
                self.assertIn(description, errors[0])
                self.assertIn("docs/PLUGINS.md:", errors[0])

    def test_later_contradictory_claim_is_not_hidden_by_first_match(self):
        errors = self.check("less than 1 MB\nLater: less than 2 MB")
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("claims 2", errors[0])

    def test_line_wrapped_english_claim_is_checked(self):
        self.assertEqual(self.check("less than\n1 MB"), [])
        self.assertTrue(self.check("less than\n2 MB"))

    def test_source_change_and_missing_constant_fail(self):
        source = docs_check.RAIZ / "tools/plugins.py"
        self.sources[source] = "ICONO_MAXIMO_MB = 2\n"
        self.assertIn("uses 2", self.check("less than 1 MB")[0])
        self.sources[source] = ""
        self.assertIn("cannot find maximum icon size", self.check("less than 1 MB")[0])

    def test_unrelated_numbers_and_absent_height_claim_are_not_errors(self):
        self.assertEqual(self.check("A 200×150 strip; width: 210; 32 MB of memory."), [])
        self.assertEqual(self.check("Use K4.Isla.altoMaximo as a height budget."), [])


class ExampleLintTests(unittest.TestCase):
    def test_missing_qmllint_warns_instead_of_silently_passing(self):
        output = io.StringIO()
        with patch.object(docs_check.shutil, "which", return_value=None), \
                patch.object(docs_check.subprocess, "run") as run, \
                contextlib.redirect_stderr(output):
            self.assertEqual(docs_check.revisar_ejemplos("guide.md", "```qml\nItem {}\n```"), [])
        run.assert_not_called()
        self.assertIn("warning: guide.md: qmllint not found", output.getvalue())
        self.assertIn("QML example checks skipped", output.getvalue())

    def test_available_qmllint_checks_examples_and_reports_failures(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "tools").mkdir()
            for returncode in (0, 1, 255):
                with self.subTest(returncode=returncode):
                    def lint(command, **kwargs):
                        self.assertEqual(command[:3], ["qmllint", "-I", str(root / "api")])
                        source = pathlib.Path(command[-1]).read_text()
                        self.assertIn("import K4 as K4", source)
                        self.assertIn("function toggle()", source)
                        self.assertNotIn(": void", source)
                        return subprocess.CompletedProcess(command, returncode, "", "")

                    with patch.object(docs_check, "RAIZ", root), \
                            patch.object(docs_check.shutil, "which", return_value="/bin/qmllint"), \
                            patch.object(docs_check.subprocess, "run", side_effect=lint) as run:
                        errors = docs_check.revisar_ejemplos(
                            "guide.md", "```qml\nItem { function toggle(): void {} }\n```")
                    run.assert_called_once()
                    self.assertFalse((root / "tools/.guia_tmp.qml").exists())
                    if returncode:
                        self.assertEqual(len(errors), 1)
                        self.assertIn(f"example 1 failed lint: qmllint exited with {returncode}", errors[0])
                    else:
                        self.assertEqual(errors, [])


class ImportBoundaryTests(unittest.TestCase):
    def check(self, text):
        path = api_checker.RAIZ / "plugins/Example/Plugin.qml"
        with patch.object(pathlib.Path, "read_text", return_value=text):
            return api_checker.revisar(path)

    def test_current_qt_and_host_import_behavior_is_preserved(self):
        """Record the current enforcement gap without expanding accepted imports."""
        for statement in ("import QtQuick", "import K4 as K4", "import QtMultimedia",
                          'import "../../core"', 'import "../../services" as Services'):
            with self.subTest(statement=statement):
                self.assertEqual(self.check(statement + "\nItem {}"), [])

    def test_direct_platform_imports_and_types_still_fail(self):
        self.assertTrue(self.check("import Quickshell.Io\nItem {}"))
        self.assertTrue(self.check("import QtQuick\nFileView {}"))


if __name__ == "__main__":
    unittest.main()
