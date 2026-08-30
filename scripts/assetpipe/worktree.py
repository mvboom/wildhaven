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
                 "add", "checkout", "symbolic-ref", "ls-files"}

WATCHED_DIRS = ("project", "scripts")


def git(repo: Path, *args: str) -> str:
    verb = next((a for a in args if not a.startswith("-") and "=" not in a), "")
    if verb not in ALLOWED_VERBS:
        raise RuntimeError(
            f"git verb {verb!r} is not authorised for this pipeline "
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

    # Ask git what it TRACKS under project/, rather than inferring from status output.
    # An earlier version gated an --untracked-files=all check on the normal-mode call being
    # empty, which is unreachable: if project/ were untracked, the normal-mode call would
    # itself print "?? project/" and never be empty. `ls-files` answers the real question
    # directly -- no tracked files under project/ means worktree isolation cannot work.
    if not git(repo, "ls-files", "project").strip():
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


class MainBranchRefused(RuntimeError):
    """Raised instead of merging into main.

    .claude/CLAUDE.md gates "merging to main / committing directly on main" as a human
    decision. The operator's local-git authorisation for this pipeline does not lift that
    gate, so approve halts here and hands back the ready branch.
    """


def commit_all(tree: Path, message: str) -> str:
    git(tree, "add", "-A")
    git(tree, "-c", "user.email=asset-pipeline@local",
        "-c", "user.name=asset-pipeline", "commit", "-m", message)
    return git(tree, "rev-parse", "HEAD").strip()


def merge(repo: Path, branch: str, target: str) -> str:
    """Merge locally, or restore the repo exactly as it was.

    This runs against the OPERATOR'S REAL REPOSITORY, so a merge that fails after the
    checkout succeeded must not strand them on an unexpected branch with a conflicted
    merge in progress. On any failure we abort the merge and return to the branch they
    were on, then re-raise.
    """
    if target == "main":
        raise MainBranchRefused(
            f"branch {branch} is ready, but this pipeline will not merge into main. "
            f"Merge it yourself, or re-run from a feature branch.")
    original = current_branch(repo)
    if original != target:
        git(repo, "checkout", target)
    try:
        git(repo, "merge", "--no-ff", branch, "-m", f"merge {branch}")
    except RuntimeError:
        try:
            git(repo, "merge", "--abort")
        except RuntimeError:
            pass  # nothing to abort: the merge failed before it started one
        if original != target:
            git(repo, "checkout", original)
        raise
    return git(repo, "rev-parse", "HEAD").strip()


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

    # Regression coverage for the dead-code bug: an earlier version's untracked-project/
    # check was gated on a git-status call that could never be empty when project/ was truly
    # untracked, so it never fired. This exercises the real condition in a fresh repo where
    # project/ exists on disk but nothing under it is tracked.
    with tempfile.TemporaryDirectory() as td2:
        repo2 = Path(td2) / "repo2"
        repo2.mkdir(parents=True)
        (repo2 / "README.md").write_text("hi\n")
        for args in (["init", "-b", "main"],
                     ["add", "README.md"],
                     ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", "init"]):
            subprocess.run(["git", *args], cwd=repo2, check=True, capture_output=True)

        (repo2 / "project" / "data").mkdir(parents=True)
        (repo2 / "project" / "data" / "y.tres").write_text("z\n")

        problems = preflight(repo2)
        c.check(any("project/" in p for p in problems),
                "untracked project/ is caught by preflight")

        subprocess.run(["git", "add", "project"], cwd=repo2, check=True, capture_output=True)
        subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t",
                        "commit", "-m", "track project"], cwd=repo2, check=True,
                       capture_output=True)
        c.check(not any("project/" in p for p in preflight(repo2)),
                "tracked project/ is no longer flagged")

    with tempfile.TemporaryDirectory() as td:
        repo = Path(td) / "repo"
        (repo / "project").mkdir(parents=True)
        (repo / "project" / "a.tres").write_text("one\n")
        for args in (["init", "-b", "main"], ["add", "."],
                     ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", "init"]):
            subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)

        tree = create(repo, "asset/well", repo / ".worktrees" / "asset-well")
        (tree / "project" / "b.tres").write_text("two\n")
        commit_all(tree, "feat: add well")

        raised = False
        try:
            merge(repo, "asset/well", "main")
        except MainBranchRefused as exc:
            raised = True
            c.check("asset/well" in str(exc), "refusal names the ready branch")
        c.check(raised, "merging into main is refused")
        c.check(not (repo / "project" / "b.tres").is_file(),
                "refused merge left main untouched")

        subprocess.run(["git", "checkout", "-b", "feature/x"], cwd=repo, check=True,
                       capture_output=True)
        merge(repo, "asset/well", "feature/x")
        c.check((repo / "project" / "b.tres").is_file(), "merge into a feature branch lands")

        blocked = False
        try:
            git(repo, "push", "origin", "main")
        except RuntimeError as exc:
            blocked = "not authorised" in str(exc)
        c.check(blocked, "push is refused by the verb guard")

    with tempfile.TemporaryDirectory() as td:
        repo = Path(td) / "repo"
        repo.mkdir(parents=True)
        (repo / "conflict.tres").write_text("base\n")
        for args in (["init", "-b", "main"], ["add", "."],
                     ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", "init"]):
            subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)

        subprocess.run(["git", "checkout", "-b", "asset/conflict"], cwd=repo, check=True,
                       capture_output=True)
        (repo / "conflict.tres").write_text("asset-version\n")
        subprocess.run(["git", "add", "."], cwd=repo, check=True, capture_output=True)
        subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t",
                        "commit", "-m", "asset change"], cwd=repo, check=True,
                       capture_output=True)

        subprocess.run(["git", "checkout", "main"], cwd=repo, check=True,
                       capture_output=True)
        subprocess.run(["git", "checkout", "-b", "feature/target"], cwd=repo, check=True,
                       capture_output=True)
        (repo / "conflict.tres").write_text("target-version\n")
        subprocess.run(["git", "add", "."], cwd=repo, check=True, capture_output=True)
        subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t",
                        "commit", "-m", "target change"], cwd=repo, check=True,
                       capture_output=True)

        subprocess.run(["git", "checkout", "asset/conflict"], cwd=repo, check=True,
                       capture_output=True)

        conflicted = False
        try:
            merge(repo, "asset/conflict", "feature/target")
        except RuntimeError:
            conflicted = True
        c.check(conflicted, "a genuine conflict raises")
        c.eq(current_branch(repo), "asset/conflict",
             "failed merge restores the branch we started on")
        c.check(not (repo / ".git" / "MERGE_HEAD").exists(),
                "failed merge leaves no merge in progress")
