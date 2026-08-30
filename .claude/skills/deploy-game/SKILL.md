---
name: deploy-game
description: Use when asked to deploy the game, publish the web build, refresh web/game/, or run /deploy-game. Builds the single-threaded Godot Web export in release mode and copies it into web/game/.
---

This is a build tool and nothing else. It builds the web export and copies it into place.

**It never touches a web server.** Do not check whether one is running, do not start one,
do not kill or restart one, do not report a URL. Serving is deliberately kept separate —
`scripts/serve-web-build.sh` is the operator's to run.

Run this entirely inline. Do not dispatch an agent — both steps are shell commands with a
deterministic outcome, and a subagent adds cost without adding judgment.

`/deploy-game` takes no arguments. If one is passed, ignore it and say so in the output.

## Procedure

### 1. Build

```bash
bash scripts/build-game.sh web-singlethread release 2>&1 | tee /tmp/claude/deploy-game-build.log | tail -20
```

Release, not debug — this is a deploy, so it should be what a player would actually get.
The script's own default is debug; pass `release` explicitly every time.

Keep the full log. Step 1b greps it, and `tail` alone would hide errors that scroll past.

This takes several minutes (a ~38MB wasm and ~33MB pck). Run it in the foreground with a
generous timeout, or in the background and wait for it once — do not poll with `sleep`.

### 1b. Check for `ERROR:` lines — a zero exit code is NOT enough

```bash
grep -c '^ERROR:' /tmp/claude/deploy-game-build.log
```

**`build-game.sh` exits 0 even when the export is broken.** Godot's exporter writes
`project.binary` (the compiled project settings, without which the game will not boot) to a
temp file first, then packs it. If that write fails, the export still reports
`savepack | Storing File: res://project.binary`, still prints `==> Done`, and still exits 0
— having packed a file that was never written. The only signal is `ERROR:` lines in the
build output.

So: **if the count is not 0, stop.** Report the matching lines verbatim and do not copy. A
half-deployed `web/game/` is worse than a stale one. Same if the exit code is non-zero.

The known cause of this is the Bash sandbox. Godot 4.7 writes `/tmp/tmpproject.binary`, and
`OS.get_temp_dir()` hardcodes `/tmp` on Linux — `TMPDIR` does not redirect it (verified
against the 4.7 binary). The sandbox permits writes only under `/tmp/claude`, so the write
fails.

Which means:

- If `.claude/settings.json` grants `sandbox.filesystem.allowWrite: ["/tmp"]`, the build
  runs sandboxed and clean. **Check for that entry before building.**
- If it does not, run step 1 with `dangerouslyDisableSandbox: true` and say so in the
  output. Do not silently accept the sandboxed build — verify step 1b either way.

A grant narrower than `/tmp` does not work: bubblewrap cannot bind a path that does not
exist yet, and Godot deletes `tmpproject.binary` after each export, so a single-file
`allowWrite` entry is inert. Tested — do not re-litigate it.

A separate `ERROR: Cannot save file '~/.config/godot/editor_settings-4.7.tres'` is cosmetic
and does not affect the export. It is the one `ERROR:` line safe to ignore; say so rather
than blocking on it.

### 2. Copy into web/game/

```bash
rm -rf web/game && mkdir -p web/game && cp -r builds/web-singlethread/. web/game/
```

Wipe first. A plain `cp` over the old directory leaves orphaned files from a previous
export sitting next to the new ones.

The trailing `/.` matters — it copies the *contents* of the build dir, not the dir itself.
`web/index.html`'s "Play Now" button points at `./game/index.html`, which is exactly what
this produces.

Confirm with `ls web/game/index.html` before reporting success.

## Report format

Report, in this order:

1. **Build** — target, mode, whether it ran sandboxed, and the `ERROR:` count (or the
   failure, verbatim).
2. **Copied** — `builds/web-singlethread/` → `web/game/`, and the file count.
3. **Changed paths** — list them. **Run no git commands** (project rule: the human runs all
   git). `builds/` is gitignored; `web/game/` is **not** — mention once, when you create it,
   that it is ~70MB of build output and the operator may want a `.gitignore` entry.
   `project/scripts/build_info.gd` also changes every build; that is by design.

Do not add a line about servers, ports, or URLs.

## Common mistakes

| Mistake | Why it's wrong |
|---|---|
| Treating exit 0 as a successful build | The export packs a `project.binary` it failed to write and still exits 0. Grep for `ERROR:`. |
| Piping the build through `tail` only | Hides the errors, which appear well before the final lines. `tee` a full log, then grep it. |
| Setting `TMPDIR` to dodge the `/tmp` write | `OS.get_temp_dir()` ignores it — hardcoded `/tmp` on Linux. |
| Skipping `release` | `build-game.sh` defaults to debug; a debug wasm is not what ships. |
| `cp -r builds/web-singlethread web/game/` | Nests it at `web/game/web-singlethread/`. Use the trailing `/.` form after an `rm -rf`. |
| Copying after a failed or error-laden build | Ships a broken export under a "deployed" banner. |
| Checking on, starting, or restarting a server | Out of scope. This skill builds and copies; that is all. |
