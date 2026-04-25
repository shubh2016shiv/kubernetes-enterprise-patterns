# MLflow Manager Promotion Runbook

## What is this?

This runbook documents the exact manager or technical lead workflow for taking
a trained MLflow candidate model, copying it into a production-approved
registered model, and selecting the version that a future Kubernetes serving
deployment should load.

## Why does this exist?

Training success is not production approval. In an enterprise team, a model
must pass through a visible governance step before an inference service is
allowed to serve it. This runbook makes that governance step explicit:

1. The training pipeline creates a `candidate`.
2. A manager or lead reviews the evidence.
3. The manager promotes/copies the model into a production-approved registered
   model.
4. The manager marks exactly one version as `champion`.
5. A future serving pipeline reads the `champion` reference.

## ASCII concept diagram

```text
Training pipeline output
        |
        v
Registered model: wine-quality-classifier
Version 1
Alias: candidate
Tag: review_status=pending_human_review
        |
        | Manager/lead reviews metrics, params, artifacts, and lineage
        v
MLflow Promote model action
        |
        | Copy to model: wine-quality-classifier-prod
        v
Registered model: wine-quality-classifier-prod
Version 1
Aliases: none yet
Tag copied from source: review_status=pending_human_review
        |
        | Manager/lead makes the serving decision explicit
        v
Registered model: wine-quality-classifier-prod
Version 1
Alias: champion
Tag: review_status=approved
        |
        v
Future serving reference
models:/wine-quality-classifier-prod@champion
```

Vocabulary:

`candidate` means "ready for review." It does not mean production approved.

`wine-quality-classifier-prod` is the production-approved registered model area
you created as a manager/lead. Think of it as the approved bucket of model
versions.

`champion` means "this is the currently selected model version for serving."
Serving systems should load `champion`, not whichever version is newest.

`review_status=approved` is a model version tag that records the human review
decision. The alias tells serving what to load. The tag tells humans and audit
systems why that version is allowed to be served.

## Learning steps

1. Open MLflow at `http://127.0.0.1:5000`.
2. Go to **Model registry**.
3. Open `wine-quality-classifier`.
4. Open the version that has alias `candidate`.
5. Review the source run metrics, parameters, artifacts, and tags.
6. Click **Promote model**.
7. Copy/promote it to `wine-quality-classifier-prod`.
8. Open `wine-quality-classifier-prod` version 1.
9. Add alias `champion`.
10. Edit tag `review_status` from `pending_human_review` to `approved`.
11. Treat `models:/wine-quality-classifier-prod@champion` as the future serving
    reference.

## Commands section

This runbook is UI-first because the goal is to understand the enterprise
governance workflow visually. The equivalent MLflow API shape is:

```python
from mlflow import MlflowClient

client = MlflowClient(tracking_uri="http://127.0.0.1:5000")

# After the promoted model exists in wine-quality-classifier-prod:
client.set_registered_model_alias(
    name="wine-quality-classifier-prod",
    alias="champion",
    version="1",
)

client.set_model_version_tag(
    name="wine-quality-classifier-prod",
    version="1",
    key="review_status",
    value="approved",
)
```

What you should see in MLflow:

```text
Registered Models
  wine-quality-classifier
    Version 1
    Alias: candidate

  wine-quality-classifier-prod
    Version 1
    Alias: champion
    Tag: review_status=approved
```

Future serving reference:

```text
models:/wine-quality-classifier-prod@champion
```

That reference says:

```text
Load the version currently approved for serving from the production model area.
```

## Enterprise translation

| Local lab action | Enterprise equivalent | Why it matters |
|---|---|---|
| Manager manually clicks **Promote model** | Approval workflow copies candidate into production registry | Separates "trained" from "approved" |
| Manager creates/uses `wine-quality-classifier-prod` | Production registered model namespace, often access-controlled | Prevents every candidate from being eligible for serving |
| Manager manually types `champion` alias | Approval workflow or platform portal sets alias from an allowed list | Prevents typos such as `champoin` from breaking serving |
| Manager edits `review_status=approved` | Governance system records approver, timestamp, ticket, and policy checks | Creates audit trail for production model changes |
| Serving later reads `@champion` | Deployment pipeline resolves alias to an immutable version and rolls out pods | Balances human-friendly approval with reproducible deployment |

## What to check if something goes wrong

If `wine-quality-classifier-prod` version 1 has no alias, the version is copied
but not selected for serving. Add alias:

```text
champion
```

If `wine-quality-classifier-prod` version 1 has alias `champion` but
`review_status=pending_human_review`, the metadata is inconsistent. Update the
tag to:

```text
review_status=approved
```

If someone mistypes the alias, the future serving pipeline will not find the
expected reference:

```text
Expected:
models:/wine-quality-classifier-prod@champion

Wrong:
models:/wine-quality-classifier-prod@champoin
models:/wine-quality-classifier-prod@production
models:/wine-quality-classifier-prod@prod
```

This is why enterprise teams usually do not rely on free-typed aliases in the
MLflow UI. They wrap this step in a script, approval workflow, or internal
platform button that only allows approved alias values.

If multiple versions are promoted into `wine-quality-classifier-prod`, that is
normal. Only one should be the main `champion` at a time:

```text
wine-quality-classifier-prod
  Version 1  alias: champion
  Version 2  alias: challenger
  Version 3  no live alias yet
```

The presence of several approved versions does not decide serving. The serving
decision is the alias or immutable model reference used by the deployment.

## How this connects to future Kubernetes serving

The future `ml-inferencing` or serving module should not scan the registry and
guess which version to use. It should receive an explicit approved reference:

```text
MODEL_URI=models:/wine-quality-classifier-prod@champion
```

Then a deployment workflow should ideally resolve the alias to an immutable
version:

```text
models:/wine-quality-classifier-prod@champion
        |
        v
models:/wine-quality-classifier-prod/1
```

Kubernetes then rolls out FastAPI pods with that exact reference:

```text
Deployment env:
  MODEL_REGISTRY_NAME=wine-quality-classifier-prod
  MODEL_ALIAS=champion
  MODEL_VERSION=1
  MODEL_URI=models:/wine-quality-classifier-prod/1
```

FastAPI does not choose the model by itself. It loads the approved model
reference provided by the deployment configuration. The production platform
chooses; FastAPI serves.
