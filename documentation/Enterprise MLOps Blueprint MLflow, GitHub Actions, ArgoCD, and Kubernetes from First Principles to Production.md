# MLOps Deep Dive: MLflow, GitHub Actions, ArgoCD & Kubernetes

### From First Principles to Enterprise Architecture

> **The goal of this document:** By the end, you will be able to draw the full system on a whiteboard,
> explain what every component does, write the YAML/code for each phase, make professional decisions,
> and answer any interview question about MLOps architecture.

---

## Table of Contents

1. [The Confusion Resolved — Training vs Inference is NOT the Same Thing](#1-the-confusion-resolved)
2. [Glossary — Hard Terms Defined Simply](#2-glossary)
3. [The Full System Architecture (Universe View)](#3-the-full-system-architecture)
4. [MLflow: All Four Components Explained](#4-mlflow-all-four-components)
5. [GitHub Actions: Two Completely Different Pipelines](#5-github-actions-two-completely-different-pipelines)
6. [Training CI Pipeline — Deep Dive](#6-training-ci-pipeline)
7. [The Model Registry — Decision Gate Between CI and CD](#7-the-model-registry)
8. [Inference CI Pipeline — Deep Dive](#8-inference-ci-pipeline)
9. [ArgoCD — The GitOps Engine](#9-argocd-the-gitops-engine)
10. [Kubernetes — The Runtime](#10-kubernetes-the-runtime)
11. [How ALL Components Connect — The Complete Data Flow](#11-how-all-components-connect)
12. [Human Decision Points — Where You Must Intervene](#12-human-decision-points)
13. [Nuanced Decision Making — Enterprise Choices](#13-nuanced-decision-making)
14. [Complete Code Reference — Every File Explained](#14-complete-code-reference)
15. [Interview Preparation — Questions and Full Answers](#15-interview-preparation)

---

## 1. The Confusion Resolved

### Your Mental Model (Before This Document)

```
You probably think: training and inference both "use MLflow" in the same way.
```

This is wrong, and it is the source of most confusion. Let's fix it immediately.

### The Core Asymmetry

Training and inference are **mirror images** of each other in how they interact with MLflow:

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                          THE FUNDAMENTAL ASYMMETRY                           ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║   TRAINING PHASE                           INFERENCE PHASE                   ║
║   ────────────────────────                 ──────────────────────────        ║
║                                                                              ║
║   Direction:  WRITES → MLflow              Direction:  READS ← MLflow        ║
║                                                                              ║
║   When:       At CI pipeline run           When:       At CD deploy time     ║
║               (code push)                              AND at pod startup    ║
║                                                                              ║
║   What it     Metrics, params,             What it     The model binary      ║
║   touches:    model binary,                touches:    (pkl/onnx), the       ║
║               registry entry                           conda environment     ║
║                                                                              ║
║   MLflow      mlflow.log_metric()          MLflow      mlflow.pyfunc         ║
║   API used:   mlflow.log_model()           API used:   .load_model()         ║
║               client.transition_                                             ║
║               model_version_stage()                                          ║
║                                                                              ║
║   URI format: http://mlflow:5000           URI format: models:/name/stage    ║
║               (tracking server)                        (registry reference)  ║
║                                                                              ║
║   Runs in:    GitHub Actions               Runs in:    GitHub Actions CD     ║
║               ephemeral VM                             (build time) +        ║
║                                                        Kubernetes Pod        ║
║                                                        (runtime)             ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### The Simple Analogy

Think of MLflow as a **government approval office** for models.

- **Training** is like a company **submitting a product** for review. They hand over the product (model binary), documentation (metrics, params), and test results. They WRITE to the office.
- **Inference** is like a **pharmacy fetching an approved drug**. They ask the office: "Give me the currently approved version of Drug X." They READ from the office.

The office (MLflow Registry) is the gatekeeper. Nothing gets deployed without going through it.

### Why They Use GitHub Actions Differently

```
TRAINING CI (triggered by code change):
─────────────────────────────────────────────────────────────────────
Purpose → "Is this new trained model good enough?"
It trains, evaluates, and if the model is good → puts it in Registry

INFERENCE CI (triggered by code change):
─────────────────────────────────────────────────────────────────────
Purpose → "Is this new API code good?"
It tests the FastAPI code, builds a Docker image, pushes to container
registry. It does NOT retrain any model.

DEPLOYMENT CD (triggered by Git change to deployment config):
─────────────────────────────────────────────────────────────────────
Purpose → "Deploy what Git says should be running"
Reads which model version is approved, pulls the binary, puts it
in a container, runs it in Kubernetes.
```

These are **three separate pipelines** with three separate triggers and three separate jobs. They are loosely coupled through MLflow Registry and Git.

---

## 2. Glossary

Before any diagram or code, understand these terms. They are used everywhere.

### Infrastructure Terms

| Term                            | What It Really Is                                                                                                                                           | Analogy                                                          |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| **Docker Container**            | A self-contained box with your Python code, dependencies, and optionally your model — all packed together. Runs identically on any machine.                 | A shipping container — standard size, runs anywhere              |
| **Docker Image**                | The blueprint/template for a container. You build an image once, run many containers from it.                                                               | The master blueprint before manufacturing                        |
| **Container Registry**          | A storage service for Docker images. Like GitHub but for Docker images. Examples: AWS ECR, Azure ACR, Docker Hub.                                           | A warehouse for blueprints                                       |
| **Kubernetes (K8s)**            | A system that runs your Docker containers at scale. Handles starting/stopping containers, load balancing, health checks, and restarting crashed containers. | A factory floor manager — decides which workers run which tasks  |
| **Pod**                         | The smallest deployable unit in Kubernetes. Usually one container. Think of it as "one running instance of your FastAPI app."                               | One worker on the factory floor                                  |
| **Deployment**                  | A Kubernetes object that says "I want 3 copies of this pod running at all times, use this image." Kubernetes makes it happen.                               | A work order: "Keep 3 workers on task A at all times"            |
| **Service**                     | A Kubernetes object that gives your pods a stable network address. Without it, pod IP addresses change every time they restart.                             | The reception desk — stable address, routes to available workers |
| **Ingress**                     | A Kubernetes object that routes external HTTP traffic to the right service. Like a bouncer deciding which door users go through.                            | The front door of the factory                                    |
| **Namespace**                   | A way to isolate groups of resources in Kubernetes. You might have `staging` and `production` namespaces.                                                   | Separate floors in a building                                    |
| **ConfigMap**                   | A Kubernetes object that stores non-secret configuration (like `MODEL_VERSION=4`) that your pods can read.                                                  | A bulletin board with instructions for workers                   |
| **Secret**                      | Like ConfigMap but encrypted. Stores passwords, API keys.                                                                                                   | A locked filing cabinet                                          |
| **PVC (PersistentVolumeClaim)** | A request for storage in Kubernetes. Your pods can read/write files to it.                                                                                  | A filing cabinet that doesn't disappear when a worker leaves     |

### MLOps Terms

| Term                | What It Really Is                                                                                                         | Common Mistake                                                                      |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| **MLflow Tracking** | The component that records experiment runs — params, metrics, artifacts. Like a lab notebook.                             | Confusing it with the Registry — Tracking is just notes, Registry is approvals      |
| **MLflow Registry** | The component that versions and stages models. Only "important" models go here.                                           | Registering every run — only register models that pass gates                        |
| **Artifact**        | Any file produced during training. The model binary, feature scalers, confusion matrices, etc.                            | Only thinking pkl files count — MLflow artifacts include all supporting files       |
| **Run**             | One execution of a training script. Each has a unique Run ID (UUID).                                                      | Thinking runs are the same as model versions — they're not                          |
| **Model Version**   | An entry in the Registry pointing to a Run's artifacts. One Run can produce one Registry version.                         | Confusing run ID with version number — different systems                            |
| **Stage**           | The approval status of a Registry version: None → Staging → Production → Archived                                         | Thinking "Production" stage means it's deployed — it just means it's approved       |
| **Artifact URI**    | The address where a model binary is stored. Usually an S3 path. `s3://bucket/run_id/model.pkl`                            | Thinking MLflow stores the binary — MLflow stores the address, S3 stores the binary |
| **Model URI**       | The MLflow "magic" reference format: `models:/model-name/stage` — resolves to actual artifact URI                         | Hardcoding artifact URIs instead of using model URIs                                |
| **Pyfunc**          | MLflow's universal model wrapper. Any model (sklearn, XGBoost, PyTorch) can be wrapped in pyfunc and loaded the same way. | Using framework-specific loaders in serving code                                    |

### GitOps / CD Terms

| Term               | What It Really Is                                                                                                          | Why It Matters                                                                 |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| **GitOps**         | A pattern where Git is the single source of truth for what should run in production. Want to change production? Make a PR. | Provides full audit trail, rollback = git revert                               |
| **ArgoCD**         | A Kubernetes operator that watches a Git repo and continuously makes your cluster match what Git says.                     | The "auto-sync" engine. You update Git, ArgoCD updates K8s                     |
| **Flux**           | Alternative to ArgoCD. Same GitOps concept, different implementation.                                                      | Either works — ArgoCD has better UI                                            |
| **Reconciliation** | The process ArgoCD uses to compare "what Git says should exist" vs "what the cluster actually has" and fix the difference. | "Git says v5 should run. Cluster has v4. Reconcile → deploy v5."               |
| **Drift**          | When what's in the cluster doesn't match what's in Git. ArgoCD detects and corrects drift.                                 | Without ArgoCD, someone could manually change prod without a PR — undetectable |
| **Helm**           | A package manager for Kubernetes manifests. Lets you template your YAML with variables.                                    | Makes your K8s config reusable across environments (staging/prod)              |
| **Manifest**       | A YAML file describing what you want in Kubernetes. "I want a Deployment with image X, 3 replicas."                        | These live in Git — they are what ArgoCD watches                               |
| **Canary**         | Running two versions simultaneously, splitting traffic between them.                                                       | "5% to new version, 95% to old version" — gradually increase if metrics hold   |
| **Istio**          | A service mesh that adds traffic management, observability, and security to Kubernetes. Enables canary traffic splitting.  | Without Istio, you can't do fine-grained traffic % splits                      |
| **VirtualService** | An Istio resource that defines traffic routing rules. "Send 5% to service-v2, 95% to service-v1."                          | The canary config lives here                                                   |

---

## 3. The Full System Architecture (Universe View)

Read this diagram top to bottom. Every arrow is a data flow. Every box is a system. We will explain every single one.

```
╔══════════════════════════════════════════════════════════════════════════════════════╗
║                             THE COMPLETE MLOPS UNIVERSE                              ║
╠══════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                      ║
║  ① SOURCE (Everything starts here)                                                   ║
║  ┌────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                             GIT REPOSITORY                                     │  ║
║  │                                                                                │  ║
║  │  training/          inference/          configs/           deployments/        │  ║
║  │  ├─ train.py        ├─ app.py           ├─ hyperparams.yaml├─ model-v5.yaml    │  ║
║  │  ├─ features.py     ├─ schemas.py       └─ thresholds.yaml └─ canary.yaml      │  ║
║  │  ├─ evaluate.py     └─ Dockerfile                                              │  ║
║  │  └─ Dockerfile      (inference CI reads this)                                  │  ║
║  │  (training CI reads this)                                                      │  ║
║  │                                                                                │  ║
║  │  .github/workflows/                                                            │  ║
║  │  ├─ training-ci.yaml   ← governs training pipeline                             │  ║
║  │  ├─ inference-ci.yaml  ← governs inference image build                         │  ║
║  │  └─ (ArgoCD watches deployments/ folder automatically)                         │  ║
║  └────────────────────────────────────────────────────────────────────────────────┘  ║
║        │ training/ changed       │ inference/ changed      │ deployments/ changed    ║
║        │ (git push)               │ (git push)              │ (PR merged)            ║
║        ▼                         ▼                         ▼                         ║
╠══════════════════════════════════════════════════════════════════════════════════════╣
║  ② AUTOMATION (GitHub Actions — two separate pipelines)                              ║
║                                                                                      ║
║  ┌──────────────────────────────────┐   ┌────────────────────────────────────────┐   ║
║  │      TRAINING CI PIPELINE        │   │         INFERENCE CI PIPELINE          │   ║
║  │      (training-ci.yaml)          │   │         (inference-ci.yaml)            │   ║
║  │                                  │   │                                        │   ║
║  │  Triggered: training/ or         │   │  Triggered: inference/ changes         │   ║
║  │  configs/ file changes           │   │                                        │   ║
║  │                                  │   │  Steps:                                │   ║
║  │  Steps:                          │   │  1. Unit tests (mock model)            │   ║
║  │  1. Unit tests (no model)        │   │  2. Integration tests (mock model)     │   ║
║  │  2. Build training container     │   │  3. Security scan (trivy, bandit)      │   ║
║  │  3. Launch training job          │   │  4. Build Docker image (no model yet!) │   ║
║  │  4. WRITE metrics to MLflow      │   │  5. Push image to Container Registry   │   ║
║  │  5. WRITE model to MLflow        │   │                                        │   ║
║  │  6. Evaluate quality gates       │   │  OUTPUT: inference-api:git-sha         │   ║
║  │  7. If pass → WRITE to Registry  │   │          image in registry             │   ║
║  │     (stage: Staging)             │   │                                        │   ║
║  │                                  │   │  NOTE: Model NOT touched here.         │   ║
║  │  OUTPUT: Model in MLflow         │   │  This pipeline is PURELY about         │   ║
║  │          Registry, stage=Staging │   │  the API serving code.                 │   ║
║  └──────────────────┬───────────────┘   └────────────────────────────────────────┘   ║
║                     │                                                                ║
║                     ▼                                                                ║
╠══════════════════════════════════════════════════════════════════════════════════════╣
║  ③ THE BRIDGE (MLflow — not just tracking, the approval state machine)               ║
║                                                                                      ║
║  ┌────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                            MLFLOW SERVER                                       │  ║
║  │                                                                                │  ║
║  │   TRACKING (backend: PostgreSQL)           REGISTRY (same DB, diff tables)     │  ║
║  │   ──────────────────────────────           ──────────────────────────────────  │  ║
║  │   experiment: "rotten-tomatoes"            Model: "rotten-tomatoes-xgb"        │  ║
║  │   run: abc123                              ┌─────────────────────────────┐     │  ║
║  │     params:                                │ v1  │ Archived              │     │  ║
║  │       max_depth: 6                         │ v2  │ Archived              │     │  ║
║  │       n_estimators: 200                    │ v3  │ Archived              │     │  ║
║  │     metrics:                               │ v4  │ Production ◄─── CD reads    │  ║
║  │       auc: 0.923                           │ v5  │ Staging ◄── CI just wrote   │  ║
║  │       f1: 0.891                            └─────────────────────────────┘     │  ║
║  │     artifacts:                                       │                         │  ║
║  │       s3://bucket/abc123/model.pkl                   │ Human approval needed   │  ║
║  │                                                      ▼                         │  ║
║  │   ARTIFACT STORE (backend: S3 / Azure Blob)          │                         │  ║
║  │   ──────────────────────────────────────────         │                         │  ║
║  │   s3://mlflow-artifacts/                    ◄────────┘                         │  ║
║  │     abc123/                                                                    │  ║
║  │       model/                                                                   │  ║
║  │         model.pkl       ← the actual binary                                    │  ║
║  │         MLmodel         ← metadata                                             │  ║
║  │         conda.yaml      ← exact environment                                    │  ║
║  │         requirements.txt                                                       │  ║
║  └────────────────────────────────────────────────────────────────────────────────┘  ║
║                     │                                                                ║
║          ┌──────────┴──────────────────────────────────────────┐                     ║
║          │  Human reviews in MLflow UI                         │                     ║
║          │  clicks "Promote to Production"                     │                     ║
║          │  → automated PR created in Git                      │                     ║
║          ▼                                                     ▼                     ║
╠══════════════════════════════════════════════════════════════════════════════════════╣
║  ④ GITOPS ENGINE (ArgoCD — watches Git, makes K8s match)                             ║
║                                                                                      ║
║  ┌────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                    ARGOCD (running inside Kubernetes)                          │  ║
║  │                                                                                │  ║
║  │  ArgoCD Sync Loop (runs every 3 minutes or via webhook):                       │  ║
║  │                                                                                │  ║
║  │  READ deployments/model-config.yaml from Git:                                  │  ║
║  │    model_version: "5"    ← was "4" before PR merged                            │  ║
║  │    canary_weight: 5                                                            │  ║
║  │                                                                                │  ║
║  │  READ current cluster state:                                                   │  ║
║  │    running: model v4, 100% traffic                                             │  ║
║  │                                                                                │  ║
║  │  DETECT DRIFT → RECONCILE:                                                     │  ║
║  │    1. Ask MLflow: "Where is model v5 stored?"                                  │  ║
║  │       Response: s3://bucket/abc123/model.pkl                                   │  ║
║  │    2. Start new pod (v5 canary)                                                │  ║
║  │    3. Pod downloads model from S3 at startup                                   │  ║
║  │    4. Update Istio VirtualService: 95% → v4, 5% → v5                           │  ║
║  │                                                                                │  ║
║  └────────────────────────────────────────────────────────────────────────────────┘  ║
║                     │                                                                ║
║                     ▼                                                                ║
╠══════════════════════════════════════════════════════════════════════════════════════╣
║  ⑤ RUNTIME (Kubernetes — where predictions happen)                                   ║
║                                                                                      ║
║  ┌────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                    KUBERNETES CLUSTER                                          │  ║
║  │                                                                                │  ║
║  │  Ingress (external HTTPS endpoint)                                             │  ║
║  │       │                                                                        │  ║
║  │       ▼                                                                        │  ║
║  │  Istio VirtualService (traffic splitter)                                       │  ║
║  │       │                      │                                                 │  ║
║  │  95% traffic            5% traffic                                             │  ║
║  │       │                      │                                                 │  ║
║  │       ▼                      ▼                                                 │  ║
║  │  ┌──────────────┐    ┌──────────────┐                                          │  ║
║  │  │ Pod: v4      │    │ Pod: v5      │   ← canary                               │  ║
║  │  │ (stable)     │    │ (new)        │                                          │  ║
║  │  │              │    │              │                                          │  ║
║  │  │ FastAPI      │    │ FastAPI      │   ← same inference code                  │  ║
║  │  │              │    │              │                                          │  ║
║  │  │ model: v4    │    │ model: v5    │   ← different model artifact             │  ║
║  │  │ (in memory)  │    │ (in memory)  │                                          │  ║
║  │  └──────────────┘    └──────────────┘                                          │  ║
║  │                                                                                │  ║
║  └────────────────────────────────────────────────────────────────────────────────┘  ║
║                     │                                                                ║
║                     ▼                                                                ║
╠══════════════════════════════════════════════════════════════════════════════════════╣
║  ⑥ FEEDBACK LOOP (Monitoring — closes the loop back to training)                     ║
║                                                                                      ║
║  ┌────────────────────────────────────────────────────────────────────────────────┐  ║
║  │  Prometheus scrapes pod metrics → Grafana dashboards                           │  ║
║  │  Evidently AI compares live data distribution vs training data                 │  ║
║  │                                                                                │  ║
║  │  Alerts:                                                                       │  ║
║  │    error_rate > 1%  →  auto-rollback (ArgoCD)                                  │  ║
║  │    data_drift > 0.2 →  Slack alert → data team investigates → retrain          │  ║
║  └────────────────────────────────────────────────────────────────────────────────┘  ║
╚══════════════════════════════════════════════════════════════════════════════════════╝
```

---

## 4. MLflow: All Four Components

MLflow has four distinct components. Most beginners think it's one monolithic thing. It is not.

```
╔═══════════════════════════════════════════════════════════════════════╗
║                 MLFLOW — FOUR SEPARATE COMPONENTS                     ║
╠════════════════════════╦══════════════════════════════════════════════╣
║ TRACKING               ║ What it does:                                ║
║                        ║ Records every training run like a lab        ║
║ Used by:               ║ notebook. Params, metrics, tags, artifact    ║
║ Training CI            ║ locations.                                   ║
║ (WRITES)               ║                                              ║
║                        ║ Why you need it:                             ║
║ Key API calls:         ║ Without it, you can't compare: "Was run #47  ║
║ mlflow.start_run()     ║ better than run #52? Which params did I      ║
║ mlflow.log_param()     ║ use?"                                        ║
║ mlflow.log_metric()    ║                                              ║
║ mlflow.log_model()     ║ Backend storage:                             ║
║                        ║ SQLite (dev) or PostgreSQL (prod)            ║
╠════════════════════════╬══════════════════════════════════════════════╣
║ MODEL REGISTRY         ║ What it does:                                ║
║                        ║ Versioned database of "keeper" models.       ║
║ Used by:               ║ Has stages: None → Staging → Production →    ║
║ Training CI (WRITES)   ║ Archived. Humans or scripts promote between  ║
║ Inference CD (READS)   ║ stages. This is the approval system.         ║
║                        ║                                              ║
║ Key API calls:         ║ Why you need it:                             ║
║ client.register_model  ║ Without it, you can't answer: "Which exact   ║
║ client.transition_     ║ model is in production right now? Who        ║
║   model_version_stage  ║ approved it? What are its metrics?"          ║
║ client.get_latest_     ║                                              ║
║   versions()           ║ Backend storage: Same DB as Tracking         ║
╠════════════════════════╬══════════════════════════════════════════════╣
║ ARTIFACT STORE         ║ What it does:                                ║
║                        ║ Stores the actual binary files. model.pkl,   ║
║ Accessed via:          ║ MLmodel metadata, conda.yaml,                ║
║ MLflow Tracking API    ║ requirements.txt, confusion matrices, SHAP   ║
║ (transparently)        ║ plots — any file you log.                    ║
║                        ║                                              ║
║ Storage backends:      ║ Why you need it separate:                    ║
║ S3, Azure Blob,        ║ Model binaries can be 5GB+. You don't want   ║
║ GCS, local disk        ║ that in a SQL database row.                  ║
║ (dev only)             ║                                              ║
║                        ║ IMPORTANT: MLflow Registry stores the        ║
║                        ║ ADDRESS of the artifact (S3 URI), not        ║
║                        ║ the binary itself.                           ║
╠════════════════════════╬══════════════════════════════════════════════╣
║ PROJECTS               ║ What it does:                                ║
║ (rarely used in        ║ Packages training code as reproducible       ║
║  enterprise CI/CD)     ║ units with a standard entrypoint.            ║
║                        ║                                              ║
║                        ║ When you'd use it:                           ║
║                        ║ Sharing self-contained training pipelines    ║
║                        ║ across teams. Most enterprise teams skip it  ║
║                        ║ and use Docker + Kubeflow instead.           ║
╚════════════════════════╩══════════════════════════════════════════════╝
```

### MLflow Server: What Actually Runs

When you deploy MLflow in production, you run one server that hosts all components:

```
mlflow server
  --backend-store-uri postgresql://user:pass@db:5432/mlflow  ← where metadata lives
  --default-artifact-root s3://your-bucket/mlflow-artifacts   ← where binaries live
  --host 0.0.0.0
  --port 5000
```

**The backend-store (PostgreSQL)** holds:

- The `experiments` table
- The `runs` table (with run_id, params, metrics)
- The `registered_models` table
- The `model_versions` table (with version, stage, run_id foreign key)

**The artifact store (S3)** holds:

- `s3://bucket/artifacts/{run_id}/model/model.pkl`
- `s3://bucket/artifacts/{run_id}/model/MLmodel`
- `s3://bucket/artifacts/{run_id}/model/conda.yaml`

The foreign key `model_versions.run_id → runs.run_id` is how MLflow knows which S3 path corresponds to which registry version. When you ask for `models:/my-model/Production`, MLflow looks up the PostgreSQL table, finds the run_id, constructs the S3 path, and either gives it to you or downloads the files.

### MLflow URI Types — The Two You Must Not Confuse

```
┌──────────────────────────────────────────────────────────────────────┐
│ URI TYPE 1: Tracking Server URI                                      │
│                                                                      │
│ Format:   http://mlflow-server:5000                                  │
│ Used by:  training scripts to WRITE data                             │
│ Set via:  MLFLOW_TRACKING_URI environment variable                   │
│                                                                      │
│ Example:                                                             │
│ export MLFLOW_TRACKING_URI="http://mlflow.internal:5000"             │
│ python train.py  ← train.py calls mlflow.log_metric() which          │
│                   sends HTTP POST to this URI                        │
│                                                                      │
│ This is like the mailing address of the office.                      │
├──────────────────────────────────────────────────────────────────────┤
│ URI TYPE 2: Model Registry URI                                       │
│                                                                      │
│ Format:   models:/model-name/stage-or-version                        │
│ Used by:  inference code and CD pipeline to READ/DOWNLOAD models     │
│                                                                      │
│ Examples:                                                            │
│ models:/fraud-detection/Production   ← latest production version     │
│ models:/fraud-detection/5            ← exactly version 5             │
│ models:/fraud-detection/Staging      ← latest staging version        │
│                                                                      │
│ To resolve this URI, MLflow must know the tracking server URI.       │
│ So MLFLOW_TRACKING_URI still needs to be set, but you QUERY          │
│ the registry rather than writing to tracking.                        │
│                                                                      │
│ This is like saying "Give me the approved v5 drug" — a semantic      │
│ reference, not a physical address.                                   │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 5. GitHub Actions: Two Completely Different Pipelines

GitHub Actions workflows are YAML files in `.github/workflows/`. Each YAML file is one pipeline. They are triggered independently.

### The Repository Structure That Makes This Work

```
your-ml-repo/
├── .github/
│   └── workflows/
│       ├── training-ci.yaml     ← PIPELINE 1: triggered by training code changes
│       └── inference-ci.yaml    ← PIPELINE 2: triggered by inference code changes
│
├── training/                    ← Changes here → triggers training-ci.yaml
│   ├── train.py
│   ├── features.py
│   ├── evaluate.py
│   └── Dockerfile               ← training container (different from inference!)
│
├── inference/                   ← Changes here → triggers inference-ci.yaml
│   ├── app.py
│   ├── schemas.py
│   ├── predict.py
│   └── Dockerfile               ← inference container (FastAPI server)
│
├── configs/                     ← Changes here → triggers training-ci.yaml
│   ├── hyperparams.yaml
│   └── thresholds.yaml
│
└── deployments/                 ← Changes here → ArgoCD picks up (not GitHub Actions)
    ├── model-config.yaml        ← ArgoCD watches this
    └── kubernetes/
        ├── deployment.yaml
        └── virtual-service.yaml
```

### Path Filters — The Core of Pipeline Separation

This is the mechanism that makes pipelines independent:

```yaml
# In training-ci.yaml:
on:
  push:
    paths:
      - 'training/**'    # only if training/ files changed
      - 'configs/**'     # only if configs/ files changed
      # inference/ is NOT listed — changes there won't trigger this

# In inference-ci.yaml:
on:
  push:
    paths:
      - 'inference/**'   # only if inference/ files changed
      # training/ and configs/ NOT listed — won't trigger this
```

**What this means in practice:**

```
You update inference/app.py (add input validation):
→ inference-ci.yaml triggers (builds new API image)
→ training-ci.yaml does NOT trigger (no retraining)
→ Model stays exactly the same
→ New API container gets built and pushed

You update configs/hyperparams.yaml (change max_depth):
→ training-ci.yaml triggers (retrains with new params)
→ inference-ci.yaml does NOT trigger (API code unchanged)
→ New model trained, evaluated, pushed to Registry
→ API container stays exactly the same

You update both:
→ Both pipelines trigger simultaneously
→ They run in parallel
→ The CD pipeline (ArgoCD) assembles both when ready
```

### GitHub Actions Runner — The Ephemeral VM

This concept trips people up. When GitHub Actions runs, it spins up a **fresh virtual machine** that:

1. Starts completely empty (no code, no model, no Python)
2. Runs your steps
3. Is completely destroyed when done

```
┌─────────────────────────────────────────────────────────────────────┐
│  GitHub Actions Runner VM (lives ~10 minutes, then destroyed)       │
│                                                                     │
│  Memory:    None (starts empty)                                     │
│  Disk:      None (starts empty)                                     │
│  Python:    Not installed (you install it each run)                 │
│  Your code: Not there (you checkout each run)                       │
│                                                                     │
│  So where does the trained model go?                                │
│  → NOT on the runner VM. It gets uploaded to S3 via MLflow.         │
│  → The runner VM is just the worker. S3 + MLflow are the storage.   │
│                                                                     │
│  So where do built Docker images go?                                │
│  → NOT on the runner VM. They get pushed to ECR/ACR.                │
│  → The runner VM just builds and pushes. Then disappears.           │
└─────────────────────────────────────────────────────────────────────┘
```

This is why **all persistent state lives outside GitHub Actions**: in MLflow (model state), in S3 (binary artifacts), in ECR (container images), and in Git (configuration).

---

## 6. Training CI Pipeline — Deep Dive

### What This Pipeline Actually Does, Step by Step

```
Developer pushes: configs/hyperparams.yaml (changed max_depth: 4 → 6)
       │
       ▼
GitHub detects path match: 'configs/**' → triggers training-ci.yaml
       │
       ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     GITHUB ACTIONS RUNNER STARTS                     │
│                      (fresh Ubuntu VM spins up)                      │
└──────────────────────────────────────────────────────────────────────┘
       │
       │ ═══ PHASE 1: SETUP ═══
       ▼
┌──────────────────────────────────────────────────────────────────────┐
│ actions/checkout@v4                                                  │
│ → Downloads your entire git repo to the VM's disk                    │
│ → Now the VM has: train.py, configs/, tests/, etc.                   │
│ → Does NOT have: model.pkl (that's in S3)                            │
└──────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────────┐
│ actions/setup-python@v5                                              │
│ → Installs Python 3.11 on the VM                                     │
│ → pip install -r requirements.txt                                    │
│ → Now VM has: mlflow, xgboost, scikit-learn, etc.                    │
└──────────────────────────────────────────────────────────────────────┘
       │
       │ ═══ PHASE 2: QUALITY GATE #1 — CODE QUALITY ═══
       ▼
┌──────────────────────────────────────────────────────────────────────┐
│ pytest tests/unit/                                                   │
│ → Tests run WITHOUT any model, WITHOUT any data                      │
│ → Tests verify: feature engineering logic, data schemas, utils       │
│ → If ANY test fails: pipeline STOPS here. No training happens.       │
│                                                                      │
│ WHY STOP EARLY? Training is expensive (20 min to 8 hours).           │
│ Never waste compute on code that doesn't even pass unit tests.       │
└──────────────────────────────────────────────────────────────────────┘
       │ (only continues if ALL tests pass)
       │
       │ ═══ PHASE 3: TRAINING JOB ═══
       ▼
┌──────────────────────────────────────────────────────────────────────┐
│ python training/train.py --config configs/hyperparams.yaml           │
│                                                                      │
│ What happens INSIDE train.py:                                        │
│                                                                      │
│ [A] mlflow.set_tracking_uri("http://mlflow.internal:5000")           │
│     → Tells MLflow client WHERE to send data                         │
│     → This env var is set from GitHub Secrets                        │
│                                                                      │
│ [B] with mlflow.start_run() as run:                                  │
│     → Creates a new Run in MLflow's PostgreSQL database              │
│     → Gets back a run_id: "3b5f8a2c..."                              │
│                                                                      │
│ [C] mlflow.log_params({"max_depth": 6, "n_estimators": 200})         │
│     → HTTP POST to MLflow server                                     │
│     → Stored in: runs.params table                                   │
│                                                                      │
│ [D] [ACTUAL TRAINING HAPPENS HERE]                                   │
│     model = XGBClassifier(max_depth=6, n_estimators=200)             │
│     model.fit(X_train, y_train)                                      │
│                                                                      │
│ [E] mlflow.log_metric("auc", 0.923)                                  │
│     mlflow.log_metric("f1", 0.891)                                   │
│     → HTTP POST to MLflow server                                     │
│     → Stored in: runs.metrics table                                  │
│                                                                      │
│ [F] mlflow.xgboost.log_model(model, "model")                         │
│     → Serializes model to model.pkl (or XGBoost format)              │
│     → Uploads to: s3://bucket/artifacts/3b5f8a2c/model/              │
│     → Creates: model.pkl, MLmodel, conda.yaml, requirements.txt      │
│     → MLflow DB records: run 3b5f8a2c has artifact at s3://...       │
│                                                                      │
│ Train.py also saves run_id to a file: run_id.txt                     │
│ → This passes run_id to the next step                                │
└──────────────────────────────────────────────────────────────────────┘
       │
       │ ═══ PHASE 4: QUALITY GATE #2 — MODEL QUALITY ═══
       ▼
┌──────────────────────────────────────────────────────────────────────┐
│ python training/evaluate.py --run-id $(cat run_id.txt)               │
│                                                                      │
│ What evaluate.py does:                                               │
│                                                                      │
│ [A] Connects to MLflow (READ operation)                              │
│     run = client.get_run("3b5f8a2c")                                 │
│     metrics = run.data.metrics  → {"auc": 0.923, "f1": 0.891}        │
│                                                                      │
│ [B] Loads thresholds from config:                                    │
│     min_auc: 0.85, min_f1: 0.80, max_bias: 0.05                      │
│                                                                      │
│ [C] Gets production model metrics (for regression check):            │
│     prod_versions = client.get_latest_versions("model",              │
│                     ["Production"])                                  │
│     prod_run = client.get_run(prod_versions[0].run_id)               │
│     prod_auc = prod_run.data.metrics["auc"]  → 0.918                 │
│                                                                      │
│ [D] Runs checks:                                                     │
│     new_auc >= 0.85        → True  (0.923 > 0.85) ✓                  │
│     new_f1 >= 0.80         → True  (0.891 > 0.80) ✓                  │
│     new_bias <= 0.05       → True  (0.031 < 0.05) ✓                  │
│     new_auc >= prod - 0.02 → True (0.923 >= 0.898) ✓                 │
│                                                                      │
│ [E] If ALL pass: script exits 0 (success)                            │
│     If ANY fail: script exits 1 → pipeline STOPS                     │
│     model is NOT registered. Alert sent.                             │
└──────────────────────────────────────────────────────────────────────┘
       │ (only continues if all quality gates pass)
       │
       │ ═══ PHASE 5: REGISTER TO STAGING ═══
       ▼
┌──────────────────────────────────────────────────────────────────────┐
│ python training/register.py --run-id 3b5f8a2c --stage Staging        │
│                                                                      │
│ What register.py does:                                               │
│                                                                      │
│ client.create_model_version(                                         │
│   name="rotten-tomatoes-xgb",                                        │
│   source="runs:/3b5f8a2c/model",   ← points to S3 artifact           │
│   run_id="3b5f8a2c"                                                  │
│ )                                                                    │
│ → MLflow creates: model_versions row                                 │
│   name: rotten-tomatoes-xgb                                          │
│   version: 5                        ← auto-incremented               │
│   stage: None                       ← starts here                    │
│   run_id: 3b5f8a2c                  ← links to the run's artifacts   │
│                                                                      │
│ client.transition_model_version_stage(                               │
│   name="rotten-tomatoes-xgb",                                        │
│   version=5,                                                         │
│   stage="Staging",                                                   │
│   archive_existing_versions=True    ← old Staging → Archived         │
│ )                                                                    │
│ → Updates: model_versions row, stage = "Staging"                     │
│                                                                      │
│ Result: MLflow Registry now has:                                     │
│   v4 → Production (still serving traffic)                            │
│   v5 → Staging    (awaiting human review)                            │
└──────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────────┐
│ SLACK NOTIFICATION SENT:                                             │
│ "✅ Model v5 in Staging. AUC=0.923 (+0.005 vs prod). Review at:      │
│  http://mlflow.internal/models/rotten-tomatoes-xgb/5"                │
└──────────────────────────────────────────────────────────────────────┘
       │
       ▼
RUNNER VM DESTROYED. All state is in MLflow + S3. Nothing on the VM.
Training CI pipeline is DONE. The model exists in Registry (Staging).
Nothing is deployed yet.
```

### The Training CI YAML (Complete with Explanations)

```yaml
# .github/workflows/training-ci.yaml

name: Training CI — Train, Evaluate, Register

# ─────────────────────────────────────────────────────────────────────────────
# TRIGGER SECTION
# ─────────────────────────────────────────────────────────────────────────────
# "paths" means: only run this pipeline if one of these files changed.
# This prevents unnecessary retraining when only API code changes.
# ─────────────────────────────────────────────────────────────────────────────
on:
  push:
    branches: [main]
    paths:
      - 'training/**'   # Training code changed → retrain
      - 'configs/**'    # Hyperparams changed → retrain
  pull_request:
    branches: [main]
    paths:
      - 'training/**'
      - 'configs/**'

# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT VARIABLES
# These are available to ALL jobs in this pipeline.
# Values come from GitHub Secrets (Settings → Secrets and Variables → Actions).
# ─────────────────────────────────────────────────────────────────────────────
env:
  # The HTTP address of your MLflow tracking server.
  # The mlflow Python library reads MLFLOW_TRACKING_URI automatically.
  MLFLOW_TRACKING_URI: ${{ secrets.MLFLOW_TRACKING_URI }}

  # If your MLflow server requires login:
  MLFLOW_TRACKING_USERNAME: ${{ secrets.MLFLOW_USERNAME }}
  MLFLOW_TRACKING_PASSWORD: ${{ secrets.MLFLOW_PASSWORD }}

  # For S3 artifact store access:
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  AWS_DEFAULT_REGION: us-east-1

# ─────────────────────────────────────────────────────────────────────────────
# JOBS SECTION
# Jobs run in parallel by default. Use "needs:" to create dependencies.
# ─────────────────────────────────────────────────────────────────────────────
jobs:

  # ═══════════════════════════════════════════════════════════════════════════
  # JOB 1: unit-tests
  # Fastest, cheapest job. Runs on every PR and push.
  # Does NOT need MLflow connection — no model involved.
  # ═══════════════════════════════════════════════════════════════════════════
  unit-tests:
    name: "Unit Tests (no model)"
    runs-on: ubuntu-latest  # GitHub-hosted runner (fresh Ubuntu VM)

    steps:
      # Step 1: Download repo code to VM
      - name: Checkout code
        uses: actions/checkout@v4
        # After this, all your files are at: /home/runner/work/your-repo/

      # Step 2: Install Python
      - name: Set up Python 3.11
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      # Step 3: Cache pip dependencies (speeds up runs after the first)
      # Cache key based on requirements.txt hash — busts cache when deps change
      - name: Cache pip packages
        uses: actions/cache@v3
        with:
          path: ~/.cache/pip
          key: ${{ runner.os }}-pip-${{ hashFiles('requirements.txt') }}
          restore-keys: |
            ${{ runner.os }}-pip-

      # Step 4: Install all Python dependencies
      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install pytest pytest-cov

      # Step 5: Run unit tests
      # These tests should have NO dependencies on MLflow, S3, or training data.
      # They test pure Python functions: feature transformations, preprocessing, etc.
      - name: Run unit tests
        run: |
          pytest tests/unit/ \
            -v \
            --cov=training \
            --cov-report=xml \
            --tb=short
          # -v: verbose output
          # --cov: measure code coverage
          # --tb=short: shorter traceback on failure

      # Step 6: Upload coverage report (optional but good practice)
      - name: Upload coverage report
        uses: codecov/codecov-action@v3
        with:
          file: ./coverage.xml
        continue-on-error: true  # Don't fail pipeline if codecov is down

  # ═══════════════════════════════════════════════════════════════════════════
  # JOB 2: train-and-evaluate
  # Expensive job. Only runs after unit-tests pass.
  # This is where the actual ML training happens.
  # ═══════════════════════════════════════════════════════════════════════════
  train-and-evaluate:
    name: "Train Model & Evaluate Quality"
    runs-on: ubuntu-latest
    needs: unit-tests   # Wait for unit-tests job to finish successfully

    # "outputs" let downstream jobs read values produced here
    outputs:
      run_id: ${{ steps.run-training.outputs.run_id }}
      auc: ${{ steps.run-training.outputs.auc }}
      passed_gates: ${{ steps.quality-gates.outputs.passed }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python 3.11
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: pip install -r requirements.txt

      # ─────────────────────────────────────────────────────────────────────
      # THE CRITICAL STEP: Run training script.
      # MLFLOW_TRACKING_URI env var is set from env: section above.
      # The mlflow Python library reads this env var automatically.
      # Your train.py doesn't need to hardcode the server address.
      # ─────────────────────────────────────────────────────────────────────
      - name: Train model
        id: run-training   # Give this step an ID so we can reference its outputs
        run: |
          # Run training script. It will:
          # 1. Connect to MLflow (via MLFLOW_TRACKING_URI env var)
          # 2. Start a run, log params, train, log metrics, log model to S3
          # 3. Print the run_id at the end
          # 4. Write run_id to file so we can pass it to next step

          python training/train.py \
            --config configs/hyperparams.yaml \
            --output-dir /tmp/training-outputs

          # Read outputs written by train.py
          RUN_ID=$(cat /tmp/training-outputs/run_id.txt)
          AUC=$(cat /tmp/training-outputs/auc.txt)

          echo "MLflow Run ID: $RUN_ID"
          echo "AUC: $AUC"

          # Write to GITHUB_OUTPUT — makes these available as job outputs
          echo "run_id=$RUN_ID" >> $GITHUB_OUTPUT
          echo "auc=$AUC" >> $GITHUB_OUTPUT

      # ─────────────────────────────────────────────────────────────────────
      # QUALITY GATES: Compare new model metrics vs thresholds and vs prod.
      # If this script exits with code 1, the pipeline fails here.
      # Nothing gets registered.
      # ─────────────────────────────────────────────────────────────────────
      - name: Evaluate quality gates
        id: quality-gates
        run: |
          python training/evaluate.py \
            --run-id ${{ steps.run-training.outputs.run_id }} \
            --config configs/thresholds.yaml \
            --model-name "rotten-tomatoes-xgb" \
            --compare-to-production true

          echo "passed=true" >> $GITHUB_OUTPUT
        # If evaluate.py calls sys.exit(1), this step fails
        # and the "register" job below won't run

      # Save training outputs as artifact for debugging
      - name: Upload training outputs
        uses: actions/upload-artifact@v4
        if: always()   # Even on failure, save these for debugging
        with:
          name: training-outputs-${{ github.run_id }}
          path: /tmp/training-outputs/
          retention-days: 7

  # ═══════════════════════════════════════════════════════════════════════════
  # JOB 3: register-to-staging
  # Only runs on main branch (not PRs).
  # Only runs if train-and-evaluate passed.
  # Promotes model to "Staging" in MLflow Registry.
  # ═══════════════════════════════════════════════════════════════════════════
  register-to-staging:
    name: "Register Model to Staging"
    runs-on: ubuntu-latest
    needs: train-and-evaluate

    # CONDITIONAL: Only register if:
    # 1. We're on the main branch (not a PR)
    # 2. The quality gates passed
    if: |
      github.ref == 'refs/heads/main' &&
      needs.train-and-evaluate.outputs.passed_gates == 'true'

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install MLflow
        run: pip install mlflow

      - name: Register model to Staging
        run: |
          python training/register.py \
            --run-id ${{ needs.train-and-evaluate.outputs.run_id }} \
            --model-name "rotten-tomatoes-xgb" \
            --target-stage "Staging" \
            --description "AUC=${{ needs.train-and-evaluate.outputs.auc }}, from git ${{ github.sha }}"

      # Notify team that a new model is waiting for review
      - name: Notify Slack
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "🧪 New model in Staging!\nModel: rotten-tomatoes-xgb\nRun ID: ${{ needs.train-and-evaluate.outputs.run_id }}\nAUC: ${{ needs.train-and-evaluate.outputs.auc }}\nReview: ${{ secrets.MLFLOW_TRACKING_URI }}"
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

### The Training Script — Line-by-Line Explanation

```python
# training/train.py
"""
This script:
1. Reads hyperparameters from config
2. Loads training data
3. Trains the model
4. Logs EVERYTHING to MLflow (params, metrics, model binary)
5. Writes run_id to a file for downstream steps
"""

import os
import sys
import yaml
import argparse
import mlflow
import mlflow.xgboost
import xgboost as xgb
from sklearn.model_selection import train_test_split
from sklearn.metrics import roc_auc_score, f1_score
import pandas as pd
import numpy as np


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--output-dir", default="/tmp/training-outputs")
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 1: Load configuration
    # Note: we do NOT hardcode hyperparams in code. Config file triggers retrain.
    # ─────────────────────────────────────────────────────────────────────────
    with open(args.config) as f:
        config = yaml.safe_load(f)

    hparams = config["model"]        # e.g., {max_depth: 6, n_estimators: 200}
    data_config = config["data"]     # e.g., {test_size: 0.2, random_state: 42}

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 2: MLflow Setup
    # MLFLOW_TRACKING_URI is set as environment variable by GitHub Actions.
    # If running locally, set: export MLFLOW_TRACKING_URI=http://localhost:5000
    # mlflow.set_tracking_uri() reads from env var if not explicitly set.
    # ─────────────────────────────────────────────────────────────────────────
    tracking_uri = os.environ.get("MLFLOW_TRACKING_URI", "http://localhost:5000")
    mlflow.set_tracking_uri(tracking_uri)

    # Experiment is like a "folder" for related runs.
    # If "rotten-tomatoes-training" doesn't exist, MLflow creates it.
    mlflow.set_experiment("rotten-tomatoes-training")

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 3: Start MLflow Run
    # Everything inside 'with mlflow.start_run()' is one recorded run.
    # The run_id is a UUID generated by MLflow server.
    # ─────────────────────────────────────────────────────────────────────────
    with mlflow.start_run(
        run_name=f"training-{os.environ.get('GITHUB_RUN_ID', 'local')}"
    ) as run:

        run_id = run.info.run_id
        print(f"Started MLflow run: {run_id}")

        # ─────────────────────────────────────────────────────────────────────
        # LOG PARAMETERS (what settings were used for this run)
        # These appear in MLflow UI "Parameters" tab.
        # Crucial for reproducibility: "I know this run used max_depth=6"
        # ─────────────────────────────────────────────────────────────────────
        mlflow.log_params(hparams)
        mlflow.log_params({
            "test_size": data_config["test_size"],
            "git_sha": os.environ.get("GITHUB_SHA", "local"),
            "git_ref": os.environ.get("GITHUB_REF", "local"),
        })

        # Tags are like params but for non-numeric metadata
        mlflow.set_tags({
            "team": "ml-platform",
            "project": "rotten-tomatoes",
            "environment": "ci",
        })

        # ─────────────────────────────────────────────────────────────────────
        # ACTUAL TRAINING (your ML code — nothing special about this part)
        # ─────────────────────────────────────────────────────────────────────

        # Load data (from S3, database, or local — doesn't matter)
        df = pd.read_parquet(data_config["train_data_path"])
        X = df.drop(columns=["label"])
        y = df["label"]

        X_train, X_test, y_train, y_test = train_test_split(
            X, y,
            test_size=data_config["test_size"],
            random_state=data_config["random_state"],
            stratify=y
        )

        # Train XGBoost
        model = xgb.XGBClassifier(**hparams)

        # Log training metrics per epoch
        eval_set = [(X_train, y_train), (X_test, y_test)]
        model.fit(
            X_train, y_train,
            eval_set=eval_set,
            verbose=False
        )

        # ─────────────────────────────────────────────────────────────────────
        # LOG METRICS (model performance numbers)
        # These appear in MLflow UI "Metrics" tab and can be compared across runs.
        # ─────────────────────────────────────────────────────────────────────
        y_pred = model.predict(X_test)
        y_pred_proba = model.predict_proba(X_test)[:, 1]

        auc = roc_auc_score(y_test, y_pred_proba)
        f1 = f1_score(y_test, y_pred, average="weighted")

        mlflow.log_metrics({
            "auc": auc,
            "f1": f1,
            "train_size": len(X_train),
            "test_size": len(X_test),
        })

        print(f"AUC: {auc:.4f}, F1: {f1:.4f}")

        # ─────────────────────────────────────────────────────────────────────
        # LOG MODEL — This is the most important step.
        # mlflow.xgboost.log_model():
        #   1. Serializes the model to model.ubj (XGBoost format)
        #   2. Creates conda.yaml (exact Python env)
        #   3. Creates requirements.txt
        #   4. Creates MLmodel (metadata file: python_function flavor)
        #   5. Uploads all files to S3 at: s3://bucket/{run_id}/model/
        #   6. Records S3 path in MLflow database
        #
        # "registered_model_name" also creates a Registry entry pointing here.
        # ─────────────────────────────────────────────────────────────────────
        signature = mlflow.models.infer_signature(X_train, y_pred)
        # ^ Signature records input schema. Protects against schema drift.

        mlflow.xgboost.log_model(
            xgb_model=model,
            artifact_path="model",               # subfolder in run's artifacts
            signature=signature,
            registered_model_name="rotten-tomatoes-xgb",  # creates Registry entry
            # Note: stage is NOT set here. It starts as "None".
            # The register.py script promotes it to "Staging".
        )

        print(f"Model logged to S3 via MLflow. Run ID: {run_id}")

    # ─────────────────────────────────────────────────────────────────────────
    # WRITE OUTPUTS FOR DOWNSTREAM STEPS
    # GitHub Actions steps run in the same VM but separate processes.
    # Pass data between them via files.
    # ─────────────────────────────────────────────────────────────────────────
    with open(f"{args.output_dir}/run_id.txt", "w") as f:
        f.write(run_id)

    with open(f"{args.output_dir}/auc.txt", "w") as f:
        f.write(str(auc))

    print(f"Training complete. Outputs written to {args.output_dir}/")


if __name__ == "__main__":
    main()
```

---

## 7. The Model Registry — Decision Gate Between CI and CD

The Registry is not passive storage. It is an **active state machine** that controls which model has permission to be deployed. Understanding its mechanics is critical.

### The Registry Data Model

```
MLflow Registry — Relational Structure:

registered_models table:
  name: "rotten-tomatoes-xgb"
  creation_timestamp: 1714000000
  description: "XGBoost classifier for review sentiment"

model_versions table:
  ┌────────┬───────┬───────────┬───────────────────────────────────────┐
  │ name   │ ver   │ stage     │ run_id (FK → runs.run_id)             │
  ├────────┼───────┼───────────┼───────────────────────────────────────┤
  │ rt-xgb │ 1     │ Archived  │ aaa111... → s3://bucket/aaa111/model  │
  │ rt-xgb │ 2     │ Archived  │ bbb222... → s3://bucket/bbb222/model  │
  │ rt-xgb │ 3     │ Archived  │ ccc333... → s3://bucket/ccc333/model  │
  │ rt-xgb │ 4     │ Production│ ddd444... → s3://bucket/ddd444/model  │
  │ rt-xgb │ 5     │ Staging   │ eee555... → s3://bucket/eee555/model  │
  └────────┴───────┴───────────┴───────────────────────────────────────┘

runs table (linked via run_id):
  run_id: ddd444...
  params: {max_depth: 4, n_estimators: 150}
  metrics: {auc: 0.918, f1: 0.885}
  artifact_uri: s3://mlflow-bucket/artifacts/ddd444.../model

CRITICAL INSIGHT:
  "models:/rotten-tomatoes-xgb/Production"  resolves to:
  1. Look up model_versions WHERE name='rt-xgb' AND stage='Production'
  2. Get run_id = "ddd444..."
  3. Get artifact_uri from runs WHERE run_id='ddd444...'
  4. Return: s3://mlflow-bucket/artifacts/ddd444.../model
```

### Stage Transitions — What They Mean

```
  ┌─────────┐     ┌─────────┐     ┌───────────┐     ┌──────────┐
  │  None   │────▶│ Staging │────▶│ Production│────▶│ Archived │
  └─────────┘     └─────────┘     └───────────┘     └──────────┘

  None:
    - Just created by training CI
    - Model exists in S3, linked to Registry entry
    - No one is supposed to deploy this
    - The evaluate.py script may immediately promote to Staging
      if quality gates pass

  Staging:
    - Passed automated quality gates
    - Awaiting human review
    - Typically deployed to a STAGING Kubernetes environment
      for integration testing
    - NOT serving real user traffic (or serving very limited canary)

  Production:
    - Human approved it
    - The CD pipeline should deploy this
    - This version serves real user traffic
    - Only ONE version should be Production at a time
      (archive_existing_versions=True ensures this)

  Archived:
    - Superseded by newer version
    - Still exists in S3 (can rollback to it instantly)
    - Doesn't serve traffic
    - Kept for audit/compliance (typically 90-180 days)
```

### The Human Review — What Actually Happens

After CI registers a model to Staging, a human (ML Engineer / Data Scientist lead) reviews in the MLflow UI:

```
MLflow UI Review Checklist:
─────────────────────────────────────────────────────────────────────

METRICS TAB:
  ✓ AUC: 0.923 (was 0.918 in prod) → improvement ✓
  ✓ F1:  0.891 (was 0.885 in prod) → improvement ✓
  ✓ Bias score: 0.031 (max allowed: 0.05) → within bounds ✓

PARAMETERS TAB:
  Review what changed: max_depth went from 4 to 6
  Does this make sense given the data? Yes. ✓

ARTIFACTS TAB:
  - Download and inspect confusion matrix image logged by train.py
  - Review SHAP feature importance chart
  - No unexpected features dominating? ✓

COMPARE RUNS:
  Click "Compare" → select current staging vs current production
  Check: no significant regression on specific classes? ✓

LINEAGE:
  git_sha tag shows exactly what code produced this model ✓
  Can reproduce this run by checking out that SHA ✓

DECISION:
  → Click "Stage: Production" in the UI

This calls:
  client.transition_model_version_stage(
    name="rotten-tomatoes-xgb",
    version=5,
    stage="Production",
    archive_existing_versions=True   # v4 → Archived
  )
```

After this click, **an automated webhook fires** (you configure this) that creates a Pull Request in your Git repo:

```
PR: "chore: deploy model rotten-tomatoes-xgb v5"

Changes:
  deployments/model-config.yaml:
  -  model_version: "4"
  +  model_version: "5"
  +  canary_weight: 5

Reviewers: @devops-team

Description:
  Model v5 approved by @sarah-mle in MLflow.
  AUC: 0.923 (+0.005 vs current prod v4)
  This PR configures a 5% canary deployment.
  ArgoCD will deploy once this is merged.
```

This PR being merged is the trigger for ArgoCD to deploy. **The Git merge is the deployment trigger.**

---

## 8. Inference CI Pipeline — Deep Dive

This pipeline runs when `inference/` code changes. It is completely independent of training.

### What It Does NOT Do (Common Misconception)

```
inference-ci.yaml does NOT:
  ✗ Train any model
  ✗ Connect to MLflow to get a model
  ✗ Know which model version exists
  ✗ Test actual ML predictions (it uses mock models for tests)

inference-ci.yaml DOES:
  ✓ Test FastAPI endpoint logic (schema validation, error handling)
  ✓ Check security vulnerabilities in dependencies
  ✓ Build a Docker image containing the FastAPI code
  ✓ Push that image to the container registry (ECR/ACR)
  ✓ Tag the image with the git commit SHA (for traceability)
```

### Why the Model is NOT Baked into the Inference CI Image

This is a subtle but important architectural decision:

```
OPTION A (naive): Bake model into image during inference CI
──────────────────────────────────────────────────────────────────────
  inference-ci.yaml builds image WITH model.pkl inside

  Problems:
  - inference CI doesn't know which model version is approved
  - inference CI runs when API CODE changes, not when model changes
  - You'd need to rebuild image every time a new model is approved
  - Image becomes huge and tightly coupled to one model version
  - If model changes, you must trigger inference CI even though code is fine

OPTION B (enterprise): Image contains code only, model loaded separately
──────────────────────────────────────────────────────────────────────
  inference-ci.yaml builds image WITHOUT model
  The deployment config (ArgoCD) specifies which model to load
  The pod downloads or mounts the model at startup

  Benefits:
  - Same inference image works with any model version
  - Changing model version = one line in Git (version number)
  - Changing API code = rebuild image (separate concern)
  - Image is small and fast to build/pull
  - Full separation of concerns

  This is the pattern enterprises use.
```

### Inference CI YAML

```yaml
# .github/workflows/inference-ci.yaml

name: Inference CI — Test, Scan, Build, Push

on:
  push:
    branches: [main, develop]
    paths:
      - 'inference/**'    # Only inference code changes trigger this
      - 'requirements-serve.txt'
  pull_request:
    branches: [main]
    paths:
      - 'inference/**'

env:
  REGISTRY: ${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.us-east-1.amazonaws.com
  REPOSITORY: rotten-tomatoes-inference

jobs:
  # ═══════════════════════════════════════════════════════════════════════════
  # JOB 1: API Tests (No model — uses mock)
  # ═══════════════════════════════════════════════════════════════════════════
  api-tests:
    name: "Test Inference API"
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python 3.11
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install serving dependencies
        run: pip install -r requirements-serve.txt pytest httpx

      # ─────────────────────────────────────────────────────────────────────
      # Unit tests: Test FastAPI schemas, validation, error handling
      # These use pytest-mock to mock the ML model — no real model needed
      # ─────────────────────────────────────────────────────────────────────
      - name: Run API unit tests
        run: |
          pytest tests/inference/test_schemas.py -v
          pytest tests/inference/test_validation.py -v
          pytest tests/inference/test_error_handling.py -v

      # ─────────────────────────────────────────────────────────────────────
      # Integration test: Start FastAPI with a mock model, send real requests
      # ─────────────────────────────────────────────────────────────────────
      - name: Run integration tests
        env:
          USE_MOCK_MODEL: "true"  # inference/app.py checks this env var
        run: |
          pytest tests/inference/test_api_integration.py -v \
            --timeout=30

  # ═══════════════════════════════════════════════════════════════════════════
  # JOB 2: Security Scan
  # ═══════════════════════════════════════════════════════════════════════════
  security-scan:
    name: "Security Scan"
    runs-on: ubuntu-latest
    needs: api-tests

    steps:
      - uses: actions/checkout@v4

      # Bandit: Python source code security scanner
      # Looks for: SQL injection, hardcoded passwords, insecure SSL, etc.
      - name: Python security scan (bandit)
        run: |
          pip install bandit
          bandit -r inference/ -ll  # -ll: only medium+ severity

      # Safety: Check for known vulnerable Python packages
      - name: Dependency vulnerability check
        run: |
          pip install safety
          safety check -r requirements-serve.txt

      # Trivy: Container image vulnerability scanner
      # Runs AFTER build (in build job) — referenced here for job ordering
      - name: Check for secrets in code
        uses: trufflesecurity/trufflehog@v3
        with:
          path: ./
          base: main

  # ═══════════════════════════════════════════════════════════════════════════
  # JOB 3: Build and Push Docker Image
  # Only runs on main branch (not PRs)
  # ═══════════════════════════════════════════════════════════════════════════
  build-and-push:
    name: "Build & Push Inference Image"
    runs-on: ubuntu-latest
    needs: [api-tests, security-scan]
    if: github.ref == 'refs/heads/main'

    permissions:
      id-token: write  # Required for OIDC authentication to AWS
      contents: read

    outputs:
      image_tag: ${{ steps.meta.outputs.tags }}
      image_digest: ${{ steps.build.outputs.digest }}

    steps:
      - uses: actions/checkout@v4

      # Configure AWS credentials (using OIDC — more secure than access keys)
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1

      # Login to Amazon ECR
      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      # Generate image metadata (tags, labels)
      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.REPOSITORY }}
          tags: |
            # Tag with git commit SHA (immutable — never changes)
            type=sha,prefix=sha-
            # Tag with branch name
            type=ref,event=branch
            # Tag as "latest" on main branch
            type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}

      # Build Docker image
      # IMPORTANT: Model is NOT included. This is pure FastAPI code.
      - name: Build Docker image
        id: build
        uses: docker/build-push-action@v5
        with:
          context: .
          file: inference/Dockerfile
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          # Build args: metadata baked into image for traceability
          build-args: |
            GIT_SHA=${{ github.sha }}
            BUILD_DATE=${{ github.event.head_commit.timestamp }}
            IMAGE_VERSION=${{ github.run_number }}

      # Scan the BUILT image for vulnerabilities
      - name: Scan image for vulnerabilities
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.REPOSITORY }}:sha-${{ github.sha }}
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'
          exit-code: '1'  # Fail if critical/high CVEs found

      - name: Upload scan results
        uses: github/codeql-action/upload-sarif@v2
        if: always()
        with:
          sarif_file: 'trivy-results.sarif'
```

### The Inference Dockerfile — No Model

```dockerfile
# inference/Dockerfile
# ====================
# This builds the FastAPI serving container.
# NOTICE: No model file is copied in. Model is loaded at runtime.

FROM python:3.11-slim AS base

# Prevent pyc files and buffer stdout
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8000

# System dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# ─────────────────────────────────────────────────────────────────────────────
# DEPENDENCY LAYER (cached — only rebuilt when requirements change)
# Keep this separate from code so Docker cache is efficient.
# ─────────────────────────────────────────────────────────────────────────────
FROM base AS dependencies
COPY requirements-serve.txt /tmp/
RUN pip install --no-cache-dir -r /tmp/requirements-serve.txt

# ─────────────────────────────────────────────────────────────────────────────
# APPLICATION LAYER
# ─────────────────────────────────────────────────────────────────────────────
FROM dependencies AS app
WORKDIR /app

# Copy only inference code (no training code, no model)
COPY inference/app.py .
COPY inference/schemas.py .
COPY inference/predict.py .
COPY inference/model_loader.py .

# Build-time metadata (baked into image — useful for debugging)
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown
ARG IMAGE_VERSION=unknown
LABEL git.sha=$GIT_SHA \
      build.date=$BUILD_DATE \
      image.version=$IMAGE_VERSION

# Runtime environment variables (can be overridden in Kubernetes)
# These have defaults for local development:
ENV MLFLOW_TRACKING_URI=""
ENV MODEL_NAME="rotten-tomatoes-xgb"
ENV MODEL_STAGE="Production"

# Health check for Kubernetes liveness/readiness probes
HEALTHCHECK \
    --interval=30s \
    --timeout=5s \
    --start-period=30s \
    --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

EXPOSE ${PORT}

# Use non-root user for security
RUN useradd --system --uid 1001 appuser
USER appuser

CMD ["sh", "-c", "uvicorn app:app --host 0.0.0.0 --port ${PORT} --workers 1"]
```

### The Inference App — Model Loading Patterns

```python
# inference/model_loader.py
"""
This module handles loading the ML model.
It supports two patterns:
  A) Runtime fetch from MLflow (recommended for most setups)
  B) Local path (baked model — for maximum performance)
"""

import os
import logging
from pathlib import Path

import mlflow.pyfunc

logger = logging.getLogger(__name__)


def load_model():
    """
    Load model using the most appropriate strategy.
    Called ONCE at application startup — not per request.
    """

    # ─────────────────────────────────────────────────────────────────────────
    # STRATEGY A: Local model path (baked into image or mounted via volume)
    # Use when: model files exist at /app/model (e.g., Kubernetes volume mount)
    # Pros: Fast startup, no network dependency, works if MLflow is down
    # Cons: Changing model requires redeploy or volume remount
    # ─────────────────────────────────────────────────────────────────────────
    local_model_path = os.environ.get("MODEL_LOCAL_PATH", "/app/model")
    if Path(local_model_path).exists():
        logger.info(f"Loading model from local path: {local_model_path}")
        model = mlflow.pyfunc.load_model(local_model_path)
        logger.info("Model loaded from local path successfully")
        return model, "local"

    # ─────────────────────────────────────────────────────────────────────────
    # STRATEGY B: Runtime fetch from MLflow Registry
    # Use when: MLFLOW_TRACKING_URI is set (standard enterprise setup)
    # The model URI format: models:/model-name/stage-or-version
    #   models:/rotten-tomatoes-xgb/Production  ← always latest approved
    #   models:/rotten-tomatoes-xgb/5           ← exactly version 5
    # ─────────────────────────────────────────────────────────────────────────
    tracking_uri = os.environ.get("MLFLOW_TRACKING_URI")
    if tracking_uri:
        model_name = os.environ.get("MODEL_NAME", "rotten-tomatoes-xgb")
        model_stage = os.environ.get("MODEL_STAGE", "Production")
        model_version = os.environ.get("MODEL_VERSION", "")

        if model_version:
            # Specific version requested (e.g., set by ArgoCD from deployment config)
            model_uri = f"models:/{model_name}/{model_version}"
        else:
            # Stage-based (always gets latest approved for that stage)
            model_uri = f"models:/{model_name}/{model_stage}"

        logger.info(f"Fetching model from MLflow: {model_uri}")
        mlflow.set_tracking_uri(tracking_uri)

        model = mlflow.pyfunc.load_model(model_uri)
        logger.info(f"Model loaded from MLflow: {model_uri}")
        return model, model_uri

    raise RuntimeError(
        "No model source configured. "
        "Set MODEL_LOCAL_PATH or MLFLOW_TRACKING_URI environment variable."
    )


# ─────────────────────────────────────────────────────────────────────────────
# inference/app.py
# The FastAPI application
# ─────────────────────────────────────────────────────────────────────────────

import os
import time
import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
import pandas as pd

from schemas import PredictionRequest, PredictionResponse, HealthResponse
from model_loader import load_model

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global state (loaded once at startup)
_model = None
_model_source = None
_startup_time = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan context manager: code before 'yield' runs at startup,
    code after 'yield' runs at shutdown.
    This replaces the older @app.on_event("startup") pattern.
    """
    global _model, _model_source, _startup_time

    logger.info("🚀 Starting up inference server...")
    start = time.time()

    # Load model — this may take 5-30 seconds for large models
    _model, _model_source = load_model()

    _startup_time = time.time() - start
    logger.info(f"✅ Model ready in {_startup_time:.2f}s. Source: {_model_source}")

    yield  # Application runs here (serving requests)

    logger.info("Shutting down...")
    _model = None


app = FastAPI(
    title="Rotten Tomatoes Sentiment API",
    description="Serving rotten-tomatoes-xgb from MLflow Registry",
    version="1.0.0",
    lifespan=lifespan
)


@app.get("/health", response_model=HealthResponse)
async def health():
    """
    Health check endpoint.
    Kubernetes readiness probe calls this to know if pod can accept traffic.
    Returns 503 if model isn't loaded (pod won't receive traffic yet).
    """
    if _model is None:
        raise HTTPException(
            status_code=503,
            detail="Model not loaded — pod is not ready"
        )
    return HealthResponse(
        status="healthy",
        model_loaded=True,
        model_source=_model_source,
        startup_time_seconds=_startup_time
    )


@app.post("/predict", response_model=PredictionResponse)
async def predict(request: PredictionRequest):
    """
    Make a prediction.
    Input is validated by Pydantic schema before reaching this function.
    """
    if _model is None:
        raise HTTPException(status_code=503, detail="Model not available")

    try:
        # Convert request to DataFrame (MLflow pyfunc expects this)
        input_df = pd.DataFrame([request.features])

        # Run prediction
        prediction = _model.predict(input_df)

        return PredictionResponse(
            prediction=int(prediction[0]),
            model_source=_model_source,
            request_id=request.request_id
        )

    except Exception as e:
        logger.error(f"Prediction failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Prediction failed")
```

---

## 9. ArgoCD — The GitOps Engine

ArgoCD is the most misunderstood piece in the architecture. Let's explain it from first principles.

### The Problem ArgoCD Solves

Without ArgoCD:

```
Deployment scenario (naive):
─────────────────────────────────────────────────────────────────────────
1. You merge a PR that says "deploy model v5"
2. A GitHub Actions CD job runs kubectl apply... to update the cluster
3. Production is now running v5

Problems:
- Someone can kubectl manually change prod without a PR → invisible change
- If the job fails halfway, cluster is in an unknown state
- "What's actually running in production?" is hard to answer
- Rollback requires finding and rerunning old GitHub Actions jobs
- No continuous verification — cluster can drift without anyone knowing
```

With ArgoCD:

```
Deployment scenario (GitOps):
─────────────────────────────────────────────────────────────────────────
1. You merge a PR that says "deploy model v5" (updates deployments/ YAML)
2. ArgoCD (already running in the cluster) detects Git changed
3. ArgoCD compares Git state vs cluster state → finds drift
4. ArgoCD applies the diff → cluster matches Git
5. ArgoCD continuously verifies cluster matches Git every 3 minutes

Benefits:
- Production state is exactly what Git says → full audit trail
- Someone manually changes prod → ArgoCD detects drift → auto-reverts
- Rollback = revert the PR in Git → ArgoCD reverts the cluster
- "What's in prod?" = look at Git's main branch
- ArgoCD UI shows sync status, health of every resource
```

### How ArgoCD Watches Git

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            ARGOCD SYNC LOOP                             │
│                                                                         │
│   Every 3 minutes (or via webhook on Git push):                         │
│                                                                         │
│   [1] READ from Git:                                                    │
│       GET deployments/model-config.yaml                                 │
│       → model_version: "5"                                              │
│         canary_weight: 5                                                │
│         inference_image: "registry/inference-api:sha-abc123"            │
│                                                                         │
│   [2] READ from Kubernetes cluster:                                     │
│       GET all Deployments, Services, VirtualServices in namespace       │
│       → model Deployment: image=inference-api:sha-old999, version=4     │
│         VirtualService: weight_v4=100, weight_v5=0                      │
│                                                                         │
│   [3] COMPUTE DIFF:                                                     │
│       Git says:       version=5, canary_weight=5                        │
│       Cluster has:    version=4, canary_weight=0                        │
│       → DRIFT DETECTED                                                  │
│                                                                         │
│   [4] RECONCILE (apply the diff):                                       │
│       kubectl apply -f <computed manifests>                             │
│       → Creates new Deployment for v5 canary                            │
│       → Updates VirtualService: v4=95%, v5=5%                           │
│                                                                         │
│   [5] VERIFY (loop back to step 1):                                     │
│       Are cluster and Git now in sync?                                  │
│       If yes: status = Synced ✅                                        │
│       If no: alert + retry                                              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### What ArgoCD Reads — The Deployment Config Files

These files live in `deployments/` in your Git repo:

```yaml
# deployments/model-config.yaml
# ──────────────────────────────────────────────────────────────────────────
# This is the file that changes when a new model version is approved.
# THIS IS WHAT ARGOCD WATCHES. This IS the deployment trigger.
# ──────────────────────────────────────────────────────────────────────────

apiVersion: serving.kserve.io/v1beta1   # or Seldon, or custom
kind: InferenceService
metadata:
  name: rotten-tomatoes-model
  namespace: ml-production
  annotations:
    # Track which PR deployed this
    argocd.argoproj.io/managed-by: "argocd"
    deployment.git-sha: "abc123"

spec:
  predictor:
    # ──────────────────────────────────────────────────────────────────────
    # MODEL SOURCE: This tells ArgoCD/KServe WHERE to get the model binary.
    # It reads this, queries MLflow, downloads from S3.
    # ──────────────────────────────────────────────────────────────────────
    model:
      modelFormat:
        name: xgboost
      storageUri: "mlflow://rotten-tomatoes-xgb/5"
      # ↑ ArgoCD/KServe resolves this:
      #   1. Connect to MLflow (via env var MLFLOW_TRACKING_URI)
      #   2. Get artifact URI for rotten-tomatoes-xgb version 5
      #   3. Download model.pkl from S3
      #   4. Mount into pod at /mnt/models/

    # ──────────────────────────────────────────────────────────────────────
    # INFERENCE CONTAINER: This is the FastAPI image built by inference CI
    # ──────────────────────────────────────────────────────────────────────
    containers:
      - name: inference-server
        image: "123456789.dkr.ecr.us-east-1.amazonaws.com/rotten-tomatoes-inference:sha-abc123"
        env:
          - name: MODEL_LOCAL_PATH
            value: "/mnt/models/rotten-tomatoes-xgb/5"  # Where model is mounted
          - name: PORT
            value: "8080"
        resources:
          requests:
            memory: "2Gi"
            cpu: "1000m"
          limits:
            memory: "4Gi"
            cpu: "2000m"
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30   # Wait 30s before checking (model loading time)
          periodSeconds: 10

---
# deployments/canary-config.yaml
# Controls traffic splitting for canary deployment

apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: rotten-tomatoes-traffic
  namespace: ml-production
spec:
  hosts:
    - rotten-tomatoes-api.internal
  http:
    - route:
        # ──────────────────────────────────────────────────────────────────
        # TRAFFIC WEIGHTS: This is where canary is configured.
        # Change these numbers = change traffic split.
        # ArgoCD reads these from Git → applies to Istio → controls traffic.
        # ──────────────────────────────────────────────────────────────────
        - destination:
            host: rotten-tomatoes-stable  # service pointing to v4 pods
          weight: 95
        - destination:
            host: rotten-tomatoes-canary  # service pointing to v5 pods
          weight: 5
```

### The ArgoCD Application Object

ArgoCD needs to be told which Git repo to watch and which Kubernetes resources to manage:

```yaml
# This is deployed to your cluster ONCE to configure ArgoCD.
# After this, ArgoCD manages itself.

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ml-model-production
  namespace: argocd
spec:
  project: default

  # WHERE IS THE SOURCE OF TRUTH?
  source:
    repoURL: https://github.com/your-org/ml-repo.git
    targetRevision: main          # Watch the main branch
    path: deployments/            # Only watch this folder
    # (When deployments/ changes → ArgoCD reconciles)

  # WHERE TO DEPLOY?
  destination:
    server: https://kubernetes.default.svc   # current cluster
    namespace: ml-production

  # HOW SHOULD IT SYNC?
  syncPolicy:
    automated:
      prune: true      # Delete resources in cluster that aren't in Git
      selfHeal: true   # Auto-fix drift (someone manually changes prod → revert)
    syncOptions:
      - CreateNamespace=true  # Create namespace if it doesn't exist
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

---

## 10. Kubernetes — The Runtime

Kubernetes is where your model actually serves predictions. Understanding its key objects is essential.

### The Objects That Matter for ML Serving

```
END TO END CANARY INFERENCE DEPLOYMENT ON KUBERNETES

                                    USER REQUEST
                                         │
                                         ▼
                          HTTPS POST /predict to api.company.com
                                         │
                                         ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│ EXTERNAL ENTRY LAYER                                                          │
│ ------------------------------------------------------------------------------│
│ INGRESS (nginx-ingress / AWS ALB)                                             │
│ Routes external HTTPS traffic into the Kubernetes cluster.                    │
│ Example: api.company.com/predict                                              │
│                                                                               │
│ YAML:                                                                         │
│ apiVersion: networking.k8s.io/v1                                              │
│ kind: Ingress                                                                 │
│ spec:                                                                         │
│   rules:                                                                      │
│     - host: api.company.com                                                   │
│       http:                                                                   │
│         paths:                                                                │
│           - path: /predict                                                    │
│             backend:                                                          │
│               service:                                                        │
│                 name: rotten-tomatoes-service                                 │
│                 port: { number: 80 }                                          │
└──────────────────────────────────────┬────────────────────────────────────────┘
                                       │
                                       │ forwards matched traffic
                                       ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│ CLUSTER ENTRY / ROUTING HANDOFF                                               │
│ ------------------------------------------------------------------------------│
│ rotten-tomatoes-service                                                       │
│ Stable internal entrypoint exposed inside the cluster.                        │
│ This is the service the Ingress points to before mesh routing decisions.      │
└──────────────────────────────────────┬────────────────────────────────────────┘
                                       │
                                       ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│ ISTIO TRAFFIC MANAGEMENT LAYER                                                │
│ ------------------------------------------------------------------------------│
│ ISTIO VIRTUALSERVICE (traffic splitting for canary deployment)                │
│ Operates inside the cluster.                                                  │
│ Splits traffic by percentage between two release paths.                       │
│ This is the component that makes canary deployment work.                      │
│                                                                               │
│ Traffic policy:                                                               │
│   95%  -> stable-service  -> stable Deployment (model v4)                     │
│    5%  -> canary-service  -> canary Deployment (model v5)                     │
└───────────────────────────────┬───────────────────────────────┬───────────────┘
                                │                               │
                              95%                             5%
                                │                               │
                                ▼                               ▼

┌─────────────────────────────────────────────┐   ┌─────────────────────────────────────────────┐
│ SERVICE (stable)                            │   │ SERVICE (canary)                            │
│ ------------------------------------------- │   │ ------------------------------------------- │
│ Type: ClusterIP                             │   │ Type: ClusterIP                             │
│ Selector:                                   │   │ Selector:                                   │
│   app: inference                            │   │   app: inference                            │
│   version: "v4"                             │   │   version: "v5"                             │
│                                             │   │                                             │
│ Routes to all pods with label version=v4    │   │ Routes to all pods with label version=v5    │
└──────────────────────────┬──────────────────┘   └──────────────────────────┬──────────────────┘
                           │                                                 │
                           ▼                                                 ▼

┌─────────────────────────────────────────────┐   ┌─────────────────────────────────────────────┐
│ DEPLOYMENT (stable)                         │   │ DEPLOYMENT (canary)                         │
│ ------------------------------------------- │   │ ------------------------------------------- │
│ replicas: 3                                 │   │ replicas: 1                                 │
│ template:                                   │   │ template:                                   │
│   labels:                                   │   │   labels:                                   │
│     version: "v4"                           │   │     version: "v5"                           │
│   spec:                                     │   │   spec:                                     │
│     containers:                             │   │     containers:                             │
│       - image: api:sha-old                  │   │       - image: api:sha-new                  │
│         env:                                │   │         env:                                │
│           MODEL_VERSION: 4                  │   │           MODEL_VERSION: 5                  │
└──────────────────────────┬──────────────────┘   └──────────────────────────┬──────────────────┘
                           │                                                 │
                           ▼                                                 ▼

┌─────────────────────────────────────────────┐   ┌─────────────────────────────────────────────┐
│ PODS: STABLE RELEASE                        │   │ PODS: CANARY RELEASE                        │
│ ------------------------------------------- │   │ ------------------------------------------- │
│  POD (v4)     POD (v4)     POD (v4)         │   │  POD (v5)                                   │
│ ┌─────────┐  ┌─────────┐  ┌─────────┐       │   │ ┌─────────┐                                 │
│ │ FastAPI │  │ FastAPI │  │ FastAPI │       │   │ │ FastAPI │                                 │
│ │ model:4 │  │ model:4 │  │ model:4 │       │   │ │ model:5 │                                 │
│ └─────────┘  └─────────┘  └─────────┘       │   │ └─────────┘                                 │
└─────────────────────────────────────────────┘   └─────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────────┐
│ POD RUNTIME BEHAVIOR                                                          │
│ ---------------------------------------------------------------------------   │
│ Each pod performs:                                                            │
│ - Model Fetch: Downloads model.pkl from S3 at startup                         │
│   (or mounts model artifacts from a volume)                                   │
│ - Hydration: Loads weights into RAM/GPU memory                                │
│ - Execution: Runs inference on incoming JSON payloads                         │
│ - Serves /predict requests                                                    │
│ - Response: Sends 200 OK + Prediction back upstream                           │
└──────────────────────────────────────┬────────────────────────────────────────┘
                                       │
                                       │ emits telemetry
                                       ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│ OBSERVABILITY & MONITORING LAYER                                              │
│ ---------------------------------------------------------------------------   │
│ [1] Metrics: Latency, throughput (Prometheus -> Grafana)                      │
│ [2] Logs: Request/Response payloads (Elastic / Splunk)                        │
│ [3] ML Quality: Data Drift & Accuracy (Evidently AI / Arize)                  │
└──────────────────────────────────────┬────────────────────────────────────────┘
                                       │
                                       ▼
                           Optional: Retrain Trigger / Alerting

RESPONSE PATH
Pod -> Service -> Istio VirtualService route -> Ingress -> User
```

### Pod Lifecycle — What Happens When a New Pod Starts

```
ArgoCD creates new canary pod:
       │
       ▼
Kubernetes schedules pod to a node (physical machine)
       │
       ▼
Container runtime pulls Docker image from ECR:
  registry/inference-api:sha-abc123
  (This is the image built by inference CI — no model inside)
       │
       ▼
Container starts. Uvicorn starts FastAPI.
FastAPI's lifespan startup runs:
       │
       ▼
model_loader.load_model() is called:
  1. Check MODEL_LOCAL_PATH → does /app/model exist?

  Case A: No local model (runtime fetch pattern)
    → mlflow.pyfunc.load_model("models:/rt-xgb/5")
    → MLflow resolves URI → gets S3 path → downloads model.pkl from S3
    → Loads model into Python memory
    → ~15-60 seconds for large models

  Case B: Volume-mounted model (production pattern)
    → Kubernetes has already downloaded model to a PersistentVolume
    → Pod mounts PVC at /app/model
    → load_model("/app/model") is instant
    → ~2-5 seconds
       │
       ▼
/health endpoint returns 200
       │
       ▼
Kubernetes readinessProbe passes → pod added to Service endpoints
       │
       ▼
Istio VirtualService starts routing 5% traffic to this pod
       │
       ▼
Pod is now serving real predictions.
```

### Kubernetes Deployment YAML (Full Example)

```yaml
# deployments/kubernetes/deployment-canary.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: rotten-tomatoes-canary
  namespace: ml-production
  labels:
    app: rotten-tomatoes
    version: "v5"
    # ↑ Labels are KEY. Services and VirtualServices use them to route traffic.
spec:
  replicas: 1   # Only 1 canary pod (handles 5% of traffic)

  selector:
    matchLabels:
      app: rotten-tomatoes
      version: "v5"

  template:
    metadata:
      labels:
        app: rotten-tomatoes
        version: "v5"

    spec:
      containers:
        - name: inference-server

          # ──────────────────────────────────────────────────────────────────
          # IMAGE: The FastAPI code. Built by inference CI. Has no model.
          # The SHA tag means this is immutable — exactly this git commit.
          # ──────────────────────────────────────────────────────────────────
          image: "123456789.dkr.ecr.us-east-1.amazonaws.com/rotten-tomatoes-inference:sha-abc123"

          imagePullPolicy: Always  # Always pull fresh (don't use cached)

          ports:
            - containerPort: 8080

          # ──────────────────────────────────────────────────────────────────
          # ENVIRONMENT VARIABLES: Configure the pod's behavior.
          # These override any defaults in the Docker image.
          # ──────────────────────────────────────────────────────────────────
          env:
            # Tell FastAPI app which MLflow server to connect to
            - name: MLFLOW_TRACKING_URI
              valueFrom:
                secretKeyRef:
                  name: mlflow-credentials   # Kubernetes Secret
                  key: tracking_uri

            # Specifically request version 5 (not stage — more deterministic)
            - name: MODEL_NAME
              value: "rotten-tomatoes-xgb"
            - name: MODEL_VERSION
              value: "5"               # ← THIS LINE CHANGES WHEN NEW MODEL DEPLOYS

            # MLflow credentials (stored as Kubernetes Secret, not ConfigMap)
            - name: MLFLOW_TRACKING_USERNAME
              valueFrom:
                secretKeyRef:
                  name: mlflow-credentials
                  key: username
            - name: MLFLOW_TRACKING_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mlflow-credentials
                  key: password

          # ──────────────────────────────────────────────────────────────────
          # RESOURCE LIMITS: Prevent one pod from consuming all node resources
          # ──────────────────────────────────────────────────────────────────
          resources:
            requests:        # Kubernetes uses this to SCHEDULE the pod
              memory: "1Gi"  # "I need at least 1GB RAM"
              cpu: "500m"    # "I need at least 0.5 CPU cores" (m = millicores)
            limits:          # Kubernetes uses this to THROTTLE the pod
              memory: "2Gi"  # "Kill me if I use more than 2GB RAM"
              cpu: "1000m"   # "Throttle me if I use more than 1 core"

          # ──────────────────────────────────────────────────────────────────
          # HEALTH PROBES: Kubernetes needs to know if pod is alive and ready
          # ──────────────────────────────────────────────────────────────────

          # readinessProbe: "Is this pod ready to receive traffic?"
          # FAILED = pod removed from service, no traffic until it passes
          readinessProbe:
            httpGet:
              path: /health    # FastAPI's /health endpoint
              port: 8080
            initialDelaySeconds: 30   # Wait 30s before first check
            # (model loading can take 20-30s — don't probe too early)
            periodSeconds: 10         # Check every 10s
            failureThreshold: 3       # 3 failures in a row → pod is unready

          # livenessProbe: "Is this pod still alive (not deadlocked)?"
          # FAILED = Kubernetes kills and restarts the pod
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 60   # More lenient — give more startup time
            periodSeconds: 30
            failureThreshold: 5       # More tolerant — don't restart too eagerly
```

---

## 11. How ALL Components Connect — The Complete Data Flow

This is the end-to-end trace of the **most important scenario**: a hyperparameter change leading to a new model in production.

```
TIME       EVENT                    COMPONENT          ACTION
─────────────────────────────────────────────────────────────────────────────────────

09:00      Dev changes              GIT                Commit pushed to main:
           max_depth: 4 → 6                           configs/hyperparams.yaml

09:01      GitHub detects           GITHUB             Webhook fired to GitHub Actions
           file path match          ACTIONS            training-ci.yaml triggers

09:01      Unit tests run           GITHUB             pytest tests/unit/ → 47 PASS
                                    ACTIONS

09:02      Training job             GITHUB             python training/train.py
           launched                 ACTIONS            (on ephemeral Ubuntu VM)

09:02      MLflow Run created       MLFLOW             HTTP POST /api/2.0/mlflow/runs/create
                                    TRACKING           → run_id: "eee555abc..."
                                                       → DB row created in 'runs' table

09:02      Params logged            MLFLOW             HTTP POST /api/2.0/mlflow/runs/log-param
                                    TRACKING           → {max_depth: 6, n_estimators: 200}
                                                       → Stored in 'params' table

09:45      Training completes       GITHUB             model.fit() finishes
                                    ACTIONS

09:45      Metrics logged           MLFLOW             HTTP POST /api/2.0/mlflow/runs/log-metric
                                    TRACKING           → {auc: 0.923, f1: 0.891}
                                                       → Stored in 'metrics' table

09:45      Model uploaded           MLFLOW             mlflow.xgboost.log_model() called
                                    ARTIFACT STORE     → Serializes model to model.ubj
                                                       → Uploads to S3:
                                                          s3://mlflow-artifacts/
                                                            eee555abc/model/
                                                            ├── model.ubj
                                                            ├── MLmodel
                                                            ├── conda.yaml
                                                            └── requirements.txt
                                                       → Records S3 URI in DB

09:45      Registry entry created   MLFLOW             client.create_model_version()
                                    REGISTRY           → model_versions table:
                                                          name: rotten-tomatoes-xgb
                                                          version: 5
                                                          stage: None
                                                          run_id: eee555abc

09:46      Quality gates run        GITHUB             python training/evaluate.py
                                    ACTIONS            → Fetches metrics from MLflow
                                                       → Compares vs thresholds
                                                       → ALL PASS ✅

09:46      Model promoted           MLFLOW             client.transition_model_version_stage()
           to Staging               REGISTRY           → version 5 → stage: Staging
                                                       → old Staging (v3) → Archived

09:47      Slack alert fires        GITHUB             "✅ Model v5 in Staging.
                                    ACTIONS             AUC=0.923. Review now."

09:47      Runner VM destroyed      GITHUB             Ephemeral VM deleted.
                                    ACTIONS            All state is in MLflow + S3.

─── MODEL EXISTS IN STAGING. NOTHING IS DEPLOYED. WAITING FOR HUMAN. ───

10:30      Sarah reviews            MLFLOW UI           Opens MLflow UI
                                                        Compares v5 vs v4
                                                        Checks confusion matrix, SHAP
                                                        Satisfied → clicks "Production"

10:31      Stage transition         MLFLOW             client.transition_model_version_stage()
                                    REGISTRY           → version 5 → stage: Production
                                                       → version 4 → stage: Archived

10:31      Webhook fires            MLFLOW →           MLflow webhook calls GitHub API
                                    GITHUB             → Triggers script that creates PR

10:31      PR created               GITHUB             PR: "deploy rotten-tomatoes-xgb v5"
                                                        deployments/model-config.yaml:
                                                        - model_version: "4"
                                                        + model_version: "5"
                                                        + MODEL_VERSION env: "5"

10:35      DevOps reviews + merges  GITHUB             PR merged to main

10:36      ArgoCD sync loop runs    ARGOCD             Detects Git change in deployments/
                                                        Git says: version=5
                                                        Cluster has: version=4
                                                        → DRIFT DETECTED

10:36      ArgoCD queries MLflow    ARGOCD →           GET /api/2.0/mlflow/
                                    MLFLOW              registered-models/get-latest-versions
                                                        → "version 5 artifacts at:
                                                           s3://mlflow-artifacts/eee555/model/"

10:36      ArgoCD creates new pod   ARGOCD →           kubectl apply deployment-canary.yaml
                                    KUBERNETES          → Kubernetes schedules pod to node

10:36      Pod pulls Docker image   KUBERNETES →       docker pull inference-api:sha-abc123
                                    ECR                (the image built by inference CI)

10:37      Pod starts FastAPI       KUBERNETES          uvicorn starts

10:37      Model loaded             KUBERNETES →       load_model("models:/rt-xgb/5")
                                    MLFLOW              → MLflow resolves → S3 URI
                                    ↓                  → Downloads model.ubj from S3
                                    S3                  → Loads into Python memory (~20s)

10:37      Pod readiness probe      KUBERNETES          GET /health → 200 OK ✅
           passes                                       Pod added to canary Service

10:37      Istio updated            ARGOCD →           VirtualService applied:
                                    KUBERNETES          → stable (v4): weight=95
                                    ISTIO               → canary (v5): weight=5

10:37:30   CANARY IS LIVE           ALL                5% of real user traffic
                                                        hits model v5

11:37      60 min monitoring        PROMETHEUS /        error_rate_v5: 0.01% ✅
           passes all thresholds    GRAFANA             latency_p99_v5: 46ms ✅
                                                        prediction_dist: normal ✅

11:37      Auto-promote triggers    ARGOCD              Updates VirtualService:
                                    PROGRESSIVE         → stable (v5): weight=100
                                    DELIVERY            → old stable (v4): weight=0
                                                        → v4 pods: scale to 0

11:37      v5 fully in production   ALL                 100% traffic → model v5

─── DONE. 2h 37min from config change to full production rollout. ───
```

---

## 12. Human Decision Points — Where You Must Intervene

Enterprise MLOps is not fully automated. Here are the exact points where humans make decisions, what they decide, and what happens if they don't.

### Decision Point 1: Quality Gate Thresholds

**When:** Before any training run happens.
**Who decides:** ML lead / architect.
**What the decision is:** "What numerical thresholds must a model pass before being registered?"

```yaml
# configs/thresholds.yaml — humans define these values
model_quality:
  min_auc: 0.85           # Below this → model rejected, not registered
  min_f1: 0.80
  max_bias_score: 0.05    # Fairness metric — regulatory requirement
  max_latency_ms: 100     # Performance requirement

regression_protection:
  max_auc_drop_from_prod: 0.02  # New model can't be >2% worse than prod
  max_f1_drop_from_prod: 0.02

# If any of these change, it's a human policy decision — not a code bug.
```

**What if no human sets these?** Without gates, every model that completes training gets registered. Registry fills with junk. Bad models sneak into production.

### Decision Point 2: Staging → Production Promotion

**When:** After CI registers a model to Staging.
**Who decides:** ML Engineer or team lead (the "reviewer").
**What they check in MLflow UI:**

```
CHECKLIST (what a good reviewer does):
──────────────────────────────────────────────────────────────────────────

1. METRICS COMPARISON
   - Open "Compare" view: new model vs current production
   - Check: Is AUC better? By how much?
   - Check: Did any class's F1 drop significantly? (aggregate can hide this)
   - Check: Did bias score worsen even if within threshold?

2. TRAINING STABILITY
   - Download training loss curve (if logged)
   - Check: Did loss converge smoothly? Sharp spikes suggest instability.

3. FEATURE IMPORTANCE
   - If SHAP values are logged, review top features
   - Check: Did a new feature suddenly dominate? Why? Is it a leak?
   - Data leakage risk: model learning from future information

4. DATA LINEAGE
   - Check: What dataset version was used?
   - Check: git_sha tag → verify this is the code you expect
   - Can you reproduce this run from that commit? Is data still available?

5. ARTIFACTS
   - Download confusion matrix image
   - Check: Are false positive/negative rates acceptable for the use case?
   - Medical use case: false negatives more costly → different threshold

OUTCOME:
  "Approve" → clicks "Transition to Production" in MLflow UI
  "Reject"  → annotates the run with explanation, alerts team

WHAT IF HUMAN SKIPS THIS? 
  A bad model goes to production. No automated system catches:
  - Subtle bias increase
  - Performance regression on a minority class
  - Model learning from a leaky feature
  These cause slow degradation — hard to detect after the fact.
```

### Decision Point 3: PR Approval for Deployment

**When:** After MLflow promotion, an automated PR is created.
**Who decides:** DevOps engineer or senior ML engineer.
**What they check:**

```
PR REVIEW CHECKLIST:
──────────────────────────────────────────────────────────────────────────

The PR changes only ONE thing: model version number in deployment config.
But reviewer checks:

1. Does the model version in the PR match what was approved in MLflow?
   (Prevents accidental wrong-version deployments)

2. Is canary_weight set appropriately?
   - New, risky model → start at 1% or 5%
   - Minor tune of stable model → can start at 10% or 25%

3. Are rollback configs in place?
   - Is previous version still in the config as fallback?
   - Is auto_rollback enabled?

4. Is this the right time to deploy?
   - Avoid deployments on Fridays, holiday eves, high-traffic events
   - Check: is there an incident in progress? Freeze deployments.

OUTCOME:
  "Approve and merge" → ArgoCD deploys
  "Request changes"   → Version bumped back or timing adjusted
```

### Decision Point 4: Canary Promotion Decision

**When:** During canary rollout, as traffic weight increases.
**Who decides:** Can be automated (recommended) or manual.
**The decision criteria:**

```
AUTOMATED PROMOTION (ArgoCD Progressive Delivery / Flagger):
──────────────────────────────────────────────────────────────────────────

Configuration in Git:
  auto_promote:
    enabled: true
    schedule:
      - after: 10min,  set_weight: 10%
      - after: 30min,  set_weight: 25%
      - after: 60min,  set_weight: 50%
      - after: 120min, set_weight: 100%
    abort_if:
      error_rate_above: 1.0   # % of 5xx responses
      latency_p99_above: 200  # ms

  auto_rollback:
    enabled: true
    on: abort_conditions_met
    action: set_weight_to_zero

MANUAL PROMOTION:
  ML Engineer watches Grafana dashboard
  At each threshold (30min, 1hr):
    - Are metrics holding?
    - No anomalies in prediction distribution?
    - No user complaints in Slack?
  → If yes: manually update canary_weight in Git → creates PR → merge
  → If no: rollback by setting canary_weight: 0 in Git → merge

WHEN MANUAL IS BETTER:
  - High-stakes domain (healthcare, finance)
  - First deployment of a major model change
  - When you don't yet have good automated monitoring

WHEN AUTOMATED IS BETTER:
  - Stable, well-monitored service
  - High deployment frequency (multiple per day)
  - After humans have validated the monitoring is trustworthy
```

### Decision Point 5: Rollback Decision

**When:** Something goes wrong in production.
**Who decides:** Oncall engineer + ML team.
**Decision tree:**

```
ALERT FIRES: error rate spiked on canary pods
       │
       ▼
  Was this spike in the CANARY pods (v5) only?
  ─────────────────────────────────────────────────
  YES → Model v5 is bad.
        → Immediately rollback: set canary_weight=0 in Git
        → Model v5 removed. Traffic → 100% to v4.
        → File post-mortem on why quality gates passed a bad model.

  NO (both v4 and v5 spiking) → Infrastructure issue, not model.
        → Check: database down? Data pipeline broken? Network issue?
        → Do NOT rollback model — it won't help.
        → Escalate to infrastructure oncall.

ROLLBACK EXECUTION (GitOps way — 30 seconds):
  git checkout main
  # Edit deployments/model-config.yaml:
  # set canary_weight: 0
  git commit -m "rollback: revert canary v5 - elevated error rate"
  git push
  # ArgoCD detects change → sets traffic to 0% canary in Istio
  # Total time from push to traffic rerouted: ~30 seconds
```

---

## 13. Nuanced Decision Making — Enterprise Choices

### Should You Bake the Model into the Docker Image or Fetch at Runtime?

This is one of the most common architecture debates in MLOps.

```
┌─────────────────────────────────────────────────────────────────────────┐
│  OPTION A: Bake model into Docker image at CD time                      │
│                                                                         │
│  How it works:                                                          │
│    CD pipeline runs:                                                    │
│    1. Download model v5 from MLflow to /tmp/model                       │
│    2. docker build --build-arg MODEL_PATH=/tmp/model ...                │
│    3. COPY ${MODEL_PATH} /app/model  (in Dockerfile)                    │
│    4. Push image containing model                                       │
│    5. Pod pulls image — model already inside                            │
│                                                                         │
│  Pros:                                                                  │
│  ✓ Pod startup is fast (no download at runtime)                         │
│  ✓ Pod is self-contained — works if MLflow is down                      │
│  ✓ Image is immutable — exact model + code combination is fixed         │
│  ✓ Easy audit: this image SHA = this model version                      │
│                                                                         │
│  Cons:                                                                  │
│  ✗ Large Docker images (model can be 500MB+)                            │
│  ✗ New model version = new image build (slower deploys)                 │
│  ✗ Rollback to model v4 requires building a v4 image if not cached      │
│  ✗ Same inference code + different model = different image tag          │
│                                                                         │
│  BEST FOR: Large models (1GB+), low-latency startup requirements,       │
│  air-gapped environments, strong immutability requirements              │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  OPTION B: Fetch model from MLflow at pod startup (runtime fetch)       │
│                                                                         │
│  How it works:                                                          │
│    Docker image contains ONLY FastAPI code                              │
│    Pod's env vars specify: MLFLOW_TRACKING_URI + MODEL_VERSION=5        │
│    At startup: app downloads model v5 from MLflow/S3                    │
│    Model cached in pod memory — no per-request downloads                │
│                                                                         │
│  Pros:                                                                  │
│  ✓ Small Docker image (fast pull)                                       │
│  ✓ Same image works with any model version                              │
│  ✓ Change model: just update MODEL_VERSION env var in K8s config        │
│  ✓ Rollback = change env var in Git, ArgoCD applies, pods restart       │
│  ✓ Clear separation: code image ↔ model artifact                        │
│                                                                         │
│  Cons:                                                                  │
│  ✗ Slower pod startup (download on every new pod)                       │
│  ✗ MLflow server must be reachable at pod startup time                  │
│  ✗ If MLflow is down + pods restart → service outage                    │
│  ✗ S3 egress costs at scale (many pods downloading same model)          │
│                                                                         │
│  BEST FOR: Frequently updated models, small-medium models (<500MB),     │
│  teams with many different experiments, fast iteration velocity         │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  OPTION C: Kubernetes PersistentVolume (enterprise hybrid)              │
│                                                                         │
│  How it works:                                                          │
│    A separate "model download" init-container runs before the main pod  │
│    It downloads the model from S3 to a shared volume                    │
│    Main pod mounts the volume and loads model from disk (fast)          │
│                                                                         │
│  Kubernetes YAML:                                                       │
│    spec:                                                                │
│      initContainers:                                                    │
│        - name: model-downloader                                         │
│          image: aws-cli:latest                                          │
│          command:                                                       │
│            - aws s3 cp                                                  │
│            - s3://mlflow-artifacts/eee555/model/ /mnt/model/            │
│            - --recursive                                                │
│          volumeMounts:                                                  │
│            - name: model-volume                                         │
│              mountPath: /mnt/model                                      │
│      containers:                                                        │
│        - name: inference-server                                         │
│          env:                                                           │
│            - name: MODEL_LOCAL_PATH                                     │
│              value: /mnt/model                                          │
│          volumeMounts:                                                  │
│            - name: model-volume                                         │
│              mountPath: /mnt/model                                      │
│      volumes:                                                           │
│        - name: model-volume                                             │
│          emptyDir: {}   # Shared between init and main container        │
│                                                                         │
│  Pros:                                                                  │
│  ✓ Fast main container startup                                          │
│  ✓ Clean separation of concerns                                         │
│  ✓ Works well with KServe/Seldon (they use this pattern natively)       │
│                                                                         │
│  Cons:                                                                  │
│  ✗ More complex configuration                                           │
│  ✗ Init container must complete before main container starts            │
│                                                                         │
│  BEST FOR: Production enterprise setups with dedicated serving platforms│
└─────────────────────────────────────────────────────────────────────────┘
```

### Should You Use Seldon / KServe or Build Your Own FastAPI?

```
ROLL YOUR OWN (FastAPI + Docker):
──────────────────────────────────────────────────────────────────────────
  You write the FastAPI code, the Dockerfile, the Kubernetes manifests.
  You control everything.

  Best for:
  - Custom preprocessing that doesn't fit standard frameworks
  - Non-standard model inputs/outputs
  - Team has strong software engineering skills
  - You need full control for compliance/audit
  - Starting point: it's simpler to understand

  Limitations:
  - You implement canary splitting yourself (Istio)
  - You implement auto-scaling yourself (HPA)
  - You implement A/B testing yourself
  - No built-in model explainability endpoints

SELDON CORE or KSERVE:
──────────────────────────────────────────────────────────────────────────
  A Kubernetes operator that understands MLflow model format.
  You give it: model URI + framework name. It handles the rest.

  Best for:
  - Teams without strong software engineering background
  - Standard ML models (sklearn, XGBoost, TF, PyTorch)
  - Built-in canary, A/B testing, shadow deployment
  - Built-in model explainability (Alibi)
  - Multi-model serving (multiple models, one server)

  KServe YAML (it's this simple):
  apiVersion: serving.kserve.io/v1beta1
  kind: InferenceService
  spec:
    predictor:
      model:
        modelFormat: { name: xgboost }
        storageUri: "gs://bucket/model.bst"

  KServe handles: downloading model, serving, canary, scaling.
  You handle: none of the above.

  Limitations:
  - Less flexible for custom preprocessing
  - Adds operational complexity (another operator to manage)
  - Overkill for simple use cases

RECOMMENDATION:
  Start with FastAPI + Docker. It teaches you the fundamentals.
  Migrate to KServe/Seldon when you have multiple models to manage.
```

---

## 14. Complete Code Reference — Every File Explained

### Project Structure

```
rotten-tomatoes-mlops/
│
├── .github/
│   └── workflows/
│       ├── training-ci.yaml          # PIPELINE 1: Train → Evaluate → Register
│       └── inference-ci.yaml         # PIPELINE 2: Test → Scan → Build → Push
│
├── training/
│   ├── train.py                      # Main training script (WRITES to MLflow)
│   ├── features.py                   # Feature engineering (pure Python)
│   ├── evaluate.py                   # Quality gate checker (READS from MLflow)
│   ├── register.py                   # Registry promoter (WRITES to MLflow Registry)
│   └── Dockerfile                    # Training container (not inference)
│
├── inference/
│   ├── app.py                        # FastAPI application
│   ├── schemas.py                    # Pydantic request/response schemas
│   ├── model_loader.py               # Model loading logic
│   ├── predict.py                    # Prediction logic
│   └── Dockerfile                    # Inference container (no model inside)
│
├── configs/
│   ├── hyperparams.yaml              # Model hyperparameters (changes → retrain)
│   └── thresholds.yaml              # Quality gate thresholds (changes → retrain)
│
├── deployments/
│   ├── model-config.yaml             # ArgoCD watches this (version lives here)
│   └── kubernetes/
│       ├── deployment-stable.yaml    # K8s Deployment for stable model
│       ├── deployment-canary.yaml    # K8s Deployment for canary model
│       ├── service-stable.yaml       # K8s Service for stable pods
│       ├── service-canary.yaml       # K8s Service for canary pods
│       ├── virtual-service.yaml      # Istio traffic splitting config
│       └── argocd-application.yaml   # ArgoCD watches this folder
│
├── tests/
│   ├── unit/                         # Pure Python tests (no model, no network)
│   └── inference/                    # API tests (mock model)
│
├── scripts/
│   ├── create_gitops_pr.py           # Webhook receiver → creates deployment PR
│   └── promote_model.py             # Manual promotion script (alternative to UI)
│
├── requirements.txt                  # Training dependencies
├── requirements-serve.txt            # Inference serving dependencies
└── monitoring/
    ├── alerts.yaml                   # Prometheus alert rules
    └── grafana-dashboard.json        # Grafana dashboard definition
```

### The Evaluation Script (Quality Gates)

```python
# training/evaluate.py
"""
Runs quality gates against a trained MLflow run.
Exits with code 0 (success) if all gates pass.
Exits with code 1 (failure) if any gate fails.
GitHub Actions checks the exit code — failure stops the pipeline.
"""

import argparse
import os
import sys
import yaml
import mlflow
from mlflow.tracking import MlflowClient


def evaluate(run_id: str, model_name: str, config_path: str, compare_to_prod: bool):

    mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
    client = MlflowClient()

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 1: Fetch metrics of the run we just trained
    # ─────────────────────────────────────────────────────────────────────────
    run = client.get_run(run_id)
    new_metrics = run.data.metrics

    print(f"\n{'='*60}")
    print(f"QUALITY GATE EVALUATION — Run: {run_id}")
    print(f"{'='*60}")
    print(f"New model metrics: {new_metrics}")

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 2: Load thresholds from config
    # ─────────────────────────────────────────────────────────────────────────
    with open(config_path) as f:
        config = yaml.safe_load(f)

    thresholds = config["model_quality"]
    regression = config.get("regression_protection", {})

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 3: Absolute threshold checks
    # ─────────────────────────────────────────────────────────────────────────
    failures = []

    for metric_name, min_value in thresholds.items():
        actual = new_metrics.get(metric_name)
        if actual is None:
            failures.append(f"MISSING metric: {metric_name} was not logged")
            continue

        if metric_name.startswith("max_"):
            # "max_" prefix: value must be BELOW threshold
            clean_name = metric_name[4:]
            actual = new_metrics.get(clean_name)
            if actual > min_value:
                failures.append(
                    f"FAILED {clean_name}: {actual:.4f} > max {min_value}"
                )
            else:
                print(f"✅ {clean_name}: {actual:.4f} <= {min_value}")
        else:
            # Must be ABOVE threshold
            if actual < min_value:
                failures.append(
                    f"FAILED {metric_name}: {actual:.4f} < min {min_value}"
                )
            else:
                print(f"✅ {metric_name}: {actual:.4f} >= {min_value}")

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 4: Regression protection (compare against current Production)
    # ─────────────────────────────────────────────────────────────────────────
    if compare_to_prod and regression:
        prod_versions = client.get_latest_versions(model_name, stages=["Production"])

        if prod_versions:
            prod_run_id = prod_versions[0].run_id
            prod_metrics = client.get_run(prod_run_id).data.metrics
            print(f"\nComparing vs Production (run: {prod_run_id}):")

            for metric_name, max_drop in regression.items():
                clean_name = metric_name.replace("max_", "").replace("_drop_from_prod", "")
                new_val = new_metrics.get(clean_name, 0)
                prod_val = prod_metrics.get(clean_name, 0)
                drop = prod_val - new_val

                if drop > max_drop:
                    failures.append(
                        f"REGRESSION {clean_name}: dropped by {drop:.4f} "
                        f"(max allowed: {max_drop}). "
                        f"Prod: {prod_val:.4f}, New: {new_val:.4f}"
                    )
                else:
                    improvement = new_val - prod_val
                    sign = "+" if improvement >= 0 else ""
                    print(f"✅ {clean_name}: {sign}{improvement:.4f} vs prod")
        else:
            print("No Production model found — skipping regression check")

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 5: Final verdict
    # ─────────────────────────────────────────────────────────────────────────
    print(f"\n{'='*60}")
    if failures:
        print("❌ QUALITY GATES FAILED:")
        for f in failures:
            print(f"   • {f}")
        print("Model will NOT be registered.")
        sys.exit(1)   # ← Exit code 1 → GitHub Actions marks step as failed
    else:
        print("✅ ALL QUALITY GATES PASSED")
        print("Model will be promoted to Staging.")
        sys.exit(0)   # ← Exit code 0 → GitHub Actions marks step as succeeded


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--model-name", required=True)
    parser.add_argument("--config", default="configs/thresholds.yaml")
    parser.add_argument("--compare-to-production", default="true")
    args = parser.parse_args()

    evaluate(
        run_id=args.run_id,
        model_name=args.model_name,
        config_path=args.config,
        compare_to_prod=args.compare_to_production.lower() == "true"
    )
```

### The Schemas File

```python
# inference/schemas.py
"""
Pydantic schemas define the exact shape of API requests and responses.
This provides:
1. Automatic input validation (wrong types → 422 error, not crash)
2. Clear API documentation (FastAPI auto-generates OpenAPI docs)
3. Protection against schema drift between training and inference
"""

from pydantic import BaseModel, Field, field_validator
from typing import Optional


class PredictionRequest(BaseModel):
    """Input to the /predict endpoint."""

    features: dict = Field(
        ...,
        description="Feature dictionary. Keys must match training schema.",
        example={
            "review_length": 150,
            "sentiment_score": 0.72,
            "has_exclamation": 1,
            "star_rating": 4
        }
    )

    # Optional trace ID for debugging and correlation
    request_id: Optional[str] = Field(
        None,
        description="Client-provided trace ID for request correlation"
    )

    @field_validator("features")
    @classmethod
    def validate_features(cls, v):
        """
        Validate that required features are present.
        This protects against client code that forgot to include a feature.
        """
        required_features = {
            "review_length", "sentiment_score", "has_exclamation", "star_rating"
        }
        missing = required_features - set(v.keys())
        if missing:
            raise ValueError(f"Missing required features: {missing}")
        return v


class PredictionResponse(BaseModel):
    """Output from the /predict endpoint."""

    prediction: int = Field(
        ...,
        description="Predicted class. 0=negative, 1=positive",
        ge=0, le=1
    )

    probability: Optional[float] = Field(
        None,
        description="Confidence score for the predicted class",
        ge=0.0, le=1.0
    )

    model_source: str = Field(
        ...,
        description="MLflow URI of the model that made this prediction"
    )

    request_id: Optional[str] = None


class HealthResponse(BaseModel):
    """Output from the /health endpoint."""

    status: str
    model_loaded: bool
    model_source: Optional[str] = None
    startup_time_seconds: Optional[float] = None
```

### The Configs

```yaml
# configs/hyperparams.yaml
# Changing this file triggers training-ci.yaml to retrain.

model:
  max_depth: 6
  n_estimators: 200
  learning_rate: 0.1
  subsample: 0.8
  colsample_bytree: 0.8
  random_state: 42
  eval_metric: "auc"
  use_label_encoder: false

data:
  train_data_path: "s3://data-lake/rotten-tomatoes/train.parquet"
  test_size: 0.2
  random_state: 42
```

```yaml
# configs/thresholds.yaml
# Quality gates — humans set these as policy decisions.

model_quality:
  auc: 0.85               # AUC must be >= 0.85
  f1: 0.80                # F1 must be >= 0.80
  max_bias_score: 0.05    # Bias score must be <= 0.05
  max_latency_p99_ms: 100 # Inference latency must be <= 100ms

regression_protection:
  # New model can't be more than X worse than current production
  max_auc_drop_from_prod: 0.02
  max_f1_drop_from_prod: 0.02
```

---

## 15. Interview Preparation — Questions and Full Answers

### "Explain the role of MLflow in an enterprise MLOps pipeline."

**Full answer:**

> MLflow serves three distinct roles that are easy to conflate. First, as an **experiment tracker**, it records every training run — params, metrics, artifacts — giving teams reproducibility and comparison capabilities. Second, as a **model registry**, it implements a stage-based approval workflow: every trained model starts at None, passes automated quality gates to reach Staging, requires human approval to reach Production, and gets Archived when superseded. This Registry is the bridge between CI and CD — CI writes to it, CD reads from it. Third, as an **artifact store** coordinator, it manages the addresses of model binaries stored in S3 or Azure Blob — the actual binary never lives in MLflow's database, just the pointer to it.

---

### "How is training CI different from inference CI?"

**Full answer:**

> They are triggered by different code changes, have different purposes, and produce different outputs. Training CI triggers when training code or config files change. Its job is to retrain the model, evaluate it against quality gates, and if it passes, register it to MLflow Staging. It writes to MLflow extensively. Inference CI triggers when serving code changes — the FastAPI app, schemas, or Dockerfile. Its job has nothing to do with models: it tests the API logic with mock models, runs security scans, builds a Docker image containing only the serving code (no model binary), and pushes that image to a container registry. The model is loaded separately at runtime. The two pipelines are completely decoupled — changing inference code does not retrain the model, and training a new model does not rebuild the inference image.

---

### "What is GitOps and how does ArgoCD implement it?"

**Full answer:**

> GitOps is a pattern where Git is the single, authoritative source of truth for what should be running in production. To change production, you change Git — there is no direct `kubectl apply` in CI/CD. ArgoCD implements this by running inside the Kubernetes cluster and continuously watching a designated Git repository folder. Every few minutes, it reads the desired state from Git — what model version, what image, what resource counts — and reads the actual state from the cluster. If they differ (drift), it reconciles the cluster to match Git. This means rollback is simply reverting a commit in Git, and the cluster auto-corrects. Manual production changes are impossible without leaving a Git trail. The audit log is Git's commit history.

---

### "How do you achieve zero-downtime model deployments?"

**Full answer:**

> Zero downtime comes from combining three things. First, canary deployment: traffic is split so only a small percentage of users (5%) hit the new model while 95% stay on the stable version. If the new model crashes, only 5% of traffic is affected. Second, Kubernetes readiness probes: pods don't receive traffic until the /health endpoint returns 200 — meaning the model is fully loaded and ready. So there's no window where traffic hits a pod that hasn't finished loading the model. Third, the old pods are not deleted until the new ones are healthy — Kubernetes Deployments use a rolling update strategy by default. Combined, a new model version can be deployed, tested on real traffic at low volume, and promoted to 100% — all with zero downtime and instant rollback available throughout.

---

### "What happens when data drift is detected?"

**Full answer:**

> Data drift means the statistical distribution of your live input data has shifted from the training data distribution. The typical detection mechanism uses tools like Evidently AI or a custom implementation of PSI (Population Stability Index) or KS test. These run on a schedule — hourly or daily — comparing a sample of live predictions against the training data reference. When drift is detected above a threshold, the response depends on severity. Mild drift triggers an alert to the data team via Slack or PagerDuty for investigation. Severe drift can trigger an automatic freeze on further model promotions and a flag for retraining. Retraining doesn't happen automatically on drift alone — a human decides whether to retrain with new data, whether the drift is expected (seasonal patterns), and whether the model is still performing acceptably on business metrics despite the distribution shift.

---

### "How does model versioning work with rollback?"

**Full answer:**

> Model versioning has two separate dimensions: the MLflow Registry version number (which model was approved) and the Docker image tag (which serving code is deployed). In MLflow, every training run that passes quality gates creates a new version number, and the model binary is preserved in S3 indefinitely. So rolling back to model v4 after promoting v5 is instant — you change one line in the deployment config YAML in Git from `model_version: 5` to `model_version: 4`, create a PR, merge it, and ArgoCD reconciles the cluster. The old model binary is still in S3, so no retraining is needed. The rollback takes about 30 seconds from PR merge to traffic rerouted. Similarly, rolling back the inference code is just updating the image tag in the deployment config. The key insight is that Git is the source of truth — rollback is a git operation, not a kubectl operation.

---

*Document version: April 2026*
*Stack: XGBoost, FastAPI, MLflow, GitHub Actions, ArgoCD, Kubernetes, Istio, Prometheus, Grafana, Evidently AI*
*Cloud reference: AWS (EKS, ECR, S3) — patterns are identical on Azure (AKS, ACR, Blob) and GCP (GKE, Artifact Registry, GCS)*
