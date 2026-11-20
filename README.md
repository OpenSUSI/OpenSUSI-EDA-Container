# OpenSUSI-EDA-Container

Standardized, PDK-agnostic, MPW-shuttle-agnostic open-source EDA execution container for the **OpenSUSI × Google AI-Assisted Chip Design Platform**.

---

## Scope & Design Boundary

| Included in This Container | Deliberately Excluded (Supplied Separately) |
| :--- | :--- |
| **OpenROAD** (+ OpenSTA) — Floorplan, P&R, STA | Foundry PDKs (`TR-1um`, `NEW-130E`, etc.) |
| **Yosys** (+ `yosys-abc`) — RTL synthesis | MPW shuttle frame / seal-ring / slot aggregation assets |
| **KLayout (`0.30.9`)** — Headless DRC / LVS / MDP / GDSII | Designer RTL, SDC, and project secrets |
| **Icarus Verilog (`iverilog` / `vvp`)** — RTL & Gate-level simulation | |
| **ngspice** — Transistor-level & post-layout SPICE simulation | |
| **Python 3** (+ PyYAML) & **Google Cloud CLI (`gcloud`)** | |

Because PDK files and shuttle-specific MPW frame integration assets vary per PDK and per MPW shuttle, keeping them out of this image guarantees that the EDA container remains 100% open-source, reusable across processes (`TR-1um` PoC → `NEW-130E` 130 nm), and independently versioned.

---

## Repository Layout

```text
OpenSUSI-EDA-Container/
├── Dockerfile                    # OpenROAD + Yosys + KLayout 0.30.9 + iverilog + ngspice + gcloud
├── versions.env                  # Pinned tool & container versions
├── entrypoint.sh                 # Dual-mode entrypoint (Local mount & GCP Cloud Batch GCS mode)
├── scripts/
│   ├── dump_versions.sh          # Writes /etc/opensusi-eda-versions.json at build time
│   └── smoke_test.sh             # Verifies all EDA tools (including ngspice batch simulation)
├── gcp/
│   ├── README.md                 # GCP Artifact Registry / GCS / IAM / Batch setup guide
│   ├── batch-job.json.tpl        # Cloud Batch job specification template
│   └── submit_batch.sh           # Stage repo snapshot to GCS & submit Cloud Batch job
└── .github/workflows/
    └── build-release.yml         # CI build, smoke test, and immutable push to AR / GHCR
```

---

## Quick Start (Local Docker)

### 1. Build Image (`linux/amd64`)
```bash
source versions.env
docker build --platform linux/amd64 \
  --build-arg BASE_IMAGE="${BASE_IMAGE}" \
  --build-arg IMAGE_VERSION="${IMAGE_VERSION}" \
  --build-arg KLAYOUT_VERSION="${KLAYOUT_VERSION}" \
  --build-arg INSTALL_GCLOUD="${INSTALL_GCLOUD}" \
  -t "opensusi-eda:${IMAGE_VERSION}" .
```

### 2. Run a Design Template Repository Locally (e.g., `NEW-130E_MPW_template`)
```bash
docker run --rm --platform linux/amd64 \
  -v "$(pwd)/../NEW-130E_MPW_template:/work" \
  "opensusi-eda:${IMAGE_VERSION}" \
  bash flow/run_all.sh
```

### 3. Inspect Baked-in Tool Versions
```bash
docker run --rm "opensusi-eda:${IMAGE_VERSION}" cat /etc/opensusi-eda-versions.json
```

---

## GCP Cloud Batch Execution

See [`gcp/README.md`](gcp/README.md) for Artifact Registry, Workload Identity Federation (WIF), and [`gcp/submit_batch.sh`](gcp/submit_batch.sh) usage.
