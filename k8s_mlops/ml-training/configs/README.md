# Configuration Reference — Wine Quality Training Pipeline

## What Is This?

This document is the **single source of truth for every configuration value** in
the `ml-training` module. Before you change any config file, read the relevant
section here to understand what the parameter controls, which other values it
affects, and what value to use for each scenario.

ML training pipelines are configuration-driven by design. A wrong value in the
wrong file can silently waste hours of GPU time, corrupt an experiment's metrics,
or publish an untested model to the team's candidate registry. This guide exists
so that no team member has to guess.

---

## Why Does ML Need a Config Reference More Than Other Software?

In most software, a wrong config causes a crash and you fix it. In ML:

- A wrong `random_seed` produces a different train/test split — your metrics are
  no longer comparable to last week's run, but the pipeline completes without error.
- A wrong `n_trials` in a prod run costs real compute money and time.
- A wrong `TRAINING_RUNTIME_MODE` means your team never sees the experiment in
  MLflow, even though the model trained correctly.
- Forgetting to set `TRAINING_TRIGGERED_BY` means the MLflow audit trail has no
  owner and your compliance reviewer raises a flag.

None of these failures make noise. They are silent mistakes that surface only
when a teammate asks "why does the new model have a different split than the one
we reviewed last month?" This guide prevents that class of error.

---

## The Three-Layer Configuration Architecture

Values are resolved in this priority order. A higher layer always wins.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER 1 — Process environment variables (highest priority)                 │
│                                                                             │
│  Set by:  Kubernetes Job spec (production)                                  │
│           GitHub Actions workflow (CI)                                      │
│           Shell export before running locally                               │
│                                                                             │
│  Example: export OPTUNA_N_TRIALS=3 && uv run run-training-pipeline         │
│                                                                             │
│  These override everything below them.                                      │
└──────────────────────────────┬──────────────────────────────────────────────┘
                               │ lower priority than Layer 1
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER 2 — .env file at the module root (local developer convenience)       │
│                                                                             │
│  File:    ml-training/.env          ← your personal local values            │
│  Template: ml-training/.env.example ← committed to Git, never edited       │
│                                                                             │
│  Loaded automatically by Pydantic Settings when the pipeline runs from      │
│  the ml-training/ directory. Never committed to Git (gitignored).           │
│                                                                             │
│  Enterprise equivalent: Kubernetes ConfigMap + Secret injection.            │
└──────────────────────────────┬──────────────────────────────────────────────┘
                               │ lower priority than Layer 2
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER 3 — configs/training_pipeline.yaml (shared pipeline config)          │
│                                                                             │
│  File:    ml-training/configs/training_pipeline.yaml                        │
│  Tracked: Yes — committed to Git, shared by the whole team                  │
│                                                                             │
│  Controls structural pipeline decisions: which model families to search,    │
│  how the train/test split is constructed, Optuna search budget defaults.    │
│  Changes here affect every team member on every branch.                     │
│                                                                             │
│  Enterprise equivalent: Kubernetes ConfigMap (mounted as a file).           │
└──────────────────────────────┬──────────────────────────────────────────────┘
                               │ lower priority than Layer 3
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER 4 — Pydantic defaults (lowest priority, safe fallback)               │
│                                                                             │
│  Source:  src/wine_quality_training/shared/env_config.py                    │
│           src/wine_quality_training/pipeline/pipeline_run_config.py         │
│                                                                             │
│  Used when no environment variable, .env file, or YAML value is set.       │
│  Safe for running tests; NOT appropriate for real training runs.            │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Quick Reference: "What Do I Change When I Want To…"

Use this table before you open any file. It tells you exactly which file and
which field to change for the most common team scenarios.

| I want to…                                      | File to change      | Field / variable                   |
|-------------------------------------------------|---------------------|------------------------------------|
| Enable MLflow experiment tracking               | `.env`              | `TRAINING_RUNTIME_MODE`            |
| Change the MLflow server address                | `.env`              | `MLFLOW_TRACKING_URI`              |
| Record who triggered this run                   | `.env`              | `TRAINING_TRIGGERED_BY`            |
| Record why this run was started                 | `.env`              | `TRAINING_RUN_REASON`              |
| Run a quick 5-trial smoke test                  | `.env`              | `OPTUNA_N_TRIALS=5`                |
| Run a full 60-trial candidate search            | `.env`              | `OPTUNA_N_TRIALS=60`               |
| Change where artifacts are written              | `.env`              | `ARTIFACT_STORE_ROOT`              |
| Add a new model family to the search            | `training_pipeline.yaml` | `model_families`              |
| Remove a model family from the search           | `training_pipeline.yaml` | `model_families`              |
| Change the train/test split ratio               | `training_pipeline.yaml` | `test_size`                   |
| Change the random seed (new experiment design)  | `training_pipeline.yaml` | `random_seed`                 |
| Change the number of CV folds                   | `training_pipeline.yaml` | `cv_folds`                    |
| Change the Optuna search default (shared)       | `training_pipeline.yaml` | `optuna.n_trials`             |
| Change the optimization metric                  | `training_pipeline.yaml` | `optuna.metric`               |
| Change the MLflow experiment name              | `training_pipeline.yaml` | `experiment_name`             |
| Set a per-run trial limit in Kubernetes         | Job env injection   | `OPTUNA_N_TRIALS` env var          |
| Point to a different pipeline config file       | `.env` or Job spec  | `PIPELINE_CONFIG_PATH`            |
| Change the model name in the MLflow registry    | `.env`              | `MLFLOW_REGISTERED_MODEL_NAME`     |

---

## Config Interaction Map

Some parameters only matter when other parameters are set a certain way. Getting
this wrong is the most common source of "it trained but nothing showed up in MLflow."

```
TRAINING_RUNTIME_MODE
│
├── "local_artifact_only"
│     │
│     └── Only these matter:
│           ARTIFACT_STORE_ROOT       → where model files are written
│           PIPELINE_CONFIG_PATH      → which YAML to load
│           OPTUNA_N_TRIALS           → how many trials to run
│           RANDOM_SEED               → reproducibility seed
│           LOG_LEVEL                 → how much to print
│
│     These are IGNORED (MLflow is not contacted):
│           MLFLOW_TRACKING_URI
│           MLFLOW_REGISTERED_MODEL_NAME
│           MLFLOW_CANDIDATE_ALIAS
│           TRAINING_TRIGGERED_BY     (still logged locally, but not to MLflow)
│           TRAINING_RUN_REASON       (same)
│
└── "mlflow_candidate_review"
      │
      └── ALL variables matter. In addition to the local_artifact_only set:
            MLFLOW_TRACKING_URI            → MUST point to a running MLflow server
            MLFLOW_REGISTERED_MODEL_NAME   → model name in the MLflow registry
            MLFLOW_CANDIDATE_ALIAS         → alias set on the passing version
            TRAINING_TRIGGERED_BY          → written as MLflow run tag
            TRAINING_RUN_REASON            → written as MLflow run tag

      Common mistake: setting TRAINING_RUNTIME_MODE=mlflow_candidate_review
      but forgetting to start the MLflow server first. The pipeline will fail
      at Phase 4 (first MLflow call) with a connection error, after the
      expensive hyperparameter search has already started.
      Fix: always run start-mlflow-server.sh BEFORE submitting a candidate run.
```

---

## Parameter Reference: `.env` File

These are runtime variables. They live in your local `.env` file and are injected
by Kubernetes in production. They override anything set in `training_pipeline.yaml`.

| Variable | Type | Default (Pydantic) | Description | When to change |
|---|---|---|---|---|
| `PIPELINE_CONFIG_PATH` | Path | `configs/training_pipeline.yaml` | Path to the YAML pipeline config. In Kubernetes this is the ConfigMap mount path. | When pointing to a different experiment config (dev vs prod). |
| `ARTIFACT_STORE_ROOT` | Path | `artifacts` | Root directory where versioned model artifacts are written. In Kubernetes this is the PVC mount path. | When the PVC mount path differs from the default. |
| `LOG_LEVEL` | str | `INFO` | Structured logging verbosity. Valid values: `DEBUG`, `INFO`, `WARNING`, `ERROR`. | Use `DEBUG` when debugging a phase failure. |
| `OPTUNA_N_TRIALS` | int ≥ 1 | `60` (YAML default) | Total number of hyperparameter search trials for this run. Overrides `optuna.n_trials` in the YAML. | Smoke test: set to 5. Full candidate: use YAML default (60). CI: set to 3. |
| `RANDOM_SEED` | int | `42` | Seed for reproducible train/test split and model weight initialisation. Overrides `random_seed` in YAML. | Only when intentionally running a different random design. Document the change. |
| `TRAINING_RUNTIME_MODE` | Literal | `local_artifact_only` | Controls whether MLflow is contacted. Two valid values: `local_artifact_only` (no MLflow) or `mlflow_candidate_review` (full MLflow tracking + registration). | Set to `mlflow_candidate_review` for any run that should be visible to the team. |
| `MLFLOW_TRACKING_URI` | str | `sqlite:///mlflow.db` | URI of the MLflow Tracking server. For local development: `http://127.0.0.1:5000`. Ignored when `TRAINING_RUNTIME_MODE=local_artifact_only`. | Change only if your MLflow server runs on a different address or port. |
| `MLFLOW_REGISTERED_MODEL_NAME` | str | `wine-quality-classifier` | Name under which the model is registered in the MLflow Model Registry. All versions of this model share this name. | Change only when starting a new model lineage (e.g., a new architecture that should not share version history with the old one). |
| `MLFLOW_CANDIDATE_ALIAS` | str | `candidate` | Mutable alias applied to the latest model version that passed the promotion gate. Reviewers look up `@candidate` in the MLflow UI to find the model waiting for approval. | Rarely changed. Only if your team uses a different alias convention. |
| `TRAINING_TRIGGERED_BY` | str | `local-user` | Name of the person, CI system, or Kubernetes controller that triggered this run. Written as an MLflow tag for audit. | **Always set this to your own name** before a local candidate run. |
| `TRAINING_RUN_REASON` | str | `local training run` | Human-readable reason for this run. Written as an MLflow tag. | Write a specific reason: "retrain after adding magnesium feature", not "training run". |

---

## Parameter Reference: `training_pipeline.yaml`

These parameters are **shared by the whole team**. Changing them affects every
teammate who runs training until the change is reverted. Treat a PR that changes
this file the same as a PR that changes Python training code.

| Field | Type | Default | Description | When to change |
|---|---|---|---|---|
| `experiment_name` | str | `wine-quality-cultivar-classification-v1` | Name of the MLflow experiment. All runs from this pipeline appear under this name in the MLflow UI. Changing it starts a new experiment — old runs remain under the old name. | When starting a fundamentally new experiment design (new features, new target). Do not change for routine retraining. |
| `artifact_store_root` | Path | `artifacts` | Fallback artifact root used when `ARTIFACT_STORE_ROOT` env var is not set. | Rarely changed. The env var takes precedence; this is a safe default for local runs. |
| `model_families` | list[str] | `[random_forest, gradient_boosting, logistic_regression]` | Which model families Optuna searches over. Each entry must match a key in `SEARCH_SPACE_REGISTRY` in `hyperparameter_search_config.py`. | Add a new family to include it in the search. Remove one to exclude it without touching Python code. |
| `test_size` | float (0–1) | `0.20` | Fraction of the dataset reserved for final evaluation. This split is set once and never used during hyperparameter search. | **Almost never change this.** Changing it invalidates metric comparisons with all previous runs because the test set changes. If you must change it, document it as a new experiment. |
| `random_seed` | int | `42` | Seed for stratified train/test split and Optuna sampler. Changing this changes the split and all resulting metrics. | Treat this the same as `test_size`. Change only when deliberately running a different random design, and document it. |
| `cv_folds` | int ≥ 2 | `5` | Number of stratified k-fold cross-validation folds used during Optuna search. Higher = more stable CV score estimate, longer search. | Increase for higher-variance datasets. Do not reduce below 3. |
| `optuna.n_trials` | int ≥ 1 | `60` | Default number of Optuna trials for a full candidate run. Can be overridden per-run via `OPTUNA_N_TRIALS` env var. | Increase for a more exhaustive search. Decrease to reduce cost. Note that individual overrides via env var are preferred for non-permanent changes. |
| `optuna.timeout_seconds` | int or null | `null` | Wall-clock timeout for the Optuna search. `null` means no timeout. Set a value to bound cost in shared clusters. | Set to a value (e.g., 3600 for 1 hour) when running in a shared cluster with a compute budget. |
| `optuna.direction` | str | `maximize` | Whether Optuna maximises or minimises the search metric. `maximize` for accuracy-family metrics, `minimize` for error-family metrics. | Change only if switching to a loss metric (e.g., log_loss). |
| `optuna.metric` | str | `balanced_accuracy` | Scikit-learn scoring string used as the Optuna objective and the primary reported CV metric. `balanced_accuracy` weights all classes equally, making it more honest than plain `accuracy` on multi-class problems. | Change to a different sklearn metric string if the business objective changes (e.g., `f1_macro` for a precision-recall trade-off). |

---

## File Ownership and Change Risk

| File | Tracked in Git | Who should change it | Risk if changed incorrectly |
|---|---|---|---|
| `.env` | No (gitignored) | Individual developer — personal values only | Low: only affects your local runs |
| `.env.example` | Yes | ML Lead / platform engineer — team template | Medium: all new developers copy this |
| `configs/training_pipeline.yaml` | Yes | Any team member via PR + review | **High**: changes affect all runs for all team members |
| `src/.../env_config.py` | Yes | ML Lead / platform engineer only | **High**: adding or removing fields changes the runtime contract |
| `src/.../pipeline_run_config.py` | Yes | ML Lead / platform engineer only | **High**: changes how YAML fields are loaded and validated |

---

## Common Mistakes and How to Fix Them

### Mistake 1: MLflow candidate run produced no entries in the MLflow UI

**Symptom**: Pipeline exits with code 0, artifact directory was created, but the
MLflow UI shows no new experiments or runs.

**Cause**: `TRAINING_RUNTIME_MODE` was not set to `mlflow_candidate_review` in
`.env`. The pipeline ran in `local_artifact_only` mode, which never contacts
MLflow.

**Fix**: Open `.env` and confirm:
```
TRAINING_RUNTIME_MODE=mlflow_candidate_review
```
Then rerun.

---

### Mistake 2: Pipeline fails with a connection error at Phase 4

**Symptom**: Phases 1–3 succeed, then Phase 4 (Model Training) fails with a
connection refused or MLflow server not found error.

**Cause**: `TRAINING_RUNTIME_MODE=mlflow_candidate_review` is set but the MLflow
server is not running.

**Fix**: In a separate terminal, start the server first:
```bash
bash training-control-plane/start-mlflow-server.sh
```
Wait until you see `Listening at: http://127.0.0.1:5000`, then resubmit the run.

---

### Mistake 3: Two runs produce different metrics despite "same config"

**Symptom**: Two pipeline runs on the same dataset produce different test-split
metrics even though `training_pipeline.yaml` looks identical.

**Cause**: `RANDOM_SEED` was set differently in `.env` for one of the runs, or
`random_seed` in the YAML was changed between runs. Different seeds produce
different train/test splits, so test-split metrics are not comparable.

**Fix**: Confirm that `RANDOM_SEED` is not set in `.env` (remove the line if
present) and that `random_seed: 42` in `training_pipeline.yaml` has not changed.
Both runs must use the same seed to produce a valid metric comparison.

---

### Mistake 4: OPTUNA_N_TRIALS in .env is ignored

**Symptom**: You set `OPTUNA_N_TRIALS=3` in `.env` but the pipeline runs 60 trials.

**Cause**: You are running from a directory other than `ml-training/`. Pydantic
Settings loads `.env` relative to the working directory. If you run from the repo
root, `.env` is not found and the YAML default (60) is used.

**Fix**: Always run the training pipeline from the `ml-training/` directory:
```bash
cd k8s_mlops/ml-training
uv run run-training-pipeline
```

---

### Mistake 5: A new model family was added to the YAML but the search ignores it

**Symptom**: You added a new entry to `model_families` in `training_pipeline.yaml`
but Optuna never samples that family.

**Cause**: The family name in the YAML does not match a key in
`SEARCH_SPACE_REGISTRY` in
`src/wine_quality_training/training/hyperparameter_search_config.py`.

**Fix**: Open `hyperparameter_search_config.py` and confirm that `SEARCH_SPACE_REGISTRY`
has an entry with exactly the same key string you added to the YAML. The
registry key and the YAML entry must be identical (case-sensitive).

---

## Enterprise Translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| `.env` file at module root | Kubernetes ConfigMap (non-secret values) + Secret (credentials) mounted as environment variables | Kubernetes injects config at pod start. No file to copy; no gitignore risk. |
| `training_pipeline.yaml` committed to Git | ConfigMap created from the YAML file via CI, mounted into the Job pod at a known path | ConfigMap changes trigger a new Job without rebuilding the container image. |
| Pydantic defaults for local fallbacks | No fallbacks in production — every required value must be explicitly set in the ConfigMap or Job spec | Defaults hide missing configuration. Production systems fail loudly when config is absent. |
| Single `training_pipeline.yaml` for all runs | Separate ConfigMaps per environment (dev, staging, prod) with different `n_trials` and compute budgets | Cost and risk are controlled at the environment level, not per-run. |
| `TRAINING_TRIGGERED_BY=shubham` in `.env` | `TRAINING_TRIGGERED_BY` injected by CI system (GitHub Actions runner name, service account) | In CI, the triggering identity is the authenticated principal, not a manually typed name. |
