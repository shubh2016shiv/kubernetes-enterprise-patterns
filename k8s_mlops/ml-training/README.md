# Wine Quality Training Pipeline

Enterprise-style ML training pipeline for wine cultivar classification.
Built to demonstrate how a real ML training workflow is structured before
it is containerised and executed as a Kubernetes Job.

---

## Table of Contents

1. [Purpose and Scope](#1-purpose-and-scope)
2. [System Design Overview](#2-system-design-overview)
3. [ML Lifecycle Phase Map](#3-ml-lifecycle-phase-map)
4. [Phase-by-Phase Explanation](#4-phase-by-phase-explanation)
   - [Phase 1 — Data Ingestion](#phase-1--data-ingestion)
   - [Phase 2 — Data Validation](#phase-2--data-validation)
   - [Phase 3 — Feature Engineering](#phase-3--feature-engineering)
   - [Phase 4 — Model Training](#phase-4--model-training)
   - [Phase 5 — Model Evaluation](#phase-5--model-evaluation)
   - [Phase 6 — Artifact Registration](#phase-6--artifact-registration)
5. [Artifact Store Structure](#5-artifact-store-structure)
6. [Hyperparameter Search Design](#6-hyperparameter-search-design)
7. [Configuration Architecture](#7-configuration-architecture)
8. [Kubernetes Mapping](#8-kubernetes-mapping)
9. [Environment Setup](#9-environment-setup)
10. [Running the Pipeline](#10-running-the-pipeline)
11. [Running the Tests](#11-running-the-tests)
12. [Production Readiness Notes](#12-production-readiness-notes)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Purpose and Scope

This module implements the ML training pipeline for the `k8s_mlops` project.
Its scope ends at the model artifact. It does not include model serving,
inference APIs, or Kubernetes Job manifests — those live in sibling modules.

The goal of this module is to answer one question clearly:

> How is a production-grade ML training pipeline structured before it is
> handed to Kubernetes for execution?

The answer this project demonstrates:

- Training is not a single script. It is a sequence of named, isolated phases,
  each with a single responsibility.
- Each phase produces a typed output that is the input to the next phase.
- Failure in any phase halts the pipeline with a specific exit code and a
  clear log message.
- The trained model is never just a `.pkl` file dropped somewhere. It is a
  versioned artifact bundle with metrics, schema, hyperparameters, and a
  complete lineage record.
- Configuration never lives in Python code. It lives in a YAML file that
  Kubernetes mounts from a ConfigMap.

The dataset used is the UCI Wine dataset from `sklearn.datasets`. It is a
three-class classification problem across 178 samples and 13 chemical
measurement features. The dataset is intentionally simple so that the
infrastructure and lifecycle design remain in focus — not the model itself.

---

## 2. System Design Overview

The diagram below shows the full pipeline from environment bootstrap to
registered artifact, including the data flow between phases and the
Kubernetes objects that correspond to each concern in production.

```
  ┌─────────────────────────────────────────────────────────────────────┐
  │  Kubernetes Training Job (mlops namespace)                           │
  │                                                                     │
  │  ┌─────────────────────┐    ┌──────────────────────────────────┐    │
  │  │ ConfigMap            │    │ PersistentVolumeClaim            │    │
  │  │ training_pipeline    │    │ artifact-store-pvc               │    │
  │  │ .yaml mounted at     │    │ mounted at /mnt/artifact-store   │    │
  │  │ /etc/mlops/config/   │    │ (local: artifacts/)              │    │
  │  └──────────┬──────────┘    └────────────────┬─────────────────┘    │
  │             │ PIPELINE_CONFIG_PATH env var    │ ARTIFACT_STORE_ROOT  │
  │             │                                │ env var              │
  │             ▼                                ▼                      │
  │  ┌──────────────────────────────────────────────────────────────┐   │
  │  │  run_training_pipeline.py  (pipeline orchestrator)            │   │
  │  │                                                              │   │
  │  │  Phase 1 ──► Phase 2 ──► Phase 3 ──► Phase 4 ──► Phase 5 ──►│   │
  │  │  Ingestion   Validation  Feature     Training    Evaluation  │   │
  │  │                          Engineering                         │   │
  │  │                                                  Phase 6 ───►│   │
  │  │                                                  Artifact     │   │
  │  │                                                  Registration │   │
  │  └──────────────────────────────────────────────────────────────┘   │
  │                                                                     │
  └──────────────────────────────────┬──────────────────────────────────┘
                                     │
                                     ▼
              ┌──────────────────────────────────────────┐
              │  artifacts/wine_quality_classifier/       │
              │  v_YYYY-MM-DD_NNN/                        │
              │    model.joblib                           │
              │    metrics.json                           │
              │    training_config.json                   │
              │    feature_schema.json                    │
              │    run_manifest.json                      │
              └──────────────────────────────────────────┘
```

Each phase is a Python module with a single public function. The orchestrator
calls them in sequence and passes typed dataclass outputs between them. No
phase reads from disk or environment variables directly — those concerns
belong to the orchestrator and the shared config loader.

---

## 3. ML Lifecycle Phase Map

The following table maps each pipeline phase to its responsible module, the
Kubernetes object that would run it in a fully decomposed pipeline, and the
enterprise concern it addresses.

```
Phase               Module                              K8s Object    Enterprise Concern
──────────────────  ──────────────────────────────────  ────────────  ─────────────────────────────────────
1. Data Ingestion   data_ingestion/load_wine_dataset    Job           Data lineage, access control, versioning
2. Data Validation  data_validation/validate_training   Job           Schema contracts, drift detection
                    _schema
3. Feature Eng.     feature_engineering/build_wine      Job           Reproducible splits, training-serving skew
                    _features
4. Model Training   training/wine_quality_model_trainer Job           Compute scheduling, cost control
5. Evaluation       evaluation/evaluate_wine_quality    Job           Promotion gates, auditability
                    _model
6. Registration     model_registry/register_model       Job           Artifact versioning, lineage traceability
                    _artifact
```

In the current implementation, all six phases execute inside one Job (the
orchestrator). In a production Argo Workflows or Kubeflow Pipelines setup,
each phase would be a separate Kubernetes Job or container step in a DAG,
enabling individual retry, resource allocation, and failure isolation per phase.

---

## 4. Phase-by-Phase Explanation

### Phase 1 — Data Ingestion

**Module:** `src/wine_quality_training/data_ingestion/load_wine_dataset.py`

**What it does:**
Loads the UCI Wine dataset from `sklearn.datasets.load_wine`. Normalises
feature column names to snake_case descriptive names (e.g. `alcohol`,
`malic_acid`, `od280_od315_of_diluted_wines`). Returns an immutable
`RawWineDataset` dataclass that carries the feature matrix, target vector,
class names, and a SHA-256 hash of the dataset contents.

**Output:** `RawWineDataset`

```
RawWineDataset
  ├── features: DataFrame (178 rows × 13 columns)
  ├── targets: Series (178 values, classes 0/1/2)
  ├── feature_names: list[str]  (13 names)
  ├── target_class_names: list[str]  ["class_0", "class_1", "class_2"]
  ├── dataset_content_hash: str  (SHA-256 of feature + target bytes)
  ├── n_samples: 178
  └── n_features: 13
```

**Why the dataset hash matters:**

The `dataset_content_hash` field is a SHA-256 fingerprint of the raw data.
It is computed once here and carried through every subsequent phase. In Phase 6
it is written into `run_manifest.json`.

```
Enterprise scenario:
  A data engineer updates the upstream feature table. The next
  training run produces a new dataset_content_hash. A reviewer
  comparing two run_manifest.json files immediately sees that the
  inputs changed — even if the model metrics look identical.
  Without the hash, this change is invisible.
```

**In a real enterprise pipeline:**
This phase would call a feature store SDK (Feast, Tecton), read from a
Delta Lake partition, or pull from a versioned dataset registry. The
data access would be gated by a Kubernetes ServiceAccount with an RBAC
binding to the appropriate data access role.

---

### Phase 2 — Data Validation

**Module:** `src/wine_quality_training/data_validation/validate_training_schema.py`

**What it does:**
Runs seven structural and statistical checks on the raw dataset before any
transformation occurs. If any mandatory check fails, it raises
`DataValidationError` and the orchestrator exits with code `2`, causing
the Kubernetes Job to record a failure immediately — no compute is wasted
on training from bad data.

**Checks performed:**

```
Check                         What it catches
────────────────────────────  ─────────────────────────────────────────────
Feature count == 13           Upstream added or dropped a column
All expected columns present  Column was renamed in upstream schema
Feature dtypes are float      Upstream changed type (e.g. string encoding)
No missing values             Upstream left nulls in the export
Target has exactly 3 classes  New class added or class collapsed upstream
Each class >= 30 samples      Class undersampling from upstream filter
Values within physical bounds  Sensor drift, unit change, data entry error
```

**Output:** `DataValidationReport`

```
DataValidationReport
  ├── n_samples: int
  ├── class_distribution: {0: 59, 1: 71, 2: 48}
  ├── missing_value_counts: {feature_name: count, ...}
  ├── out_of_bounds_counts: {feature_name: count, ...}
  ├── validation_passed: bool
  └── failure_reasons: list[str]
```

**Data flow diagram:**

```
  RawWineDataset
       │
       ▼
  ┌────────────────────────────────────┐
  │  validate_wine_training_schema()   │
  │                                    │
  │  ✓ feature count        pass/fail  │
  │  ✓ column presence      pass/fail  │
  │  ✓ dtype check          pass/fail  │
  │  ✓ null check           pass/fail  │
  │  ✓ class count          pass/fail  │
  │  ✓ class sample size    pass/fail  │
  │  ✓ value bounds         warn/fail  │
  └────────────┬───────────────────────┘
               │
       ┌───────┴──────────┐
       │                  │
       ▼                  ▼
  DataValidationReport   DataValidationError
  (passed=True)          (pipeline halts, exit 2)
```

**Enterprise scenario:**

```
A data pipeline team changes the upstream ETL to normalise the
"magnesium" column by dividing by 100. The values now fall between
0.6 and 1.65 instead of 60 to 165. The physical bounds check
detects 178 out-of-bounds values and raises DataValidationError.

Without this check, the training run would complete and register
an artifact. The model would look healthy in metrics because it
was trained and evaluated on the same (wrong) scale. It would
fail silently in production when it receives properly-scaled inputs.
```

---

### Phase 3 — Feature Engineering

**Module:** `src/wine_quality_training/feature_engineering/build_wine_features.py`

**What it does:**
Produces a stratified train/test split from the validated dataset and computes
a `FeatureSchema` that records training-partition statistics for all 13 features.

**Key design decisions:**

**Stratified splitting:**
`StratifiedShuffleSplit` is used instead of a random split to ensure that each
cultivar class is represented proportionally in both partitions. With only 178
samples, a random split could easily produce a test set missing one class entirely.

```
  178 samples (3 classes)
       │
       ▼  StratifiedShuffleSplit(test_size=0.20, random_state=42)
  ┌────────────────────────────────────────────────┐
  │  Train split (142 samples, ~80%)               │
  │    class_0: ~47 samples                        │
  │    class_1: ~57 samples                        │
  │    class_2: ~38 samples                        │
  └────────────────────────────────────────────────┘
  ┌────────────────────────────────────────────────┐
  │  Test split (36 samples, ~20%)                 │
  │    class_0: ~12 samples                        │
  │    class_1: ~14 samples                        │
  │    class_2: ~10 samples                        │
  └────────────────────────────────────────────────┘
```

**Scaling is intentionally absent here:**
`StandardScaler` is included inside the sklearn `Pipeline` in Phase 4, not here.
This is deliberate: the scaler must be fitted only on training data. If scaling
were applied before the split, test statistics would leak into the scaler's
learned mean and variance, inflating evaluation metrics.

**The FeatureSchema contract:**
Statistics are computed from the training partition only and written to
`feature_schema.json` in the artifact store. The inference service loads this
schema at startup to validate incoming prediction requests.

```
FeatureSchema
  ├── feature_names: ["alcohol", "malic_acid", ..., "proline"]
  ├── feature_statistics:
  │     alcohol:     {mean: 13.0, std: 0.81, min: 11.0, max: 14.8, p25: 12.4, p75: 13.7}
  │     malic_acid:  {mean: 2.3,  std: 1.12, min: 0.74, max: 5.8,  p25: 1.6,  p75: 3.1}
  │     ...
  ├── target_column: "wine_cultivar_class"
  ├── target_class_names: ["class_0", "class_1", "class_2"]
  ├── train_size: 142
  ├── test_size: 36
  └── stratified_split: true
```

**Enterprise scenario:**

```
The inference API receives a prediction request where the caller
passes "colour_intensity" instead of "color_intensity" (British spelling).
The schema check at the API boundary catches the mismatch and returns
HTTP 422 before the request reaches the model. Without the schema,
the model would receive a feature vector with a missing column and
either crash or return a wrong prediction silently.
```

---

### Phase 4 — Model Training

**Modules:**
- `src/wine_quality_training/training/training_pipeline_config.py`
- `src/wine_quality_training/training/hyperparameter_search_config.py`
- `src/wine_quality_training/training/wine_quality_model_trainer.py`

**What it does:**
Runs an Optuna hyperparameter search across three model families
(RandomForest, GradientBoosting, LogisticRegression). Each trial is scored
by stratified 5-fold cross-validation on the training split. The test split
is never touched. After the study completes, the best trial's pipeline is
refit on the full training split.

**Search architecture:**

```
  ┌─────────────────────────────────────────────────────────────────┐
  │  Optuna Study  (60 trials, TPE sampler, direction=maximize)      │
  │                                                                  │
  │  Each trial:                                                     │
  │    1. suggest model_family ─► one of [RF, GB, LR]               │
  │    2. suggest hyperparams  ─► family-specific search space       │
  │    3. build sklearn Pipeline(StandardScaler + classifier)        │
  │    4. StratifiedKFold(n=5) cross_val_score on X_train            │
  │    5. return mean balanced_accuracy across 5 folds               │
  │                                                                  │
  │  Objective: maximize mean balanced_accuracy (5-fold CV)          │
  └──────────────────────────────┬──────────────────────────────────┘
                                 │
                    best trial identified
                                 │
                                 ▼
  ┌──────────────────────────────────────────────────────────────────┐
  │  Refit best pipeline on full X_train (142 samples)               │
  │    Pipeline(StandardScaler → best_classifier(best_hyperparams))  │
  └──────────────────────────────────────────────────────────────────┘
```

**Model families and their search spaces:**

| Model Family         | Key Parameters Searched                             |
|----------------------|-----------------------------------------------------|
| RandomForest         | n_estimators, max_depth, min_samples_split, max_features, class_weight |
| GradientBoosting     | n_estimators, learning_rate (log scale), max_depth, subsample, max_features |
| LogisticRegression   | C (log scale), penalty (l1/l2), max_iter, class_weight |

**Why cross-validation instead of a held-out validation set:**

With 142 training samples, a single random validation split is too small
to give a stable estimate of model performance. A 5-fold CV uses all 142
samples for both training and validation across folds, giving a more reliable
signal for the Optuna objective. The test split (36 samples) is preserved
exclusively for the evaluation phase.

```
  CV fold structure on 142 training samples:
  ┌────────┬────────┬────────┬────────┬────────┐
  │ Fold 1 │ Fold 2 │ Fold 3 │ Fold 4 │ Fold 5 │  ◄─ 5 × ~114 train + ~28 validate
  └────────┴────────┴────────┴────────┴────────┘
  mean(score_fold_1 ... score_fold_5) → trial objective value
```

**The sklearn Pipeline design:**

Every model is wrapped in a `sklearn.pipeline.Pipeline` with two steps:

```python
Pipeline([
    ("scaler", StandardScaler()),
    ("classifier", <model_family>(**hyperparams)),
])
```

The Pipeline is serialised as a single `model.joblib` file. This means:
- The scaler's learned mean and variance are inseparable from the classifier.
- The inference service calls `pipeline.predict(X)` without needing to know
  that scaling happened.
- There is no risk of the scaler being loaded separately with wrong parameters.

**Enterprise scenario:**

```
In production, the GradientBoosting training image is allocated
4 vCPUs via resource limits in the Job spec. The Optuna search runs
n_jobs=-1 inside cross_val_score, saturating all 4 cores across
CV folds. A second training Job scheduled in parallel receives
its own 4 vCPUs from a different node pool without contention.

Without resource limits, two concurrent training Jobs could
contend for CPU on the same node, making both slower and making
CV score estimates unstable — a subtle form of non-determinism
that is hard to diagnose from logs alone.
```

---

### Phase 5 — Model Evaluation

**Module:** `src/wine_quality_training/evaluation/evaluate_wine_quality_model.py`

**What it does:**
Runs the fitted pipeline against the held-out test split and computes a
comprehensive set of classification metrics. Compares the primary metric
(`balanced_accuracy`) against the promotion threshold defined in the
pipeline config (default 0.85).

**Metrics computed:**

```
Overall metrics (multi-class, test split):
  accuracy              overall fraction correct
  balanced_accuracy     mean recall per class (penalises class imbalance)
  macro_f1              unweighted mean F1 across classes
  weighted_f1           class-frequency-weighted mean F1
  macro_precision       unweighted mean precision across classes
  macro_recall          unweighted mean recall across classes

Per-class breakdown:
  per_class_f1          {class_0: 1.0, class_1: 1.0, class_2: 1.0}
  per_class_precision   {class_0: 1.0, class_1: 1.0, class_2: 1.0}
  per_class_recall      {class_0: 1.0, class_1: 1.0, class_2: 1.0}

Confusion matrix (actual v. predicted, 36 test samples):
              Predicted
              class_0  class_1  class_2
  Actual
  class_0  [   12         0        0   ]
  class_1  [    0        14        0   ]
  class_2  [    0         0       10   ]
```

**Promotion gate logic:**

```
  balanced_accuracy >= 0.85
         │
    ┌────┴────┐
    │         │
   YES        NO
    │         │
    ▼         ▼
  Phase 6   Artifact still registered
  proceeds  (evaluation_passed=false)
  exit 0    Pipeline exits with code 3
            (signals gate failure to K8s Job)
```

The artifact is always registered even when the gate fails. This is intentional:
a failed run's artifact is still a complete audit record. An operator can inspect
`metrics.json` to understand why the gate failed, without needing to re-run training.

**Why `balanced_accuracy` and not plain `accuracy`:**

The wine dataset has slight class imbalance (59 class_0, 71 class_1, 48 class_2).
A classifier that always predicts class_1 would achieve ~40% plain accuracy, which
sounds high enough to look acceptable. `balanced_accuracy` is the mean recall per
class and would score such a classifier at 33% — correctly exposing the problem.

**Enterprise scenario:**

```
Month 3: The training team changes the dataset preprocessing to
oversample class_2 (which was historically underrepresented). The new
model achieves balanced_accuracy=0.92 versus the previous 0.88. The
metrics.json from both versions are compared in a model review meeting.
The improvement is traceable to a specific run_manifest.json that
records the dataset_content_hash of the oversampled dataset.

Without structured metrics stored alongside the artifact, this
comparison would require re-running old training code against old data
— expensive, fragile, and often impossible when old data is no longer
in the same state.
```

---

### Phase 6 — Artifact Registration

**Modules:**
- `src/wine_quality_training/model_registry/artifact_version_resolver.py`
- `src/wine_quality_training/model_registry/register_model_artifact.py`

**What it does:**
Resolves the next version string for this model, creates a versioned directory
in the artifact store, and writes five files. The version string is
deterministic, human-readable, and collision-free across concurrent runs.

**Version scheme:**

```
  v_YYYY-MM-DD_NNN

  Example progression on 2026-04-25:
    v_2026-04-25_001  ◄─ first run of the day
    v_2026-04-25_002  ◄─ second run (different hyperparams or data)
    v_2026-04-25_003
    ...
    v_2026-04-26_001  ◄─ first run the next day (sequence resets)
```

The version resolver scans existing directories under
`artifacts/wine_quality_classifier/` to find the highest sequence number
used on today's date, then increments it. This makes the next version
collision-free even if two runs start within seconds of each other on
different nodes (as long as they write to the same shared storage).

**Files written per version:**

```
artifacts/wine_quality_classifier/v_2026-04-25_001/
  │
  ├── model.joblib
  │     The fitted sklearn Pipeline (StandardScaler + classifier).
  │     Loaded by the inference service with joblib.load().
  │     Compressed at level 3 to reduce storage on the PVC.
  │
  ├── metrics.json
  │     All evaluation metrics from the test split.
  │     Used by the promotion gate and model review process.
  │
  ├── training_config.json
  │     The exact hyperparameters chosen by Optuna.
  │     Allows exact reproduction of the trained model.
  │
  ├── feature_schema.json
  │     Feature names, training-partition statistics, target classes.
  │     Loaded by the inference service to validate requests.
  │
  └── run_manifest.json
        Complete lineage record. Contains:
          schema_version         version of the manifest format itself
          model_name             wine_quality_classifier
          version                v_2026-04-25_001
          experiment_name        wine-quality-cultivar-classification-v1
          registered_at_utc      ISO 8601 timestamp
          python_version         3.12.11
          platform               Windows / Linux
          git_commit_sha         short SHA of HEAD at training time
          dataset_content_hash   SHA-256 of raw feature + target bytes
          model_artifact_sha256  SHA-256 of model.joblib
          model_family           gradient_boosting
          n_training_samples     142
          n_test_samples         36
          n_features             13
          cv_metric              balanced_accuracy
          best_cv_score          1.0
          balanced_accuracy_test 1.0
          evaluation_passed      true
          promotion_threshold    0.85
```

**Artifact traceability chain:**

```
  run_manifest.json
       │
       ├── git_commit_sha ──────────────────► git log --oneline <sha>
       │                                       (what code produced this?)
       │
       ├── dataset_content_hash ────────────► SHA-256 of raw input bytes
       │                                       (what data produced this?)
       │
       ├── model_artifact_sha256 ───────────► SHA-256 of model.joblib
       │                                       (is this the authentic artifact?)
       │
       ├── training_config.json ────────────► exact hyperparameters
       │                                       (can we reproduce this model?)
       │
       └── metrics.json ────────────────────► balanced_accuracy, f1, etc.
                                               (was this model good enough?)
```

**Enterprise scenario:**

```
A production incident shows that the deployed model is making wrong
predictions on class_2 samples. The SRE team checks the inference
service's MODEL_VERSION env var, which reads "v_2026-04-25_001".
They open run_manifest.json for that version:
  - git_commit_sha: c27ca54  → maps to the exact code commit
  - dataset_content_hash     → confirms which data snapshot was used
  - per_class_f1.class_2: 1.0 → evaluation passed at training time
The issue is in the serving layer, not the model itself.
This diagnosis took 2 minutes because every artifact is a complete
audit record. Without run_manifest.json, the team would need to
reconstruct the training environment from scratch.
```

---

## 5. Artifact Store Structure

```
artifacts/
└── wine_quality_classifier/
    ├── v_2026-04-25_001/          ← first run
    │   ├── model.joblib           (406 KB compressed sklearn Pipeline)
    │   ├── metrics.json           (test-split classification metrics)
    │   ├── training_config.json   (Optuna-chosen hyperparameters)
    │   ├── feature_schema.json    (feature contract for inference)
    │   └── run_manifest.json      (complete lineage record)
    ├── v_2026-04-25_002/          ← second run same day
    │   └── ...
    └── v_2026-04-26_001/          ← first run next day
        └── ...
```

The `artifacts/` directory is local in this project. In Kubernetes, it maps
to the `mountPath` of a `PersistentVolumeClaim` in the Job spec:

```yaml
volumeMounts:
  - name: artifact-store
    mountPath: /mnt/artifact-store
volumes:
  - name: artifact-store
    persistentVolumeClaim:
      claimName: mlops-artifact-store-pvc
```

In production, the PVC would be backed by:
- **AWS:** EFS (shared) or S3 via a CSI driver
- **GCP:** Filestore or GCS via the GCS FUSE CSI driver
- **Azure:** Azure Files or Blob Storage via the Azure CSI driver

---

## 6. Hyperparameter Search Design

Optuna uses the Tree-structured Parzen Estimator (TPE) sampler. TPE is a
Bayesian optimisation algorithm that builds a probabilistic model of which
hyperparameter regions produce high objective values, and samples more
aggressively from those regions as the study accumulates evidence.

This is in contrast to a grid search or random search:

```
  Grid search:    exhaustive, combinatorial explosion, poor for continuous params
  Random search:  uniform sampling, no learning from prior trials
  TPE (Optuna):   Bayesian, adapts to good regions, efficient on continuous params
```

The cross-validation objective (5-fold `balanced_accuracy` on `X_train`) is
the single signal TPE learns from. The test split is never part of this signal.

**Trial budget:**
60 trials are distributed across 3 model families. The model family is itself
a categorical hyperparameter inside the study. This means the study can
discover mid-search that one family dominates and allocate more trials to it —
which is more efficient than splitting 20 trials per family manually.

**Reproducibility:**
The TPE sampler is seeded with `random_seed` from the pipeline config. The
same config file always produces the same trial sequence, which means the same
best hyperparameters and (given the same dataset) the same model artifact.

---

## 7. Configuration Architecture

All runtime values are externalized. No value that changes between local
development, staging, and production is hardcoded in Python.

```
  Source of truth          Value                       Consumer
  ─────────────────────    ──────────────────────────  ──────────────────────
  Environment variable     ARTIFACT_STORE_ROOT         env_config.py
  Environment variable     PIPELINE_CONFIG_PATH        env_config.py
  Environment variable     LOG_LEVEL                   env_config.py
  Environment variable     OPTUNA_N_TRIALS             env_config.py (override)
  Environment variable     RANDOM_SEED                 env_config.py (override)
  training_pipeline.yaml   experiment_name             training_pipeline_config.py
  training_pipeline.yaml   model_families              training_pipeline_config.py
  training_pipeline.yaml   test_size, random_seed      training_pipeline_config.py
  training_pipeline.yaml   cv_folds                    training_pipeline_config.py
  training_pipeline.yaml   optuna.n_trials, metric     training_pipeline_config.py
```

`env_config.py` validates required variables at startup with a fast-fail
pattern. If `ARTIFACT_STORE_ROOT` or `PIPELINE_CONFIG_PATH` are absent, the
Job exits with code `1` immediately and Kubernetes marks it as failed — before
any expensive computation starts.

In Kubernetes, the environment variables come from:

```yaml
env:
  - name: ARTIFACT_STORE_ROOT
    value: /mnt/artifact-store
  - name: PIPELINE_CONFIG_PATH
    value: /etc/mlops/config/training_pipeline.yaml
  - name: LOG_LEVEL
    valueFrom:
      configMapKeyRef:
        name: wine-training-env-config
        key: log_level
```

---

## 8. Kubernetes Mapping

This pipeline is designed to run as a Kubernetes `Job`. The table below
maps each design decision to the Kubernetes object that enforces or supports it.

```
Design Decision                           Kubernetes Object / Field
────────────────────────────────────────  ─────────────────────────────────────────
Pipeline config (training_pipeline.yaml)  ConfigMap (volume mount)
Artifact store path                       PersistentVolumeClaim (volume mount)
Runtime env vars                          ConfigMap (envFrom or env.valueFrom)
Credentials (future: registry, storage)  Secret (env.valueFrom)
Training Job lifecycle                    Job (restartPolicy: Never)
Retry on transient failure                Job (backoffLimit: 2)
CPU / memory bounds                       resources.requests + resources.limits
Log collection                            stdout → cluster log aggregator (Loki)
Job scheduling on CPU node pool           nodeSelector / affinity rules
Namespace isolation                       namespace: mlops
Auditability (labels + annotations)       app.kubernetes.io/name, version labels
```

**Sample Job resource block (to be added to K8s manifests module):**

```yaml
resources:
  requests:
    cpu: "1"
    memory: "2Gi"
  limits:
    cpu: "4"
    memory: "4Gi"
# ENTERPRISE EMPHASIS: The training phase uses n_jobs=-1 in cross_val_score,
# which spawns one process per CPU core. Setting cpu.limits=4 gives Optuna
# 4 parallel CV workers per trial. Setting it to 1 would make the search
# 4x slower. Setting it unbounded would let the Job starve other workloads.
```

**Pipeline exit codes and their Kubernetes meaning:**

```
Exit code  Reason                         Kubernetes Job status   Action
─────────  ─────────────────────────────  ──────────────────────  ─────────────────────────
0          All phases succeeded            Succeeded               None
1          Missing env var / bad config    Failed (no retry)       Fix ConfigMap or Secret
2          Data validation failure         Failed (no retry)       Investigate upstream data
3          Evaluation threshold not met    Failed (no retry)       Review metrics, tune config
4          Unexpected runtime error        Failed (retry up to 2)  Check logs, report bug
```

Using distinct exit codes allows a CI/CD system or Argo Workflows step to
make intelligent routing decisions: code 2 triggers a data quality alert,
code 3 triggers a model review notification, code 4 triggers a retry.

---

## 9. Environment Setup

This project uses [uv](https://docs.astral.sh/uv/) for dependency management.
The virtual environment is self-contained inside `ml-training/.venv/` and
isolated from any other Python environment on the machine.

**Prerequisites:**
- `uv` installed (`pip install uv` or `curl -LsSf https://astral.sh/uv/install.sh | sh`)
- Python 3.11 or newer (uv downloads and manages this automatically)

**Install all dependencies:**

```bash
cd k8s_mlops/ml-training
uv sync
```

`uv sync` reads `pyproject.toml`, resolves the full dependency graph, creates
`.venv/`, and installs all packages including dev dependencies (pytest).

Expected output:
```
Using CPython 3.12.x
Creating virtual environment at: .venv
Resolved 29 packages in ...
Installed 28 packages in ...
```

**Dependencies:**

| Package        | Version  | Purpose                                      |
|----------------|----------|----------------------------------------------|
| scikit-learn   | ≥ 1.5    | ML models, preprocessing, cross-validation   |
| optuna         | ≥ 3.6    | Bayesian hyperparameter search               |
| numpy          | ≥ 1.26   | Numerical array operations                   |
| pandas         | ≥ 2.2    | Tabular data handling                        |
| joblib         | ≥ 1.4    | Model serialisation                          |
| pyyaml         | ≥ 6.0    | Pipeline config parsing                      |
| pytest         | ≥ 8.0    | Unit testing (dev only)                      |
| pytest-cov     | ≥ 5.0    | Test coverage reporting (dev only)           |

---

## 10. Running the Pipeline

The pipeline reads two required environment variables. Set them before running.

**Local run (from `ml-training/` directory):**

```bash
# Set required environment variables
export ARTIFACT_STORE_ROOT=artifacts
export PIPELINE_CONFIG_PATH=configs/training_pipeline.yaml

# Run the pipeline
uv run python -m wine_quality_training.pipeline.run_training_pipeline
```

**Optional overrides:**

```bash
# Change Optuna trial count (overrides YAML value)
export OPTUNA_N_TRIALS=30

# Change log verbosity
export LOG_LEVEL=DEBUG

# Use a different random seed (affects train/test split and model init)
export RANDOM_SEED=123
```

**Expected terminal output:**

```
2026-04-25T01:44:07 | INFO | pipeline_orchestrator | ... | Wine Quality Training Pipeline — START
2026-04-25T01:44:07 | INFO | pipeline_orchestrator | ... | Configuration loaded
2026-04-25T01:44:07 | INFO | pipeline_orchestrator | ... | --- Phase 1: Data Ingestion ---
2026-04-25T01:44:07 | INFO | data_ingestion        | ... | Loading UCI Wine dataset from sklearn.datasets
2026-04-25T01:44:07 | INFO | data_ingestion        | ... | Dataset loaded successfully
2026-04-25T01:44:07 | INFO | pipeline_orchestrator | ... | Phase 1 complete (0.02s)
2026-04-25T01:44:07 | INFO | pipeline_orchestrator | ... | --- Phase 2: Data Validation ---
  ...
2026-04-25T01:45:07 | INFO | pipeline_orchestrator | ... | --- Phase 4: Model Training ---
  ... (60 Optuna trials, ~60 seconds)
2026-04-25T01:45:08 | INFO | model_evaluation      | ... | Evaluation PASSED (threshold=0.85)
2026-04-25T01:45:09 | INFO | pipeline_orchestrator | ... | Wine Quality Training Pipeline — COMPLETE
```

**Every run creates a new version directory:**

```
# First run
artifacts/wine_quality_classifier/v_2026-04-25_001/

# Second run (same day, same or different config)
artifacts/wine_quality_classifier/v_2026-04-25_002/

# Re-running never overwrites a previous version.
```

---

## 11. Running the Tests

```bash
cd k8s_mlops/ml-training
uv run pytest tests/unit/ -v
```

Expected output:
```
collected 25 items

tests/unit/test_artifact_versioning.py::test_first_version_on_empty_store     PASSED
tests/unit/test_artifact_versioning.py::test_version_format_matches_pattern   PASSED
tests/unit/test_artifact_versioning.py::test_second_run_same_day_increments   PASSED
tests/unit/test_artifact_versioning.py::test_new_day_resets_sequence          PASSED
tests/unit/test_artifact_versioning.py::test_list_versions_returns_sorted     PASSED
tests/unit/test_artifact_versioning.py::test_get_latest_returns_most_recent   PASSED
tests/unit/test_artifact_versioning.py::test_get_latest_returns_none          PASSED
tests/unit/test_artifact_versioning.py::test_list_ignores_non_version_dirs    PASSED
tests/unit/test_data_validation.py::test_valid_dataset_passes_validation      PASSED
tests/unit/test_data_validation.py::test_correct_sample_count                 PASSED
tests/unit/test_data_validation.py::test_carries_three_classes                PASSED
tests/unit/test_data_validation.py::test_missing_column_raises_error          PASSED
tests/unit/test_data_validation.py::test_missing_values_raises_error          PASSED
tests/unit/test_data_validation.py::test_wrong_class_count_raises_error       PASSED
tests/unit/test_feature_engineering.py::test_split_sizes_sum_to_total         PASSED
tests/unit/test_feature_engineering.py::test_test_size_approximately_20pct    PASSED
tests/unit/test_feature_engineering.py::test_feature_names_match_expected     PASSED
tests/unit/test_feature_engineering.py::test_schema_feature_names_match       PASSED
tests/unit/test_feature_engineering.py::test_schema_three_target_classes      PASSED
tests/unit/test_feature_engineering.py::test_statistics_cover_all_features    PASSED
tests/unit/test_feature_engineering.py::test_statistics_have_expected_keys    PASSED
tests/unit/test_feature_engineering.py::test_all_classes_in_test_split        PASSED
tests/unit/test_feature_engineering.py::test_y_train_X_train_lengths_match    PASSED
tests/unit/test_feature_engineering.py::test_y_test_X_test_lengths_match      PASSED
tests/unit/test_feature_engineering.py::test_reproducibility_same_seed        PASSED

25 passed in 2.19s
```

**Test coverage by module:**

| Test file                     | What it covers                                              |
|-------------------------------|-------------------------------------------------------------|
| `test_data_validation.py`     | Valid dataset passes; missing column, null values, wrong class count all raise `DataValidationError` |
| `test_feature_engineering.py` | Split sizes, stratification, schema metadata, reproducibility with same seed |
| `test_artifact_versioning.py` | Version format, day-sequence incrementing, date rollover, latest version lookup, non-version directory filtering |

---

## 12. Production Readiness Notes

**What this pipeline gets right for production:**

| Concern              | How it is addressed                                                   |
|----------------------|-----------------------------------------------------------------------|
| Reproducibility      | Fixed `random_seed` in config; dataset hash in manifest               |
| Auditability         | `run_manifest.json` traces git SHA, data hash, config, metrics        |
| Training-serving skew| `feature_schema.json` published with every artifact                   |
| Data quality         | Phase 2 fails fast on schema violations before compute is spent       |
| Evaluation integrity | Test split never used in hyperparameter selection                     |
| Config safety        | Fast-fail on missing env vars before any phase runs                   |
| Artifact safety      | Each run writes to a new version directory — no overwrites possible   |
| Observability        | Structured log format with `pipeline_phase` field on every log line   |
| Cost control         | `n_trials` and `timeout_seconds` are configurable per-run             |

**What would change in a real enterprise environment:**

| This project                   | Production equivalent                                              |
|--------------------------------|--------------------------------------------------------------------|
| `sklearn.datasets.load_wine`   | Feature store (Feast, Tecton) or Delta Lake partition read         |
| `artifacts/` on local disk     | S3 bucket, GCS bucket, or Azure Blob container                     |
| Single orchestrator Job        | Argo Workflows DAG with one container per phase                    |
| In-memory Optuna storage       | Optuna with PostgreSQL or Redis storage for distributed search      |
| No model registry              | MLflow Model Registry, SageMaker Model Registry, or Vertex AI      |
| Manual version comparison      | Automated promotion gate in CI/CD (GitHub Actions, Argo)           |
| Local `kind` cluster           | EKS, GKE, or AKS with GPU node pools for compute-heavy training    |

---

## 13. Troubleshooting

**`RuntimeError: Missing required environment variables: ['ARTIFACT_STORE_ROOT']`**

```
Cause:   ARTIFACT_STORE_ROOT env var not set before running the pipeline.
Fix:     export ARTIFACT_STORE_ROOT=artifacts
         In Kubernetes: check the Job spec's env section and the ConfigMap.
K8s cmd: kubectl describe job wine-quality-training-job -n mlops
         kubectl get configmap wine-training-env-config -n mlops -o yaml
```

**`FileNotFoundError: Training pipeline config not found at '...'`**

```
Cause:   PIPELINE_CONFIG_PATH points to a file that does not exist.
Fix:     Ensure configs/training_pipeline.yaml exists and the path is correct.
         In Kubernetes: verify the ConfigMap volume mount path matches
         PIPELINE_CONFIG_PATH in the env section.
K8s cmd: kubectl describe pod <pod-name> -n mlops | grep -A5 "Mounts:"
```

**`DataValidationError: Dataset validation failed`**

```
Cause:   The dataset does not meet the schema contract.
         Common triggers: missing column, wrong dtype, unexpected null values.
Fix:     Read the failure_reasons list in the log output.
         Each reason names the exact check that failed and the value found.
Log:     Look for lines with pipeline_phase=data_validation and level=ERROR.
```

**`[W] Trial N failed with ... ValueError: CategoricalDistribution`**

```
Cause:   Dynamic categorical choices in an Optuna trial (choices that change
         based on another parameter's value violate Optuna's distribution
         compatibility rule).
Fix:     Make all categorical search spaces static. Each parameter's choices
         must be identical across all trials.
```

**`Pipeline exits with code 3 (evaluation threshold not met)`**

```
Cause:   The best model's balanced_accuracy on the test split is below 0.85.
Fix:     Check metrics.json in the registered artifact version.
         Options: increase n_trials in training_pipeline.yaml,
         add more model families, adjust class_weight, or check data quality.
K8s cmd: kubectl logs job/wine-quality-training-job -n mlops | grep "Evaluation"
```

**`Job completed but artifacts directory is empty`**

```
Cause:   In Kubernetes, the artifact store PVC was not mounted correctly.
         The pipeline wrote to ephemeral container storage, which was lost
         when the pod terminated.
Fix:     Verify that ARTIFACT_STORE_ROOT matches the mountPath in the Job spec.
         Verify the PVC is Bound and the mount succeeded.
K8s cmd: kubectl get pvc -n mlops
         kubectl describe pod <pod-name> -n mlops | grep -A10 "Volumes:"
         kubectl exec <pod-name> -n mlops -- ls /mnt/artifact-store
```
