# Model Approval and Serving Handoff Guide

## What is this?

This guide explains what happens after training has produced a reviewable
MLflow model version. At this point the model is no longer just a file from a
training script. It is a governed candidate with metrics, artifacts, lineage,
tags, and aliases that a platform team can review before serving traffic.

## Why does this exist?

In enterprise MLOps, the dangerous mistake is treating "model trained
successfully" as the same thing as "model is approved for production." They are
different events. Training creates evidence. Approval accepts risk. Deployment
moves traffic. Monitoring proves the model behaves after release.

## ASCII concept diagram

```text
MLflow candidate model version
  alias: candidate
  tag: review_status=pending_human_review
        |
        v
Human and automated review
  metrics, schema, artifacts, lineage, smoke tests
        |
        v
Approval decision
  approved, rejected, needs_retrain
        |
        v
Model registry pointer changes
  local/simple: champion alias points to approved version
  mature enterprise: copy model version to prod registered model
        |
        v
Serving deployment pipeline
  reads approved model reference
  rolls out FastAPI or model server pods
        |
        v
Production inference
  requests include served model version
  metrics/logs track latency, errors, drift, and prediction quality
        |
        v
Rollback if needed
  move champion alias back or redeploy previous approved reference
```

Vocabulary:

`candidate` means the model version is reviewable, not production-approved.

`champion` means the model version is the currently approved default version for
serving traffic.

Model alias means a mutable named pointer to a model version. For example,
`models:/wine-quality-classifier@candidate` can point to version 1 today and
version 2 tomorrow.

Model version tag means metadata attached to a specific registered model
version. Example: `review_status=approved`.

Smoke test means a small automated test that verifies the model can be loaded
and can return predictions for known valid inputs before a real rollout.

## Learning steps

1. Open the MLflow registered model version that has alias `candidate`.
2. Review the model version tags: `review_status`, `run_group_id`,
   `local_artifact_version`, and `run_manifest_path`.
3. Open the source run and inspect metrics, parameters, and artifacts.
4. Decide whether the model should be approved, rejected, or sent back for
   retraining.
5. For this local lab, approval means setting an approved tag and assigning a
   `champion` alias.
6. In the future serving phase, the FastAPI or Kubernetes deployment consumes
   the approved model reference, not the raw training output directory.

## Commands section

View the candidate model in the MLflow UI:

```bash
# Browser URL:
http://127.0.0.1:5000
```

What you should see:

```text
Registered model: wine-quality-classifier
Version: 1
Alias: candidate
review_status: pending_human_review
local_artifact_version: v_YYYY-MM-DD_NNN
```

The local lab has not yet implemented the approval script. The approval action
will be added in the next training-control-plane step. The important concept is
that approval changes registry metadata; it does not retrain the model and does
not directly copy files into a Kubernetes pod.

Conceptual approval API:

```python
from mlflow import MlflowClient

client = MlflowClient(tracking_uri="http://127.0.0.1:5000")

# Mark the reviewed version as approved.
client.set_model_version_tag(
    name="wine-quality-classifier",
    version="1",
    key="review_status",
    value="approved",
)

# Make this version the currently approved serving target.
client.set_registered_model_alias(
    name="wine-quality-classifier",
    alias="champion",
    version="1",
)
```

What you should see:

```text
wine-quality-classifier version 1
aliases: candidate, champion
review_status: approved
```

Future serving reference:

```text
models:/wine-quality-classifier@champion
```

That reference is what an inference pipeline or model server should consume.

## Enterprise translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Review one MLflow candidate by hand | Combine human approval with automated validation checks | Human judgment and automated safety checks catch different risks |
| Use `candidate` alias for review | Use `candidate`, `challenger`, `shadow`, `canary`, and `champion` aliases | Different aliases support staged rollout, A/B testing, and rollback |
| Set `champion` alias on the same registered model | Often copy the approved version into a production registered model such as `prod.ml_team.wine_quality_classifier` | Separate registered models can enforce environment access control |
| Click or script approval locally | Use GitHub Actions, Argo Workflows, Jenkins, or an internal approval portal | Enterprise approval needs audit logs, approver identity, and repeatability |
| Serving reads `models:/wine-quality-classifier@champion` | Serving reads a prod alias, immutable model URI, or object-store URI plus checksum | Production systems need precise rollback and supply-chain traceability |
| Rollback by moving `champion` back | Rollback through GitOps, deployment history, or alias reassignment plus rollout restart | Traffic must move safely without manually editing live pods |

## What to check if something goes wrong

If MLflow shows a `Promote model` button, understand what it means. In MLflow
3.x, promotion can copy a model version to another registered model. This is
useful when you maintain separate registered models for environments, such as
development and production. It is not the same thing as "send this model to a
Kubernetes pod right now."

If the model version has alias `candidate` but not `champion`, the model is
still pending review. A serving system should not treat it as approved.

If the model version has `review_status=pending_human_review`, approval has not
happened yet. Review metrics, artifacts, schema, and lineage before moving the
approved alias.

If serving later loads the wrong model, check the exact model reference first:

```text
Expected approved reference:
models:/wine-quality-classifier@champion

Common wrong references:
models:/wine-quality-classifier@candidate
models:/wine-quality-classifier/1
local artifacts/wine_quality_classifier/v_... path
```

## The enterprise moment of truth

The exact moment you are seeing in MLflow is the handoff between model
development and model governance.

Before this point, the question is:

```text
Can we train a model and produce evidence?
```

After this point, the question becomes:

```text
Do we trust this specific model version enough to let a serving system load it?
```

The answer is recorded through registry metadata: tags, aliases, descriptions,
approval records, and eventually deployment history. Kubernetes does not decide
whether a model is approved. Kubernetes only runs the serving workload that is
configured to load the approved reference.
