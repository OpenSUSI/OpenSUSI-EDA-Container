#!/usr/bin/env bash
# ==============================================================================
# OpenSUSI EDA Container Entrypoint
#
# Modes:
#   1) Local / Interactive mode (default, when GCS_INPUT_URI is unset):
#      Executes the passed command directly in WORKDIR (/work).
#      Example:
#        docker run --rm -v "$PWD:/work" opensusi-eda bash flow/run_all.sh
#
#   2) GCP Cloud Batch mode (when GCS_INPUT_URI and GCS_OUTPUT_URI are set):
#      - Downloads input snapshot tarball from GCS_INPUT_URI to local /work
#      - Optionally downloads PDK overlay from GCS_PDK_URI (if provided)
#      - Executes FLOW_CMD (default: "bash flow/run_all.sh") on local fast disk
#      - Always uploads output/ (logs, reports, GDS, bundle) to GCS_OUTPUT_URI
#        even on non-zero exit so CI/Gemini can diagnose failures.
# ==============================================================================
set -euo pipefail

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

if [[ -z "${GCS_INPUT_URI:-}" ]]; then
    # Local / direct execution mode
    if [[ "$#" -eq 0 ]]; then
        exec bash flow/run_all.sh
    else
        exec "$@"
    fi
fi

# ------------------------------------------------------------------------------
# GCP Cloud Batch Execution Mode
# ------------------------------------------------------------------------------
if [[ -z "${GCS_OUTPUT_URI:-}" ]]; then
    echo "ERROR: GCS_OUTPUT_URI must be set when GCS_INPUT_URI is specified." >&2
    exit 2
fi

WORK_ROOT="${OPENSUSI_WORK_ROOT:-/work/job}"
mkdir -p "${WORK_ROOT}"
cd "${WORK_ROOT}"

echo "========================================================================"
echo " OpenSUSI EDA Container — GCP Cloud Batch Execution"
echo "   Container Version : ${OPENSUSI_EDA_CONTAINER_VERSION:-unknown}"
echo "   Input URI         : ${GCS_INPUT_URI}"
echo "   PDK URI           : ${GCS_PDK_URI:-<embedded in design repo>}"
echo "   Output URI        : ${GCS_OUTPUT_URI}"
echo "========================================================================"

if [[ -f /etc/opensusi-eda-versions.json ]]; then
    cat /etc/opensusi-eda-versions.json
fi

echo "=== [Batch 1/4] Fetching input design snapshot from GCS ==="
gcloud storage cp "${GCS_INPUT_URI}" /tmp/input_repo.tar.gz
tar -xzf /tmp/input_repo.tar.gz -C "${WORK_ROOT}"
rm -f /tmp/input_repo.tar.gz

if [[ -n "${GCS_PDK_URI:-}" ]]; then
    echo "=== [Batch 2/4] Fetching runtime PDK overlay from GCS ==="
    mkdir -p "${WORK_ROOT}/pdk"
    if [[ "${GCS_PDK_URI}" == *.tar.gz || "${GCS_PDK_URI}" == *.tgz ]]; then
        gcloud storage cp "${GCS_PDK_URI}" /tmp/pdk_overlay.tar.gz
        tar -xzf /tmp/pdk_overlay.tar.gz -C "${WORK_ROOT}/pdk"
        rm -f /tmp/pdk_overlay.tar.gz
    else
        gcloud storage cp -r "${GCS_PDK_URI%/}/*" "${WORK_ROOT}/pdk/"
    fi
else
    echo "=== [Batch 2/4] Using PDK configured in repository ==="
fi

FLOW_CMD="${FLOW_CMD:-bash flow/run_all.sh}"
echo "=== [Batch 3/4] Running EDA flow: ${FLOW_CMD} ==="
set +e
bash -lc "${FLOW_CMD}"
FLOW_RC=$?
set -e

echo "=== [Batch 4/4] Uploading outputs to ${GCS_OUTPUT_URI} (flow exit=${FLOW_RC}) ==="
mkdir -p "${WORK_ROOT}/output/reports"
if [[ -f /etc/opensusi-eda-versions.json ]]; then
    cp /etc/opensusi-eda-versions.json "${WORK_ROOT}/output/reports/eda_versions.json"
fi

if [[ -d "${WORK_ROOT}/output" ]]; then
    # Exclude heavy scratch work/ unless UPLOAD_WORK=true
    if [[ "${UPLOAD_WORK:-false}" != "true" ]]; then
        rm -rf "${WORK_ROOT}/output/work"
    fi
    gcloud storage cp -r "${WORK_ROOT}/output/*" "${GCS_OUTPUT_URI%/}/" || true
fi

echo "Batch job finished with exit code ${FLOW_RC}."
exit "${FLOW_RC}"
