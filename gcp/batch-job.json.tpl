{
  "taskGroups": [
    {
      "taskSpec": {
        "runnables": [
          {
            "container": {
              "imageUri": "${EDA_CONTAINER_IMAGE}",
              "commands": []
            }
          }
        ],
        "computeResource": {
          "cpuMilli": ${CPU_MILLI},
          "memoryMib": ${MEMORY_MIB},
          "bootDiskMib": ${BOOT_DISK_MIB}
        },
        "maxRetryCount": ${MAX_RETRY_COUNT},
        "maxRunDuration": "${MAX_RUN_DURATION}",
        "environment": {
          "variables": {
            "GCS_INPUT_URI": "${GCS_INPUT_URI}",
            "GCS_OUTPUT_URI": "${GCS_OUTPUT_URI}",
            "GCS_PDK_URI": "${GCS_PDK_URI}",
            "FLOW_CMD": "${FLOW_CMD}"
          }
        }
      },
      "taskCount": 1,
      "parallelism": 1
    }
  ],
  "allocationPolicy": {
    "instances": [
      {
        "policy": {
          "machineType": "${MACHINE_TYPE}",
          "provisioningModel": "${PROVISIONING_MODEL}"
        }
      }
    ],
    "serviceAccount": {
      "email": "${BATCH_SERVICE_ACCOUNT}"
    }
  },
  "logsPolicy": {
    "destination": "CLOUD_LOGGING"
  },
  "labels": {
    "platform": "opensusi-eda",
    "repo": "${LABEL_REPO}",
    "pdk": "${LABEL_PDK}"
  }
}
