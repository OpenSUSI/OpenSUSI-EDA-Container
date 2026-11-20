#!/usr/bin/env bash
# ==============================================================================
# Smoke test for OpenSUSI-EDA-Container
# Verifies OpenROAD, Yosys, KLayout, iverilog/vvp, ngspice, and Python3
# ==============================================================================
set -euo pipefail

echo "=== Smoke Test: Checking EDA Tool Binaries ==="
for tool in openroad yosys iverilog vvp klayout ngspice python3; do
    command -v "${tool}" >/dev/null 2>&1 || { echo "FAIL: missing ${tool}" >&2; exit 1; }
    echo "  OK: $(command -v "${tool}")"
done

echo "=== Smoke Test: Version Metadata ==="
cat /etc/opensusi-eda-versions.json

TMPD="$(mktemp -d)"
trap 'rm -rf "${TMPD}"' EXIT

echo "=== Smoke Test: iverilog + vvp ==="
cat > "${TMPD}/t.v" <<'EOF'
module t; initial begin $display("IVERILOG_OK"); $finish; end endmodule
EOF
iverilog -o "${TMPD}/t.vvp" "${TMPD}/t.v"
vvp "${TMPD}/t.vvp" | grep -q "IVERILOG_OK"

echo "=== Smoke Test: yosys ==="
yosys -q -p "read_verilog ${TMPD}/t.v; stat"

echo "=== Smoke Test: openroad ==="
openroad -exit /dev/null >/dev/null 2>&1 || openroad -version

echo "=== Smoke Test: klayout (headless batch + pya) ==="
cat > "${TMPD}/k.py" <<'EOF'
import pya
l = pya.Layout()
c = l.create_cell("TOP")
print("KLAYOUT_PYA_OK", c.name)
EOF
klayout -b -r "${TMPD}/k.py" | grep -q "KLAYOUT_PYA_OK"

echo "=== Smoke Test: ngspice (batch DC operating point) ==="
cat > "${TMPD}/rc.sp" <<'EOF'
* Simple resistive divider smoke test
V1 in 0 DC 5.0
R1 in out 1k
R2 out 0 1k
.op
.control
run
print v(out)
quit
.endc
.end
EOF
ngspice -b "${TMPD}/rc.sp" | tee "${TMPD}/ngspice.log" | grep -q "v(out)"

echo "=== ALL SMOKE TESTS PASSED ==="
