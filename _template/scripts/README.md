# scripts/ — mechanical ingest

These ship inside the KB so it stays self-contained and splittable. Detection is a pure
script (no LLM, no cost); the actual ingest invokes Claude Code headlessly.

> **Run these where `raw/` actually resolves — your real machine, not a container or
> remote sandbox.** Sources are often symlinks to local mounts (shared drives, OneDrive,
> etc.). Inside a container those symlinks are broken, so a scan there fingerprints
> *emptiness* and an ingest captures nothing. Sanity check: if
> `find -L raw/<source> -type f | wc -l` is `0` for a source you know has files, the mount
> isn't present — you're in the wrong place.

## `scan.sh` — detect changes

Walks `raw/`, fingerprints each source (following symlinks into living drives), and diffs
against `.ingest/manifest.tsv`. Writes the queue to `.ingest/pending.md`.

```sh
./scripts/scan.sh          # detect; exit 0 = clean, 10 = changes pending
./scripts/scan.sh --accept # advance the baseline to current state (used after ingest)
```

This is also the drift check the Lint workflow calls — it covers files, directories, and
living symlink targets in one pass.

## `ingest-new.sh` — detect + ingest

```sh
./scripts/ingest-new.sh            # supervised: scan, then ingest pending via Claude Code
./scripts/ingest-new.sh --dry-run  # show what would run; no LLM, no changes
./scripts/ingest-new.sh --auto     # unattended permissions — for cron / launchd
```

If `claude` isn't on your PATH: `CLAUDE_BIN=/full/path/to/claude ./scripts/ingest-new.sh`.

On success it advances `.ingest/manifest.tsv` and commits. The manifest only advances when
the ingest run exits cleanly, so an interrupted run leaves the queue intact for next time.

## Opt-in auto-ingest

Enable this once you trust the supervised flow. Both options run `ingest-new.sh --auto` on
a cadence; runs where `raw/` hasn't changed do nothing (detection is free). Replace
`KBPATH` with this KB's absolute path.

> Auto mode runs Claude Code with `--permission-mode bypassPermissions` so it can write
> unattended. Only enable it when you're comfortable with what supervised runs produce.

### macOS (launchd)

Save as `~/Library/LaunchAgents/dev.example.{{KB_NAME}}-ingest.plist`, then load it. Runs
daily at 07:00:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key>            <string>dev.example.{{KB_NAME}}-ingest</string>
  <key>ProgramArguments</key> <array>
    <string>/bin/bash</string>
    <string>KBPATH/scripts/ingest-new.sh</string>
    <string>--auto</string>
  </array>
  <key>StartCalendarInterval</key> <dict>
    <key>Hour</key><integer>7</integer><key>Minute</key><integer>0</integer>
  </dict>
  <key>StandardOutPath</key>   <string>KBPATH/.ingest/auto.log</string>
  <key>StandardErrorPath</key> <string>KBPATH/.ingest/auto.log</string>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
</dict></plist>
```

```sh
launchctl load   ~/Library/LaunchAgents/dev.example.{{KB_NAME}}-ingest.plist
launchctl unload ~/Library/LaunchAgents/dev.example.{{KB_NAME}}-ingest.plist
```

### Linux (cron)

```cron
# daily at 07:00 — ingest anything new in this KB
0 7 * * * cd KBPATH && /bin/bash scripts/ingest-new.sh --auto >> .ingest/auto.log 2>&1
```
