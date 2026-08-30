"""Worktree isolation -- the ONLY module in this pipeline that calls git.

Authorised verbs are LOCAL ONLY: worktree, branch, commit, merge, status, rev-parse.
Never push, never gh, never anything that leaves the machine. This is a deliberate,
scoped exception to .claude/CLAUDE.md's "agents run no git commands"; it covers this
script's runtime behaviour and nothing else.

WHY A WORKTREE: quarantined content is complete and LIVE in its own checkout, so the
game can be run with the candidate content in it before approval. A staging directory
inside the main checkout cannot offer that.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

# Guarded rather than documented: a typo that reaches for a network verb fails loudly.
ALLOWED_VERBS = {"worktree", "branch", "commit", "merge", "status", "rev-parse",
                 "add", "checkout", "symbolic-ref"}

WATCHED_DIRS = ("project", "scripts")


def git(repo: Path, *args: str) -> str:
    if args and args[0] not in ALLOWED_VERBS:
        raise RuntimeError(
            f"git verb {args[0]!r} is not authorised for this pipeline "
            f"(local-only: {sorted(ALLOWED_VERBS)})")
    proc = subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc.stdout


def current_branch(repo: Path) -> str:
    return git(repo, "rev-parse", "--abbrev-ref", "HEAD").strip()


def preflight(repo: Path) -> list[str]:
    """Problems that must be empty before a run starts.

    Scoped deliberately to TRACKED changes under project/ and scripts/. A blanket
    cleanliness check would never pass: this repo carries many untracked files by design.
    """
    problems: list[str] = []

    porcelain = git(repo, "status", "--porcelain", "--untracked-files=no")
    for line in porcelain.splitlines():
        path = line[3:].strip()
        if any(path.startswith(d + "/") for d in WATCHED_DIRS):
            problems.append(f"uncommitted change to tracked file: {path}")

    if not git(repo, "status", "--porcelain", "--", "project").strip():
        tracked = git(repo, "status", "--porcelain", "--untracked-files=all", "--", "project")
        if tracked.strip().startswith("??"):
            problems.append("project/ is untracked -- worktree isolation needs it committed")

    existing = git(repo, "worktree", "list")
    for line in existing.splitlines()[1:]:
        problems.append(f"stale worktree present: {line.split()[0]}")

    return problems


def create(repo: Path, branch: str, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    git(repo, "worktree", "add", "-b", branch, str(path))
    return path


def seed_import_cache(repo: Path, tree: Path) -> str:
    """Copy project/.godot into the fresh worktree so Godot imports only the new asset.

    ~65MB / 250 files. Without it every run re-imports all 365 project assets.
    VERIFY ON FIRST REAL RUN that this copy is path-independent; if Godot re-imports
    anyway, delete the copy and accept the cost rather than shipping a cache that lies.
    """
    src = repo / "project" / ".godot"
    if not src.is_dir():
        return "no import cache to seed"
    dst = tree / "project" / ".godot"
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    return f"seeded {sum(1 for _ in dst.rglob('*') if _.is_file())} cache files"


def abandon(repo: Path, path: Path, branch: str) -> None:
    git(repo, "worktree", "remove", "--force", str(path))
    git(repo, "branch", "-D", branch)


def selftest_cases(c) -> None:
    import subprocess, tempfile
    with tempfile.TemporaryDirectory() as td:
        repo = Path(td) / "repo"
        (repo / "project" / "data").mkdir(parents=True)
        (repo / "scripts").mkdir()
        (repo / "project" / "data" / "x.tres").write_text("a\n")
        (repo / "scripts" / "s.py").write_text("b\n")
        for args in (["init", "-b", "main"],
                     ["add", "."],
                     ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", "init"]):
            subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)

        c.eq(current_branch(repo), "main", "current branch read")
        c.eq(preflight(repo), [], "clean tracked tree passes preflight")

        (repo / "untracked.md").write_text("fine\n")
        c.eq(preflight(repo), [], "untracked files outside project/ and scripts/ are fine")

        (repo / "project" / "data" / "x.tres").write_text("changed\n")
        problems = preflight(repo)
        c.check(any("x.tres" in p for p in problems), "modified tracked file blocks preflight")
        subprocess.run(["git", "checkout", "--", "project"], cwd=repo, check=True,
                       capture_output=True)

        tree = create(repo, "asset/pig", repo / ".worktrees" / "asset-pig")
        c.check(tree.is_dir(), "worktree directory created")
        c.check((tree / "project" / "data" / "x.tres").is_file(), "worktree has the content")
        c.check("asset/pig" in git(repo, "branch", "--list", "asset/pig"), "branch created")
        c.eq(current_branch(repo), "main", "creating a worktree does not move the main checkout")

        (repo / "project" / ".godot").mkdir()
        (repo / "project" / ".godot" / "cache.bin").write_bytes(b"x" * 16)
        seed_import_cache(repo, tree)
        c.check((tree / "project" / ".godot" / "cache.bin").is_file(), "import cache seeded")

        c.check(any("asset-pig" in p for p in preflight(repo)),
                "a stale worktree of the same name is reported")

        abandon(repo, tree, "asset/pig")
        c.check(not tree.exists(), "abandon removes the worktree")
        c.eq(git(repo, "branch", "--list", "asset/pig").strip(), "", "abandon deletes the branch")
        c.eq((repo / "project" / "data" / "x.tres").read_text(), "a\n",
             "main checkout untouched by the whole cycle")
