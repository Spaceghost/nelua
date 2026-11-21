#!/usr/bin/env python3
"""Time fresh Nelua processes and check their outputs under identical paths.

Build both checkouts with make first. Example on Linux:
  taskset -c 3 python3 tools/bench-frontend.py ../baseline . --rounds 15 > samples.csv
"""
import argparse
import csv
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


def prepare(source, stage):
    stage.mkdir()
    for name in ("nelua", "nelua-lua"):
        shutil.copy2(source / name, stage / name)
    for name in ("lualib", "lib", "examples", "tests"):
        shutil.copytree(source / name, stage / name)
    with (stage / "checked-module.nelua").open("w") as fixture:
        fixture.write("local function checked(x: integer): integer\n")
        for i in range(1, 2049):
            fixture.write(f"  assert(x ~= -{i})\n")
        fixture.write("  return x\nend\nprint(checked(7))\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--rounds", type=int, default=15)
    args = parser.parse_args()
    if args.rounds < 1:
        parser.error("--rounds must be positive")
    workloads = [("-c", "examples/helloworld.nelua"), ("-c", "examples/matmul.nelua"),
                 ("-c", "tests/all_test.nelua"), ("-c", "checked-module.nelua"),
                 ("--lint", "examples/syntax_tour.nelua")]
    with tempfile.TemporaryDirectory(prefix="nelua-frontend-") as tmp:
        root = Path(tmp).resolve()
        active, output = root / "active", root / "output.c"
        stages = {"baseline": root / "baseline", "candidate": root / "candidate"}
        prepare(args.baseline, stages["baseline"])
        prepare(args.candidate, stages["candidate"])
        # Nelua uses source paths when naming generated symbols. The two
        # private staging trees take turns occupying exactly the same path.
        cache = str(root / "cache")
        expected = {}
        writer = csv.writer(sys.stdout, lineterminator="\n")
        writer.writerow(["round", "mode", "workload", "position", "version", "elapsed_ns", "output_bytes"])
        for rep in range(args.rounds + 1):
            for index in range(len(workloads)):
                case = (index + rep) % len(workloads)
                mode, workload = workloads[case]
                versions = list(stages)
                if (rep + case) % 2:
                    versions.reverse()
                for position, version in enumerate(versions, 1):
                    stage = stages[version]
                    stage.rename(active)
                    try:
                        output.unlink(missing_ok=True)
                        command = [str(active / "nelua"), "--cache-dir", cache, mode, workload]
                        if mode == "-c":
                            command.extend(["-o", str(output)])
                        start = time.perf_counter_ns()
                        run = subprocess.run(command, cwd=active, check=True,
                                             stdout=subprocess.PIPE)
                        elapsed = time.perf_counter_ns() - start
                        generated = output.read_bytes() if mode == "-c" else run.stdout
                        digest = hashlib.sha256(generated).digest()
                        if digest != expected.setdefault((mode, workload), digest):
                            raise RuntimeError(f"output differs for {workload} ({version})")
                        if rep:  # round zero warms the filesystem and compiler probe
                            writer.writerow([rep, mode, workload, position, version, elapsed, len(generated)])
                            sys.stdout.flush()
                    finally:
                        active.rename(stage)


if __name__ == "__main__":
    main()
