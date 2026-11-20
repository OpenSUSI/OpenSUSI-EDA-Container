# GCP Cloud Batch Deployment Guide (`gcp/`)

This directory contains the GCP Cloud Batch job specification and submission helper used by the **OpenSUSI × Google AI-Assisted Chip Design Platform**.

## 1. Architecture Separation

- **This Container (`OpenSUSI-EDA-Container`)**: Pure open-source EDA runtime (`OpenROAD`, `Yosys`, `KLayout`, `iverilog`, `ngspice`, `Python`, `gcloud`). Contains **no PDK files** and **no MPW shuttle frame integration scripts**.
- **Design Repository (`NEW-130E_MPW_template` clones)**: Holds RTL, constraints, verification testbench, `design.yaml`, and PDK profile reference.
- **PDK Overlay (optional GCS URI `GCS_PDK_URI`)**: For foundry-restricted PDKs (e.g., 130 nm `NEW-130E`), PDK views/decks can live in a restricted GCS bucket and be fetched at runtime by `entrypoint.sh`.
- **MPW Aggregation (separate downstream stage)**: Consumes only signed-off `mpw_bundle.tar.gz` + `manifest.json` from the Submission Gateway to assemble shuttle-specific frames and slots.

## 2. One-Time GCP Project Setup

```bash
export PROJECT_ID="opensusi-eda-platform"
export REGION="asia-northeast1"
export AR_REPO="eda"
export BUCKET="gs://opensusi-mpw-artifacts"

# 1. Enable required APIs
gcloud services enable \
  batch.googleapis.com \
  compute.googleapis.com \
  artifactregistry.googleapis.com \
  storage.googleapis.com \
  logging.googleapis.com \
  iamcredentials.googleapis.com \
  --project="${PROJECT_ID}"

# 2. Create Artifact Registry repository for immutable EDA images
gcloud artifacts repositories create "${AR_REPO}" \
  --repository-format=docker \
  --location="${REGION}" \
  --project="${PROJECT_ID}"

# 3. Create artifact bucket with lifecycle cleanup for scratch jobs
gcloud storage buckets create "${BUCKET}" \
  --location="${REGION}" \
  --uniform-bucket-level-access \
  --project="${PROJECT_ID}"

# 4. Create dedicated least-privilege Batch worker Service Account
gcloud iam service-accounts create eda-batch-worker \
  --display-name="OpenSUSI EDA Cloud Batch Worker" \
  --project="${PROJECT_ID}"

SA="eda-batch-worker@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA}" --role="roles/batch.agentReporter"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA}" --role="roles/logging.logWriter"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA}" --role="roles/artifactregistry.reader"
gcloud storage buckets add-iam-policy-binding "${BUCKET}" \
  --member="serviceAccount:${SA}" --role="roles/storage.objectUser"
```

## 3. Submitting a Job Manually

```bash
./gcp/submit_batch.sh \
  --repo-dir ../NEW-130E_MPW_template \
  --project "${PROJECT_ID}" \
  --region "${REGION}" \
  --bucket "${BUCKET}" \
  --image "${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/opensusi-eda:v0.1.0" \
  --service-account "eda-batch-worker@${PROJECT_ID}.iam.gserviceaccount.com" \
  --spot \
  --wait
```
