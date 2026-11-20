#!/usr/bin/env bash
# ==============================================================================
# Emit pinned EDA tool versions as JSON (saved to /etc/opensusi-eda-versions.json)
# ==============================================================================
set -euo pipefail

get_ver() {
    local cmd="$1"
    eval "${cmd}" 2>&1 | head -n 1 | tr -d '\r' || echo "unavailable"
}

python3 - <<'PY'
import json, os, subprocess

def run(cmd):
    try:
        p = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15)
        for line in p.stdout.splitlines():
            s = line.strip()
            if s:
                return s
        return "unknown"
    except Exception as e:
        return f"error: {e}"

data = {
    "container_version": os.environ.get("OPENSUSI_EDA_CONTAINER_VERSION", "dev"),
    "tools": {
        "openroad": run("openroad -version"),
        "yosys": run("yosys -V"),
        "klayout": run("klayout -v"),
        "iverilog": run("iverilog -V"),
        "ngspice": run("ngspice -v | grep -i ngspice | head -n 1"),
        "python3": run("python3 --version"),
        "gcloud": run("gcloud --version | head -n 1") if os.system("command -v gcloud >/dev/null 2>&1") == 0 else "not-installed",
    },
}
print(json.dumps(data, indent=2))
PY
