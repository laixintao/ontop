#!/usr/bin/env python3
"""Exercise release automation using disposable local Git repositories and a fake gh."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


def command(*args, cwd, check=True, env=None):
    return subprocess.run(args, cwd=cwd, env=env, check=check, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=40)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ontop-release-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / "work"
        self.remote = self.base / "origin.git"
        self.repo.mkdir()
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        self.env.pop("VERSION", None)
        for name in (".github", "OnTop", "scripts", "docs", "README.md", "README.zh-CN.md",
                     "CONTRIBUTING.md", "SECURITY.md", "CHANGELOG.md", "LICENSE", "Makefile"):
            source, target = ROOT / name, self.repo / name
            if source.is_dir():
                shutil.copytree(source, target, ignore=shutil.ignore_patterns("__pycache__"))
            else:
                shutil.copy2(source, target)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "release-test@example.invalid")
        self.git("add", ".")
        self.git("commit", "-m", "Initial fixture")
        command("git", "init", "--bare", "--initial-branch=main", str(self.remote), cwd=self.base, env=self.env)
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "-u", "origin", "main")
        self.initial = self.git("rev-parse", "HEAD")
        self.info = plistlib.loads((self.repo / "OnTop/Info.plist").read_bytes())
        major, minor, patch = map(int, self.info["CFBundleShortVersionString"].split("."))
        self.next_version = f"{major}.{minor}.{patch + 1}"
        self.next_tag = "v" + self.next_version

    def git(self, *args):
        return command("git", *args, cwd=self.repo, env=self.env).stdout.strip()

    def release(self, *args):
        return command(sys.executable, "scripts/release.py", *args, cwd=self.repo, env=self.env, check=False)

    def assert_unchanged(self):
        self.assertEqual(self.initial, self.git("rev-parse", "HEAD"))
        self.assertEqual(self.initial, self.git("ls-remote", "origin", "refs/heads/main").split()[0])

    def test_patch_release_pushes_commit_and_annotated_tag(self):
        result = command("make", "release", cwd=self.repo, env=self.env, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        info = plistlib.loads((self.repo / "OnTop/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleShortVersionString"], self.next_version)
        self.assertEqual(int(info["CFBundleVersion"]), int(self.info["CFBundleVersion"]) + 1)
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertEqual(self.git("cat-file", "-t", self.next_tag), "tag")
        head = self.git("rev-parse", "HEAD")
        self.assertEqual(head, self.git("ls-remote", "origin", "refs/heads/main").split()[0])
        self.assertEqual(head, self.git("ls-remote", "origin", f"refs/tags/{self.next_tag}^{{}}").split()[0])
        notes = (self.repo / f"docs/releases/{self.next_tag}.md").read_text()
        self.assertIn("## 中文", notes)
        self.assertIn("Initial fixture", notes)
        self.assertIn(f"## {self.next_version}", (self.repo / "CHANGELOG.md").read_text())

    def test_explicit_version_preserves_prepared_notes(self):
        version = "99.0.0"
        notes = self.repo / f"docs/releases/v{version}.md"
        custom = "# A carefully written release\n\nEnglish details.\n\n## 中文\n人工编写的说明。\n"
        notes.write_text(custom)
        self.git("add", str(notes))
        self.git("commit", "-m", "Prepare release notes")
        result = command("make", "release", f"VERSION={version}", cwd=self.repo, env=self.env, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(notes.read_text(), custom)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.git("rev-parse", f"v{version}^{{}}"))

    def test_dirty_tree_stops_before_release_edits(self):
        (self.repo / "unfinished.txt").write_text("work in progress")
        result = self.release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("working tree must be clean", result.stderr)
        self.assert_unchanged()
        self.assertEqual(self.git("status", "--porcelain"), "?? unfinished.txt")

    def test_invalid_or_nonincreasing_version_stops(self):
        for version in ("v2.0.0", "2.0", "01.2.3", "0.0.1", self.info["CFBundleShortVersionString"], "1.2.3;touch BAD"):
            with self.subTest(version=version):
                self.assertNotEqual(self.release("--version", version).returncode, 0)
                self.assert_unchanged()
                self.assertEqual(self.git("status", "--porcelain"), "")

    def test_wrong_branch_stops(self):
        self.git("switch", "-c", "feature")
        result = self.release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("main branch", result.stderr)
        self.assert_unchanged()

    def test_existing_remote_tag_stops_without_edits(self):
        self.git("tag", self.next_tag)
        self.git("push", "origin", self.next_tag)
        self.git("tag", "-d", self.next_tag)
        result = self.release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already exists on origin", result.stderr)
        self.assert_unchanged()
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_remote_ahead_stops_without_edits(self):
        other = self.base / "other"
        command("git", "clone", str(self.remote), str(other), cwd=self.base, env=self.env)
        command("git", "-c", "user.name=Other", "-c", "user.email=other@example.invalid", "commit", "--allow-empty", "-m", "Remote work", cwd=other, env=self.env)
        command("git", "push", cwd=other, env=self.env)
        result = self.release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Remote main has changes", result.stderr)
        self.assertEqual(self.initial, self.git("rev-parse", "HEAD"))
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_failed_push_keeps_retryable_commit_and_tag(self):
        hook = self.remote / "hooks/pre-receive"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)
        result = self.release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("git push --atomic", result.stderr)
        self.assertNotEqual(self.initial, self.git("rev-parse", "HEAD"))
        self.assertEqual(self.git("rev-parse", "HEAD"), self.git("rev-parse", f"{self.next_tag}^{{}}"))
        self.assertEqual(self.initial, self.git("ls-remote", "origin", "refs/heads/main").split()[0])
        self.assertEqual(self.git("ls-remote", "origin", f"refs/tags/{self.next_tag}"), "")
        self.assertEqual(self.git("status", "--porcelain"), "")
        hook.unlink()
        self.git("push", "--atomic", "origin", "HEAD:refs/heads/main", f"refs/tags/{self.next_tag}")
        self.assertEqual(self.git("rev-parse", "HEAD"), self.git("ls-remote", "origin", f"refs/tags/{self.next_tag}^{{}}").split()[0])


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ontop-publish-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.log = self.base / "commands.jsonl"
        fake = self.base / "gh"
        fake.write_text('''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ["FAKE_GH_LOG"], "a") as output:
    output.write(json.dumps(args) + "\\n")
mode = os.environ["FAKE_GH_MODE"]
if args[:2] == ["release", "view"]:
    if mode in ("new", "upload-fails"):
        sys.exit(1)
    print("false" if mode == "published" else "true")
if args[:2] == ["release", "upload"] and mode == "upload-fails":
    sys.exit(1)
''')
        fake.chmod(0o755)
        info = plistlib.loads((ROOT / "OnTop/Info.plist").read_bytes())
        self.env = dict(os.environ, PATH=str(self.base) + os.pathsep + os.environ["PATH"],
                        RELEASE_TAG="v" + info["CFBundleShortVersionString"], GH_REPO="test/fixture",
                        FAKE_GH_LOG=str(self.log))

    def publish(self, mode):
        result = command("bash", "scripts/publish-release.sh", cwd=ROOT,
                         env=dict(self.env, FAKE_GH_MODE=mode), check=False)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, calls

    def test_published_release_is_untouched(self):
        result, calls = self.publish("published")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[:2] for call in calls], [["release", "view"]])

    def test_new_release_uploads_before_publishing(self):
        result, calls = self.publish("new")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[1] for call in calls], ["view", "create", "upload", "edit"])
        self.assertIn("--draft", calls[1])
        self.assertIn("--verify-tag", calls[1])
        self.assertIn("--draft=false", calls[-1])

    def test_interrupted_draft_can_resume(self):
        result, calls = self.publish("draft")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[1] for call in calls], ["view", "edit", "upload", "edit"])
        self.assertIn("--draft=false", calls[-1])

    def test_failed_upload_does_not_publish(self):
        result, calls = self.publish("upload-fails")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([call[1] for call in calls], ["view", "create", "upload"])

    def test_mismatched_tag_makes_no_github_calls(self):
        self.env["RELEASE_TAG"] = "v0.0.0"
        result, calls = self.publish("new")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
