# Training Control Plane

## What is this?

This module teaches the team-facing control plane around the wine quality
training pipeline: how a teammate triggers training, how MLflow records the run,
how a candidate model version becomes reviewable, and which exact reference is
handed to the future serving workflow.

## Why does this exist?

In an enterprise team, model training is not only caused by code changes. A data
scientist may rerun training after new data arrives, a platform engineer may run
a small smoke test after changing resources, and a reviewer may ask for a repeat
run with a different random seed. The control plane gives that autonomy while
keeping audit records in one place.

## ASCII concept diagram

```text
Team member or GitHub event
        |
        | code/config change, manual workflow_dispatch, or later a scheduled run
        v
GitHub Actions workflow
        |
        | validates code, chooses runtime knobs such as OPTUNA_N_TRIALS
        v
Training pipeline
        |
        | logs one MLflow run per Optuna hyperparameter trial
        | writes immutable local artifact bundle
        v
MLflow Tracking and Model Registry
        |
        | version tags: review_status, run_reason, triggered_by
        | alias: candidate points to the newest reviewable model
        v
Human review
        |
        | later approval can move champion to the chosen version
        v
Serving pipeline, in the next phase, reads the approved model reference
```

Vocabulary:

`workflow_dispatch` means a GitHub Actions workflow can be started manually
from the GitHub UI with inputs such as trial count and run reason.

MLflow Tracking stores experiment runs: metrics, parameters, artifacts, and run
metadata.

MLflow Model Registry stores named model versions and mutable aliases.
An alias is a readable pointer, such as `candidate` or `champion`, that can be
moved to a different model version without changing the version itself.

## Learning steps

1. Read [start-mlflow-server_1.sh](./start-mlflow-server_1.sh) to see how the local
   MLflow server is started for this lab.
2. Read [env_config.py](../src/wine_quality_training/shared/env_config.py) to
   see the central Pydantic Settings object that owns all runtime configuration.
3. Read [.env.example](../.env.example) to see the local candidate-training
   config template.
4. Read [publish_candidate_to_mlflow.py](../src/wine_quality_training/model_registry/publish_candidate_to_mlflow.py)
   to see how one completed training run becomes a reviewable MLflow model
   version.
5. Read [model-approval-and-serving-handoff-guide.md](./model-approval-and-serving-handoff-guide.md)
   to understand what happens after MLflow shows a candidate model version.
6. Read [mlflow-manager-promotion-runbook.md](./mlflow-manager-promotion-runbook.md)
   to follow the manager/lead workflow for promoting a candidate into a
   production-approved registry and assigning `champion`.
7. Read [ml-training-ci.yaml](../../../.github/workflows/ml-training-ci.yaml) to
   see how code/config changes and manual teammate requests trigger the training
   workflow.
8. Run the local MLflow server, then run the training pipeline using your
   local `.env` file.
9. Open the MLflow UI and inspect the `candidate` model alias.

## Commands section

Install `uv` in WSL2 if this is your first time running the training module:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source "$HOME/.local/bin/env"
uv --version
```

What you should see:

```text
uv 0.x.x
```

Start the local MLflow server from WSL2:

```bash
cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/k8s_mlops/ml-training/training-control-plane
./start-mlflow-server_1.sh
```

What you should see:

```text
[OK] WSL2 Python environment path: .../ml-training/.venv-wsl2
[INFO] First run note: uv may spend a few minutes installing MLflow.
[INFO] Open the browser only after you see a line like:
       Listening at: http://127.0.0.1:5000
[OK] MLflow backend directory exists
[OK] MLflow artifact directory exists
MLflow server listening at http://127.0.0.1:5000
```

In a second WSL2 terminal, run a candidate training job:

```bash
cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/k8s_mlops/ml-training

# One-time local setup:
# Copy the template to .env at the module root. The .env file is gitignored
# because each teammate has a different name, trial count, and MLflow URL.
cp .env.example .env

# Edit .env if you want to change TRAINING_TRIGGERED_BY,
# TRAINING_RUN_REASON, OPTUNA_N_TRIALS, or the MLflow URL.
uv run --extra tracking run-training-pipeline
```

What you should see:

```text
Wine Quality Training Pipeline - START
...
Starting hyperparameter search
...
MLflow trial runs appear during Phase 4
...
Artifact registration complete
...
MLflow candidate publication complete
```

Open the MLflow UI:

```bash
# Browser URL:
http://127.0.0.1:5000
```

What you should see:

```text
Experiment: wine-quality-cultivar-classification-v1
Runs tagged run_type=hyperparameter_trial
Registered model: wine-quality-classifier
Alias: candidate
Tags: review_status, local_artifact_version, run_reason, triggered_by
```

Important behavior:

If you run only:

```bash
uv run python -m wine_quality_training.pipeline.run_training_pipeline
```

from a clean checkout with no `.env` at the module root, the pipeline trains
and writes local artifacts, but MLflow stays empty. That is expected because
`TRAINING_RUNTIME_MODE` defaults to `local_artifact_only`.

If you want MLflow to capture the hyperparameter trials and final candidate,
copy the template and rerun:

```bash
cp .env.example .env
uv run --extra tracking run-training-pipeline
```

Configuration source order:

```text
1. Real environment variables
   Example: GitHub Actions inputs or Kubernetes ConfigMap/Secret env injection.

2. .env file at the module root (ml-training/.env)
   Example: the file you copied from .env.example on your local machine.

3. Pydantic defaults
   Example: local artifact-only training when no .env is present.
```

Enterprise note: the env file is a local teaching convenience. In production,
the same keys are injected by the platform from ConfigMaps, Secrets, workflow
parameters, or a self-service training portal.

Runtime modes:

| Mode | What happens | Enterprise use |
|---|---|---|
| `local_artifact_only` | Train, evaluate, and write a versioned artifact bundle. MLflow stays empty. | Developer smoke tests, fast CI validation, or offline debugging |
| `mlflow_candidate_review` | Log Optuna trial runs to MLflow, write the artifact bundle, and register a passing model as the `candidate`. | Shared team training runs that require review and audit |

## Enterprise translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Use `TRAINING_RUNTIME_MODE` in `.env` at the module root | Inject the same mode from Kubernetes ConfigMaps, GitHub Actions inputs, or an internal platform form | The platform, not an ad hoc CLI flag, declares whether a run is local-only or reviewable |
| Use `.env` for local runtime values | Inject the same keys from Kubernetes ConfigMaps, Secrets, GitHub Actions inputs, or an internal platform form | Developers need easy local runs; shared environments need auditable managed config |
| Run `mlflow server --serve-artifacts --artifacts-destination ./mlflow-tracking/artifacts` | Run MLflow with `--artifacts-destination s3://my-bucket/mlflow/` and `--serve-artifacts`, backed by PostgreSQL or MySQL | The artifact proxy pattern is identical; only the destination storage changes from local disk to object store |
| Run training from GitHub Actions for the lab | Trigger a Kubernetes Job, Argo Workflows DAG, or Kubeflow Pipeline from GitHub Actions | Real training may need more CPU, memory, GPUs, retries, and cluster scheduling |
| Use `workflow_dispatch` for manual teammate runs | Use a self-service portal, GitHub Actions manual run, or Argo Workflows submit form | The important pattern is controlled self-service with audit logs |
| Use `candidate` alias for review | Use `candidate`, `challenger`, and `champion` aliases with model version tags | MLflow stages are deprecated; aliases and tags are more flexible |
| Use SQLite for local MLflow metadata | Use PostgreSQL or MySQL for shared MLflow metadata | SQLite is excellent for a laptop lab; shared teams need concurrent access and backups |
| Upload CI artifacts from GitHub Actions | Store artifacts in S3/GCS/Azure and keep MLflow as the source of truth | CI runners are temporary; object storage is durable |

## Understanding the MLflow UI artifact layout

When you open a registered model version in the MLflow UI and click the
**Artifacts** tab, you may see an empty page. This is expected and is not a bug
in the training pipeline.

MLflow 3.x has two distinct artifact surfaces:

```text
Run detail page → Artifacts tab
  Shows everything logged with mlflow.log_artifacts() during the run.
  This is where your artifact_bundle/ (model.joblib, metrics.json,
  feature_schema.json, run_manifest.json, training_config.json) lives.
  Navigate to: Experiments → wine-quality-cultivar-classification-v1 →
               select the candidate run → Artifacts tab.

LoggedModel detail page → Artifacts tab
  Shows artifacts explicitly linked to the LoggedModel entity via the
  MLflow 3.x LoggedModel artifact API. mlflow.sklearn.log_model() creates
  the sklearn model files under run_artifacts/model/ but does not
  additionally link them to the LoggedModel artifact surface.
  This tab is intentionally empty in our setup because we use the run-level
  artifact_bundle/ as the single source of truth, which is the correct
  enterprise pattern (one auditable bundle per run, not scattered across
  multiple MLflow surfaces).
```

To verify the full artifact bundle exists, open the **source run** from the
registered model version page, then click the **Artifacts** tab. You should
see `artifact_bundle/` with all five files.

## What to check if something goes wrong

If MLflow UI does not open, confirm the server terminal is still running and the
URL is exactly `http://127.0.0.1:5000`. If the terminal only shows
`Using CPython ...`, MLflow is not listening yet; `uv` is still creating the
WSL2 Python environment or installing dependencies. Wait until the terminal
prints a server line such as `Listening at: http://127.0.0.1:5000`.

From a second WSL2 terminal, you can verify the port before opening the browser:

```bash
curl -I http://127.0.0.1:5000
```

What you should see:

```text
HTTP/1.1 200 OK
```

If the script prints `uv: command not found`, install `uv` inside WSL2. Windows
and WSL2 have separate executable paths, so a Windows `uv.exe` does not count
for Ubuntu:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source "$HOME/.local/bin/env"
uv --version
```

If training says `No module named mlflow`, install the optional tracking extra:

```bash
cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/k8s_mlops/ml-training
uv sync --extra tracking --group dev
```

If MLflow still stays empty, check your local runtime config:

```bash
cat .env
```

Confirm it contains:

```text
TRAINING_RUNTIME_MODE=mlflow_candidate_review
MLFLOW_TRACKING_URI=http://127.0.0.1:5000
```

If no registered model appears in MLflow, check that
`TRAINING_RUNTIME_MODE=mlflow_candidate_review` is set before running the
pipeline.

If the model appears but no `candidate` alias is set, inspect the model version
tag `review_status`. A failed metric gate is still logged for audit, but it is
not assigned the `candidate` alias.

If loading `models:/wine-quality-classifier/1` from Windows fails with a path
error like `D:\mnt\d\...` or a permission denied on a Linux-style path, the
server was started without `--serve-artifacts`. That flag is now present in
`start-mlflow-server_1.sh`. Stop the running server, restart it with the updated
script, then re-run the training pipeline to register a new model version with
a correct `mlflow-artifacts:/` artifact URI:

```bash
# Terminal 1 — WSL2: restart the server
bash training-control-plane/start-mlflow-server_1.sh

# Terminal 2 — WSL2: re-run the pipeline to create a clean artifact URI
cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/k8s_mlops/ml-training
uv run --extra tracking run-training-pipeline
```

After the re-run, `models:/wine-quality-classifier/2` (or the next version
number) will have an `mlflow-artifacts:/` artifact URI that resolves correctly
from Windows, WSL2, and containers alike.

Why this happens without --serve-artifacts:
The MLflow server runs in WSL2 and records artifact paths as Linux absolute
paths such as `/mnt/d/...`. A Windows Python client interpreting the same
path string reads it as `D:\mnt\d\...`, which does not exist. With
`--serve-artifacts` the client only ever uses `http://127.0.0.1:5000` as
the artifact endpoint and never touches the server filesystem directly.
