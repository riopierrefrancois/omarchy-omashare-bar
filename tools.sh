#!/usr/bin/env bash
# Local-only bridge. All dynamic values are positional arguments, never shell code.
set -euo pipefail
case "${1:-}" in
  available)
    command -v omashare >/dev/null 2>&1
    ;;
  jobs)
    python3 - <<'PY'
import glob
import json
import os
import pathlib
import time

runtime = os.environ.get("XDG_RUNTIME_DIR")
directory = pathlib.Path(runtime, "omashare", "jobs") if runtime else pathlib.Path("/tmp", f"omashare-{os.getuid()}", "jobs")
jobs = []
for path in glob.glob(str(directory / "*.json"))[:128]:
    try:
        if os.path.getsize(path) > 16384:
            continue
        with open(path, encoding="utf-8") as handle:
            job = json.load(handle)
        if isinstance(job, dict) and job.get("state") in ("running", "done", "failed"):
            jobs.append(job)
    except (OSError, ValueError, UnicodeError):
        pass
print(json.dumps(jobs[:64]))
PY
    ;;
  pick)
    omarchy file select --title "Share a video" --extensions "mp4 mov mkv webm m4v"
    ;;
  upload)
    file=${2:?file required}
    # The process survives shell reloads; the CLI publishes its progress to job files.
    systemd-run --user --collect --quiet -- omashare --json upload "$file" >/dev/null
    ;;
  copy)
    printf '%s' "${2:?link required}" | wl-copy
    ;;
  *)
    echo 'usage: tools.sh available | jobs | pick | upload FILE | copy LINK' >&2
    exit 2
    ;;
esac
