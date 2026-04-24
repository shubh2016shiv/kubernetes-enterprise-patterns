# 05-custom-fastapi-serving

This module is the custom application-serving contrast study.

## Why It Lives Under `ml-serving/`

Yes, the runtime belongs under `ml-serving/` because it is still a serving pattern. The important distinction is not whether it belongs in `ml-serving/`; it is whether the folder names clearly separate container-image code from Kubernetes deployment code. That is why this module is split into `runtime-image/` and `kubernetes-manifests/`.

## File Order

1. `runtime-image/`: build the application image and package the custom runtime.
2. `kubernetes-manifests/`: deploy that image to Kubernetes.

## Position In The Curriculum

Study this after the KServe path. It is here to teach what you have to manage manually when you do not use a serving platform abstraction like KServe.
