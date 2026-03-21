# slipstream-thresholds.sh — single source of truth for per-module thresholds.
# Source this file; do not execute it directly.
#
# To change a threshold, edit only this file. All hooks and the cron prompt
# read from here so values stay in sync automatically.

THRESHOLD_PERMISSIONS=5
THRESHOLD_COMPACTIONS=3
THRESHOLD_ERRORS=3
THRESHOLD_READS=10
THRESHOLD_CORRECTIONS=2
THRESHOLD_MEMORY=2
THRESHOLD_COMMANDS=3

# Time-based threshold: recommend a module if it has any new data and the
# last review was more than this many days ago.
TIME_THRESHOLD_DAYS=7
