#!/usr/bin/env python3
"""Measure CPU time over a fixed interval (100% = one fully occupied core)."""
import argparse
import datetime
import json
import subprocess
import time
from pathlib import Path


def cpu_seconds(pid):
    value = subprocess.check_output(
        ["/bin/ps", "-p", str(pid), "-o", "time="], text=True
    ).strip()
    if not value:
        raise RuntimeError(f"Process {pid} exited")
    days, value = value.split("-", 1) if "-" in value else ("0", value)
    result = 0.0
    for part in value.split(":"):
        result = result * 60 + float(part)
    return int(days) * 86400 + result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", required=True, type=int)
    parser.add_argument("--seconds", type=float, default=20)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error("--seconds must be positive")
    started = datetime.datetime.now().astimezone().isoformat()
    start_cpu = cpu_seconds(args.pid)
    start_time = time.monotonic()
    time.sleep(args.seconds)
    end_cpu = cpu_seconds(args.pid)
    elapsed = time.monotonic() - start_time
    report = {
        "started": started,
        "pid": args.pid,
        "elapsed_seconds": round(elapsed, 3),
        "cpu_seconds": round(end_cpu - start_cpu, 3),
        "average_cpu_percent": round((end_cpu - start_cpu) / elapsed * 100, 2),
        "scale": "100% = one CPU core",
    }
    rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered)
    print(rendered, end="")


if __name__ == "__main__":
    main()
