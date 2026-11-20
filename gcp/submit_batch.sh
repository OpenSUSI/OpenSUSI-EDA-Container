#!/usr/bin/env bash
# ==============================================================================
# Submit an OpenSUSI EDA Design Repository Snapshot to GCP Cloud Batch
#
# Usage:
#   ./gcp/submit_batch.sh \
#     --repo-dir ../JSC-130E_MPW_template \
#     --project opensusi-eda-platform \
#     --region asia-northeast1 \
#     --bucket gs://opensusi-mpw-artifacts \
#     --image asia-northeast1-docker.pkg.dev/opensusi-eda-platform/eda/opensusi-eda:v0.1.0 \
#     --service-account eda-batch-worker@opensusi-eda-platform.iam.gserviceaccount.com \
#     [--pdk-uri gs://opensusi-pdks/jsc130e/v1.tar.gz] \
#     [--machine-type n2-standard-4] \
#     [--spot] \
#     [--wait]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_JSON="${SCRIPT_DIR}/batch-job.json.tpl"

REPO_DIR="."
GCP_PROJECT=""
GCP_REGION="asia-northeast1"
GCS_BUCKET=""
EDA_CONTAINER_IMAGE=""
BATCH_SERVICE_ACCOUNT=""
GCS_PDK_URI=""
FLOW_CMD="bash flow/run_all.sh"
MACHINE_TYPE="e2-standard-4"
CPU_MILLI="4000"
MEMORY_MIB="14336"
BOOT_DISK_MIB="30720"
MAX_RUN_DURATION="3600s"
PROVISIONING_MODEL="SPOT"
MAX_RETRY_COUNT="1"
WAIT_FOR_COMPLETION="false"
JOB_ID=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --repo-dir)        REPO_DIR="$2"; shift 2 ;;
        --project)         GCP_PROJECT="$2"; shift 2 ;;
        --region)          GCP_REGION="$2"; shift 2 ;;
        --bucket)          GCS_BUCKET="${2%/}"; shift 2 ;;
        --image)           EDA_CONTAINER_IMAGE="$2"; shift 2 ;;
        --service-account) BATCH_SERVICE_ACCOUNT="$2"; shift 2 ;;
        --pdk-uri)         GCS_PDK_URI="$2"; shift 2 ;;
        --flow-cmd)        FLOW_CMD="$2"; shift 2 ;;
        --machine-type)    MACHINE_TYPE="$2"; shift 2 ;;
        --cpu-milli)       CPU_MILLI="$2"; shift 2 ;;
        --memory-mib)      MEMORY_MIB="$2"; shift 2 ;;
        --max-duration)    MAX_RUN_DURATION="$2"; shift 2 ;;
        --standard)        PROVISIONING_MODEL="STANDARD"; shift ;;
        --spot)            PROVISIONING_MODEL="SPOT"; shift ;;
        --job-id)          JOB_ID="$2"; shift 2 ;;
        --wait)            WAIT_FOR_COMPLETION="true"; shift ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

for req in GCP_PROJECT GCS_BUCKET EDA_CONTAINER_IMAGE BATCH_SERVICE_ACCOUNT; do
    if [[ -z "${!req}" ]]; then
        echo "ERROR: Missing required argument for ${req}." >&2
        exit 2
    fi
done

REPO_ABS="$(cd "${REPO_DIR}" && pwd)"
REPO_NAME="$(basename "${REPO_ABS}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
GIT_SHA="$(git -C "${REPO_ABS}" rev-parse --short HEAD 2>/dev/null || echo "local")"
JOB_ID="${JOB_ID:-eda-${REPO_NAME:0:24}-${GIT_SHA}-${STAMP}}"
JOB_ID="$(echo "${JOB_ID}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | cut -c1-63 | sed 's/-$//')"

GCS_JOB_PREFIX="${GCS_BUCKET}/jobs/${REPO_NAME}/${JOB_ID}"
GCS_INPUT_URI="${GCS_JOB_PREFIX}/input/repo.tar.gz"
GCS_OUTPUT_URI="${GCS_JOB_PREFIX}/output"

TMPD="$(mktemp -d)"
trap 'rm -rf "${TMPD}"' EXIT

echo "=== [1/3] Archiving & staging design repository to ${GCS_INPUT_URI} ==="
tar -czf "${TMPD}/repo.tar.gz" \
    --exclude='.git' \
    --exclude='output/work' \
    --exclude='output/package' \
    --exclude='output/gds/*' \
    --exclude='output/reports/*' \
    --exclude='output/logs/*' \
    -C "${REPO_ABS}" .

gcloud storage cp "${TMPD}/repo.tar.gz" "${GCS_INPUT_URI}"

echo "=== [2/3] Rendering Cloud Batch job spec (${JOB_ID}) ==="
LABEL_REPO="${REPO_NAME:0:60}"
LABEL_PDK="$(python3 -c '
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / "design.yaml"
if p.exists():
    for line in p.read_text().splitlines():
        if line.strip().startswith("name:") and "tr1um" in line or "jsc130e" in line:
            print(line.split(":",1)[1].strip().strip("\"\x27"))
            break
    else:
        print("unknown")
else:
    print("unknown")
' "${REPO_ABS}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]//g')"

export EDA_CONTAINER_IMAGE CPU_MILLI MEMORY_MIB BOOT_DISK_MIB MAX_RETRY_COUNT
export MAX_RUN_DURATION GCS_INPUT_URI GCS_OUTPUT_URI GCS_PDK_URI FLOW_CMD
export MACHINE_TYPE PROVISIONING_MODEL BATCH_SERVICE_ACCOUNT LABEL_REPO LABEL_PDK

python3 - "${TEMPLATE_JSON}" "${TMPD}/batch-job.json" <<'PY'
import os, re, sys
from pathlib import Path

tpl = Path(sys.argv[1]).read_text(encoding="utf-8")
def repl(m):
    key = m.group(1)
    return os.environ.get(key, "")
out = re.sub(r"\$\{([A-Z0-9_]+)\}", repl, tpl)
Path(sys.argv[2]).write_text(out, encoding="utf-8")
PY

echo "=== [3/3] Submitting Cloud Batch job ${JOB_ID} (project=${GCP_PROJECT}, region=${GCP_REGION}) ==="
gcloud batch jobs submit "${JOB_ID}" \
    --project="${GCP_PROJECT}" \
    --location="${GCP_REGION}" \
    --config="${TMPD}/batch-job.json"

echo "Submitted: ${JOB_ID}"
echo "Outputs  : ${GCS_OUTPUT_URI}"

if [[ "${WAIT_FOR_COMPLETION}" == "true" ]]; then
    echo "Waiting for Cloud Batch job completion..."
    while true; do
        STATE="$(gcloud batch jobs describe "${JOB_ID}" \
            --project="${GCP_PROJECT}" \
            --location="${GCP_REGION}" \
            --format='value(status.state)')"
        echo "  [$(date -u +%H:%M:%S)] state=${STATE}"
        case "${STATE}" in
            SUCCEEDED)
                echo "Cloud Batch job SUCCEEDED."
                gcloud storage cp "${GCS_OUTPUT_URI}/reports/summary.json" "${TMPD}/summary.json" && cat "${TMPD}/summary.json"
                exit 0
                ;;
            FAILED|DELETION_IN_PROGRESS)
                echo "ERROR: Cloud Batch job ended with state=${STATE}" >&2
                gcloud storage cp "${GCS_OUTPUT_URI}/reports/summary.json" "${TMPD}/summary.json" 2>/dev/null && cat "${TMPD}/summary.json" || true
                exit 1
                ;;
        esac
        sleep 15
    done
fi
