# go-cache-cleanup

Keeps Go build caches from filling the disk on a Mac. Every Git worktree of a
large Go repo builds its own copy of the code into the build cache (the
package directory is part of the cache key), so parallel agents and worktrees
can add 10–20 GiB per hour.

Two parts:

- **launchd job** (`bin/go-cache-trim`): every 15 minutes it checks free space
  on `/System/Volumes/Data`. Above the minimum (10 GiB by default) it only
  logs `ok`. Below it, it trims Go build caches in stages and stops as soon as
  free space is back over the minimum:
  1. entries unused for 24 hours,
  2. entries unused for 6 hours,
  3. entries unused for 1 hour,
  4. the whole caches (`go clean -cache`).

  It covers the default cache (`~/Library/Caches/go-build`) and agent caches
  in `/private/tmp` named `*-go-build` or `*-gocache`. If free space is still
  low after stage 4, the log says something else is filling the disk.
- **`go-cache-cleanup` skill** (`skills/go-cache-cleanup/SKILL.md`): a Claude
  Code (and Codex) skill that a session runs on its own when it sees
  "no space left on device" or low free space. It clears the same caches,
  reports free space before and after, and asks before touching the Go module
  cache.

## Requirements

- macOS
- Go in `PATH` when you run the install

## Set up

```bash
git clone git@github.com:matkaras/go-cache-cleanup.git ~/Personal/go-cache-cleanup
cd ~/Personal/go-cache-cleanup
./launchd.sh install
```

`install` does this:

1. Links `~/.local/bin/go-cache-trim` to `bin/go-cache-trim`.
2. Links `~/.claude/skills/go-cache-cleanup` to `skills/go-cache-cleanup`.
   If `~/.codex/skills` is a link to `~/.claude/skills`, Codex sees the skill
   too. New sessions pick it up; running ones do not.
3. Writes `~/Library/LaunchAgents/com.matkaras.go-cache-trim.plist` with your
   Go directory in `PATH` (launchd starts jobs with a minimal `PATH`).
4. Loads the job and runs it once.

The links point into this clone, so a `git pull` updates the script and the
skill. Run `./launchd.sh install` again after moving the clone or Go.

If `~/.local/bin/go-cache-trim` or `~/.claude/skills/go-cache-cleanup` already
exists as a regular file or directory, `install` stops. Move it away and run
`install` again.

To keep a different minimum:

```bash
MIN_FREE_GIB=20 ./launchd.sh install
```

## Check that it works

```bash
./launchd.sh status
```

It prints the launchd state, the run count, the last exit code, and the last
lines of `~/.local/state/go-cache-trim/trim.log`. A healthy job logs a line
every 15 minutes:

```text
2026-10-20 20:28:02 ok free=71G
```

To try the stages without a low disk, point it at a throwaway
cache and force a high minimum. It deletes that cache:

```bash
GOCACHE=/tmp/test-cache TMP_CACHES=/tmp/none MIN_FREE_GIB=100000 bin/go-cache-trim
```

## Why fixed times

The job uses `StartCalendarInterval` (minutes 0, 15, 30, 45), not
`StartInterval`. `StartInterval` counts only awake time, so on a laptop that
sleeps a lot it can go days without a run. A calendar run missed during sleep
runs right after wake.

## Remove

```bash
./launchd.sh uninstall
```

This unloads the job and removes the plist and both links. The log stays in
`~/.local/state/go-cache-trim/`.
