---
name: go-cache-cleanup
description: Free disk space on this Mac by clearing Go build caches. Use when the disk runs low: "no space left on device", a Go build or test fails writing its cache, or `df` shows under 10 GiB free on /System/Volumes/Data.
---

# Go cache cleanup

Go build caches are the fastest-growing disk consumer here: every n9 worktree builds its own copy of n9, so agents can add 10–20 GiB per hour. A cache is always safe to drop; the only cost is slower next builds.

## Steps

1. **Measure.** Record free space and every Go build cache:

   ```bash
   df -h /System/Volumes/Data | tail -1
   du -sh "$(go env GOCACHE)"
   find /private/tmp -maxdepth 1 -type d \( -name '*-go-build' -o -name '*-gocache' \) -exec du -sh {} +
   ```

   The `/private/tmp` ones are separate `GOCACHE` dirs that agents create when the default cache is not writable.

2. **Clear the build caches.** Clear each one with Go itself, so the cache layout stays valid:

   ```bash
   go clean -cache
   find /private/tmp -maxdepth 1 -type d \( -name '*-go-build' -o -name '*-gocache' \) -exec env GOCACHE={} go clean -cache \;
   ```

   A Go build running at the same moment in another session may fail on a missing cache entry; it succeeds on rerun. In Codex, only `~/Library/Caches/go-build` is a writable root, so the `/private/tmp` caches need sandbox escalation.

3. **Report.** Run `df -h /System/Volumes/Data | tail -1` again and report free space before and after, plus how much each cache held. Done when every cache from step 1 is cleared and the numbers are reported.

## Beyond build caches

The Go module cache (`~/go/pkg/mod`, ~50 GiB, cleared with `go clean -modcache`) forces every module to download again, so clear it only after the user says yes. For anything else on the disk, report the biggest consumers and let the user decide.

## Background trim

A launchd job (`~/Library/LaunchAgents/com.matkaras.go-cache-trim.plist`) runs `~/.local/bin/go-cache-trim` every 15 minutes. It keeps at least 10 GiB free by trimming the default cache and the `/private/tmp` caches in stages (entries unused for 24h, 6h, 1h, then the whole caches) and logs each run to `~/.local/state/go-cache-trim/trim.log`. If the disk filled up anyway, read the log tail and include it in the report: it shows whether the job runs, and a "still under" line means something other than the Go build cache is filling the disk.
