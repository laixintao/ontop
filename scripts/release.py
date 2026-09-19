#!/usr/bin/env python3
"""Bump, commit, and atomically push a release; GitHub Actions builds and publishes it."""
import argparse
from datetime import date
import html
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def run(*args, check=True):
    return subprocess.run(args, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=check)


def git(*args):
    return run("git", *args).stdout.strip()


def version_tuple(value):
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", value):
        raise ValueError("Use a version like 1.2.3 (without a v prefix).")
    return tuple(map(int, value.split(".")))


def release_notes(version, changes):
    return f"""## OnTop {version}

Keep a live reference above your work, with clicks and scrolling passing through.

### Changes

{changes}

### Install

Download **OnTop-{version}-universal.dmg**, open it, and drag OnTop into Applications.
The ZIP is also available. Both support Apple Silicon and Intel.

- macOS 14+; Return to App and automatic source-app hide/restore require macOS 15.2+.
- Ad-hoc signed, **not Apple-notarized**. If blocked on first launch, use System Settings → Privacy & Security → Open Anyway. [Apple's instructions](https://support.apple.com/en-us/102445).
- SHA-256 checksums are in `SHA256SUMS`. Verify build provenance with `gh attestation verify OnTop-{version}-universal.dmg --repo laixintao/ontop`.

---

## 中文

实时置顶参考窗口，鼠标点击和滚动穿透到下方窗口。

### 本次变更

上方 Changes 列出了本次发布包含的提交；提交标题保留原文。

### 安装

下载 **OnTop-{version}-universal.dmg**，打开后把 OnTop 拖入「应用程序」，也可以解压 ZIP。通用包支持 Apple Silicon 和 Intel。

要求 macOS 14+；返回 App 和自动显隐要求 macOS 15.2+。**当前未经过 Apple 公证**，首次打开如被拦截，请前往「系统设置 → 隐私与安全性 → 仍要打开」。[Apple 的说明](https://support.apple.com/zh-cn/102445)。附件提供 SHA-256 校验值和 GitHub 构建来源证明。
"""


def main(requested=None):
    if git("status", "--porcelain"):
        raise ValueError("Commit or stash your changes before releasing; the working tree must be clean.")
    if git("branch", "--show-current") != "main":
        raise ValueError("Release from the main branch.")
    plist_path = ROOT / "OnTop/Info.plist"
    plist_text = plist_path.read_text()
    info = plistlib.loads(plist_text.encode())
    current = info["CFBundleShortVersionString"]
    major, minor, patch = version_tuple(current)
    version = requested or f"{major}.{minor}.{patch + 1}"
    if version_tuple(version) <= (major, minor, patch):
        raise ValueError(f"The next version must be newer than {current}.")
    build = int(info["CFBundleVersion"]) + 1
    tag = f"v{version}"
    if run("git", "show-ref", "--verify", "--quiet", f"refs/tags/{tag}", check=False).returncode == 0:
        raise ValueError(f"{tag} already exists locally. Retry its push instead of bumping again.")

    # Fetch before editing files. Never overwrite a remote branch or a version tag.
    git("fetch", "--quiet", "origin", "refs/heads/main", "--tags")
    remote_head = git("rev-parse", "FETCH_HEAD")
    if run("git", "merge-base", "--is-ancestor", remote_head, "HEAD", check=False).returncode:
        raise ValueError("Remote main has changes you do not have. Pull/rebase before releasing.")
    if git("ls-remote", "origin", f"refs/tags/{tag}"):
        raise ValueError(f"{tag} already exists on origin. Choose a new version.")

    base = f"v{current}"
    has_base = run("git", "rev-parse", "--verify", f"refs/tags/{base}", check=False).returncode == 0
    revision = f"{base}..HEAD" if has_base else "HEAD"
    commits = git("log", "--no-merges", "--format=%h%x09%s", revision)
    changes = []
    for line in commits.splitlines():
        sha, subject = line.split("\t", 1)
        subject = re.sub(r"([\\`*_\[\]])", r"\\\1", html.escape(subject))
        changes.append(f"- {subject} (`{sha}`)")
    if not changes:
        raise ValueError("There are no new commits since the current release.")
    changes = "\n".join(changes)

    for key, value in (("CFBundleShortVersionString", version), ("CFBundleVersion", str(build))):
        plist_text, count = re.subn(rf"(<key>{key}</key>\s*<string>)[^<]*(</string>)",
                                   lambda match: match[1] + value + match[2], plist_text)
        if count != 1:
            raise ValueError(f"Expected one {key} string in Info.plist.")
    plist_path.write_text(plist_text)
    notes_path = ROOT / f"docs/releases/{tag}.md"
    if not notes_path.exists():
        notes_path.write_text(release_notes(version, changes))
    changelog_path = ROOT / "CHANGELOG.md"
    changelog = changelog_path.read_text()
    if not re.search(rf"^## {re.escape(version)}(?:\s|$)", changelog, re.MULTILINE):
        heading, separator, remainder = changelog.partition("\n")
        entry = (f"\n## {version} — {date.today().isoformat()}\n\n"
                 f"[Release notes / 发布说明](docs/releases/{tag}.md)\n\n{changes}\n")
        changelog_path.write_text(heading + separator + entry + remainder)

    # Fail before a commit or push if metadata is inconsistent. Keep edits for inspection.
    subprocess.run([sys.executable, "scripts/check-project.py", "--release-tag", tag], cwd=ROOT, check=True)
    paths = ["OnTop/Info.plist", "CHANGELOG.md", f"docs/releases/{tag}.md"]
    git("add", "--", *paths)
    git("commit", "-m", f"Release {tag}")
    git("tag", "-a", tag, "-m", f"OnTop {version}")
    print(f"Prepared {tag} (build {build}). Pushing main and tag together…", flush=True)
    pushed = run("git", "push", "--atomic", "origin", "HEAD:refs/heads/main", f"refs/tags/{tag}", check=False)
    if pushed.returncode:
        print(pushed.stderr, file=sys.stderr)
        print(f"Commit and tag are kept locally. After fixing the push error, retry:\n"
              f"  git push --atomic origin HEAD:refs/heads/main refs/tags/{tag}\n"
              "Do not run make release again to retry this version.", file=sys.stderr)
        return 1
    print(f"Pushed {tag}. GitHub Actions will test both architectures, package, attest, and publish.\n"
          "Follow progress: https://github.com/laixintao/ontop/actions/workflows/release.yml\n"
          f"Release (available after CI): https://github.com/laixintao/ontop/releases/tag/{tag}")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default=os.environ.get("VERSION") or None)
    try:
        sys.exit(main(parser.parse_args().version))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        sys.exit(1)
