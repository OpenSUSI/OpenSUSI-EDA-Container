# ==============================================================================
# OpenSUSI Standard Open-Source EDA Execution Container
# Scope : Generic, PDK-agnostic, MPW-shuttle-agnostic EDA toolchain
# Tools : OpenROAD (+ OpenSTA), Yosys, KLayout, Icarus Verilog, ngspice, Python
# Note  : Deliberately excludes PDK files and MPW shuttle frame integration
#         assets, which vary per PDK and per MPW shuttle and are supplied at
#         runtime by each design repository / PDK mount / MPW Aggregation stage.
# ==============================================================================

ARG BASE_IMAGE=openroad/orfs:latest
FROM ${BASE_IMAGE}

ARG IMAGE_VERSION=v0.1.0
ARG KLAYOUT_VERSION=0.30.13
ARG INSTALL_GCLOUD=true

LABEL org.opencontainers.image.title="OpenSUSI Standard EDA Container" \
      org.opencontainers.image.description="PDK-agnostic open-source EDA container (OpenROAD, Yosys, KLayout, iverilog, ngspice) for OpenSUSI x Google AI-Assisted Chip Design Platform" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.licenses="Apache-2.0"

USER root
ENV DEBIAN_FRONTEND=noninteractive \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR=/tmp \
    OPENSUSI_EDA_CONTAINER_VERSION="${IMAGE_VERSION}" \
    PATH="/OpenROAD-flow-scripts/tools/install/OpenROAD/bin:/OpenROAD-flow-scripts/tools/install/yosys/bin:/usr/local/bin:/usr/bin:/bin"

# 1. Core utilities, Icarus Verilog, ngspice, and Python runtime
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        gnupg \
        iverilog \
        jq \
        ngspice \
        python3 \
        python3-yaml \
        tar \
        wget && \
    rm -rf /var/lib/apt/lists/*

# 2. Install pinned KLayout (.deb matching base image Ubuntu LTS release)
RUN set -eux; \
    . /etc/os-release; \
    UBUNTU_MAJOR="${VERSION_ID%%.*}"; \
    DEB="klayout_${KLAYOUT_VERSION}-1_amd64.deb"; \
    URL="https://www.klayout.org/downloads/Ubuntu-${UBUNTU_MAJOR}/${DEB}"; \
    wget -q "${URL}" -O "/tmp/${DEB}"; \
    apt-get update; \
    apt-get install -y --no-install-recommends "/tmp/${DEB}"; \
    rm -f "/tmp/${DEB}"; \
    rm -rf /var/lib/apt/lists/*

# 3. Install Google Cloud CLI for GCP Cloud Batch GCS staging (optional)
RUN set -eux; \
    if [ "${INSTALL_GCLOUD}" = "true" ]; then \
        curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
            | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg; \
        echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
            > /etc/apt/sources.list.d/google-cloud-sdk.list; \
        apt-get update; \
        apt-get install -y --no-install-recommends google-cloud-cli; \
        rm -rf /var/lib/apt/lists/*; \
    fi

# 4. Ensure standard symlinks in /usr/local/bin (works regardless of base PATH)
RUN set -eux; \
    for bin_dir in \
        /OpenROAD-flow-scripts/tools/install/OpenROAD/bin \
        /OpenROAD-flow-scripts/tools/install/yosys/bin; do \
        if [ -d "${bin_dir}" ]; then \
            for tool in openroad yosys yosys-abc; do \
                if [ -x "${bin_dir}/${tool}" ] && [ ! -e "/usr/local/bin/${tool}" ]; then \
                    ln -s "${bin_dir}/${tool}" "/usr/local/bin/${tool}"; \
                fi; \
            done; \
        fi; \
    done

# 5. Install OpenSUSI container helper scripts & record immutable tool versions
COPY entrypoint.sh /opt/opensusi/entrypoint.sh
COPY scripts/dump_versions.sh /opt/opensusi/scripts/dump_versions.sh
COPY scripts/smoke_test.sh /opt/opensusi/scripts/smoke_test.sh

RUN chmod +x /opt/opensusi/entrypoint.sh \
             /opt/opensusi/scripts/dump_versions.sh \
             /opt/opensusi/scripts/smoke_test.sh && \
    /opt/opensusi/scripts/dump_versions.sh > /etc/opensusi-eda-versions.json && \
    /opt/opensusi/scripts/smoke_test.sh

WORKDIR /work
ENTRYPOINT ["/opt/opensusi/entrypoint.sh"]
CMD ["bash", "flow/run_all.sh"]
