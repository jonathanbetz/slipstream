# Slipstream Tests

## Requirements

- [bats-core](https://github.com/bats-core/bats-core) >= 1.7

```bash
# macOS
brew install bats-core

# Ubuntu / Debian
sudo apt-get install bats

# From source
git clone https://github.com/bats-core/bats-core.git
cd bats-core && ./install.sh /usr/local
```

## Running

From the repo root:

```bash
bats tests/slipstream.bats
```

Or with verbose output:

```bash
bats --verbose-run tests/slipstream.bats
```

## What's covered

| Group | Tests |
|-------|-------|
| Capture scripts produce valid JSON | Permission, compaction, errors, reads (Read + Glob), skips non-Read/Glob |
| Malformed JSON handling | All 4 capture scripts exit 0, log to errors.log, don't write to .jsonl |
| Empty / missing .cursor.json | check-triggers exits 0, produces no output |
| Negative new-event counts | Treated as 0, no false recommendation |
| Trigger thresholds | Permissions and errors: below/at/above threshold |
| Thresholds single source of truth | All variables defined; cron prompt uses real values |
| Concurrent writes (flock) | 10 parallel writes produce exactly 10 valid JSON lines |
| install.sh | Creates backups directory |

## Design notes

Each test runs with a temporary `$HOME` (`mktemp -d`) so tests never touch the real
`~/.slipstream` directory. The `teardown` function removes the temp dir after each test.

Hook scripts are made executable at setup time so the test environment matches a
freshly installed Slipstream.
