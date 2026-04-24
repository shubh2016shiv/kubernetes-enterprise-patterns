# 03-wine-quality-inferenceservice

This module deploys a KServe `InferenceService` for the wine classifier.

## File Order

1. `01-wine-quality-sklearn-isvc.yaml`: the serving API contract.
2. `02-inspect-generated-k8s-objects.sh`: shows which lower-level objects KServe created.
3. `03-test-open-inference-v2.sh`: sends an inference request over the Open Inference Protocol.
4. `sample-v2-infer.json`: request payload used by the test script.

## Why This Matters

This is the first module where the learner sees a higher-level serving abstraction that still maps back to familiar Kubernetes resources underneath.
