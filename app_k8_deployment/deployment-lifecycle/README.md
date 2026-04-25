# Deployment Lifecycle Scripts

## What is this?

This folder contains the operational scripts for building, loading, deploying, verifying, updating, observing, backing up, restoring, rotating credentials, and cleaning up the patient record system. These scripts are the local-learning equivalent of stages you would normally see in an enterprise CI/CD pipeline. CI/CD means "Continuous Integration and Continuous Delivery/Deployment": the automated release machinery that tests, builds, deploys, and verifies software changes.

## Why does this exist?

If someone gives you many shell scripts, you should not guess the order from file names alone. A real platform team provides an orchestrated pipeline, runbook, Makefile, task runner, or README that explains which scripts are entry points, which scripts are optional operations, and which scripts are dangerous cleanup or restore actions. This folder keeps that intent visible so the learner understands not only which script to run, but why that step exists in a release flow.

## ASCII concept diagram

```text
LOCAL LEARNING FLOW

  Source code changed
        |
        v
  build-application-images_1.sh
        |
        v
  load-images-into-kind_2.sh
        |
        v
  deploy-patient-record-system_3.sh
        |
        v
  verify-patient-record-system_4.sh
        |
        v
  observe-patient-record-system_5.sh


ENTERPRISE CI/CD TRANSLATION

  Git commit / pull request
        |
        v
  CI: test, lint, scan, build image, push immutable tag
      Meaning: automated checks package a trusted container image.
        |
        v
  CD: render manifests, apply with Argo CD / Flux / pipeline deploy job
      Meaning: automated deployment applies the desired Kubernetes state.
        |
        v
  Verification: rollout status, smoke tests, metrics, logs, alerts
      Meaning: the pipeline proves the release is alive before trusting it.
        |
        v
  Operations: rollback, backup, restore, credential rotation
      Meaning: controlled procedures exist for failures and maintenance.
```

## Learning steps

1. Run [build-application-images_1.sh](build-application-images_1.sh) to package the FastAPI backend and nginx UI as container images.
2. Run [load-images-into-kind_2.sh](load-images-into-kind_2.sh) so the local kind cluster can see images built on the laptop.
3. Run [deploy-patient-record-system_3.sh](deploy-patient-record-system_3.sh) to apply namespace, config, database, backend, frontend, and platform controls.
4. Run [verify-patient-record-system_4.sh](verify-patient-record-system_4.sh) to prove the browser-to-nginx-to-FastAPI-to-database path works.
5. Run [observe-patient-record-system_5.sh](observe-patient-record-system_5.sh) when you want to inspect pods, logs, Services, rollouts, and events.
6. Use update and operations scripts only after the base system exists.

## Plain-English Vocabulary

| Term | Plain meaning |
|---|---|
| `CI` | Continuous Integration. The automated system that checks code, runs tests, builds container images, and catches problems early. |
| `CD` | Continuous Delivery or Continuous Deployment. The automated system that releases tested changes into an environment. |
| `CI/CD pipeline` | The ordered release workflow. It is the enterprise version of running these scripts in the correct sequence. |
| `Runbook` | Written operational instructions for humans. It explains what to run, when to run it, and what to check. |
| `Entrypoint script` | A script meant to be started directly by a human or pipeline. Helper scripts may exist, but entrypoints are the safe starting points. |
| `Immutable tag` | A container image tag that should point to one exact build forever. Reusing the same tag for different code makes rollback confusing. |
| `Registry` | A server that stores container images so Kubernetes nodes can pull them. Local kind uses `kind load docker-image` instead. |
| `Smoke test` | A small post-deploy test that proves the most important path works. Here, it means the UI path can reach FastAPI and write to the database. |
| `Rollout` | Kubernetes replacing old pods with new pods from an updated Deployment. |
| `Rollback` | Kubernetes returning a Deployment to a previous working pod template. |
| `Drift` | A mismatch between what Git or the pipeline says should exist and what is actually running in the cluster. |
| `Promotion` | Moving a tested build to the next environment, such as local to dev, dev to staging, or staging to production. |

## Commands

Run these from the repository root.

### First deployment

```bash
bash app_k8_deployment/deployment-lifecycle/build-application-images_1.sh
bash app_k8_deployment/deployment-lifecycle/load-images-into-kind_2.sh
bash app_k8_deployment/deployment-lifecycle/deploy-patient-record-system_3.sh
bash app_k8_deployment/deployment-lifecycle/verify-patient-record-system_4.sh
```

What you should see:

```text
Successfully tagged patient-record-api:1.0.0
Successfully tagged patient-intake-ui:1.0.0
Image: "patient-record-api:1.0.0" with ID ... loaded into kind
deployment "patient-record-api" successfully rolled out
deployment "patient-intake-ui" successfully rolled out
HTTP smoke test succeeds through http://localhost:30001
```

### Observe the running system

```bash
bash app_k8_deployment/deployment-lifecycle/observe-patient-record-system.sh
```

What you should see:

```text
Pods, Services, rollout status, recent Events, and backend/UI logs.
```

### Simulate a backend rolling update

```bash
API_IMAGE=patient-record-api:1.0.1 bash app_k8_deployment/deployment-lifecycle/build-application-images.sh
API_IMAGE=patient-record-api:1.0.1 bash app_k8_deployment/deployment-lifecycle/load-images-into-kind.sh
bash app_k8_deployment/deployment-lifecycle/simulate-rolling-update.sh 1.0.1
```

What you should see:

```text
Kubernetes creates a new ReplicaSet, waits for new backend pods to become Ready,
then removes old pods without dropping below the allowed availability.
```

### Roll back the backend

```bash
bash app_k8_deployment/deployment-lifecycle/rollback-patient-record-api.sh
```

What you should see:

```text
Kubernetes reverts the patient-record-api Deployment to the previous ReplicaSet.
```

### Backup, restore, and credential operations

```bash
bash app_k8_deployment/deployment-lifecycle/run-database-backup-now.sh
bash app_k8_deployment/deployment-lifecycle/restore-database-backup.sh /backups/patient-record-db-YYYYMMDD-HHMMSS.sql.gz
NEW_DATABASE_PASSWORD='new-local-password' bash app_k8_deployment/deployment-lifecycle/rotate-database-password.sh
```

What you should see:

```text
Backup creates a timestamped SQL dump.
Restore loads a selected dump back into the database.
Password rotation updates the database credential path and restarts env-var consumers.
```

### Clean up the lab

```bash
bash app_k8_deployment/deployment-lifecycle/cleanup-patient-record-system.sh
```

What you should see:

```text
The patient-record-system namespace and its lab resources are removed.
```

## Script Order And Intent

| Script | When to run it | Enterprise equivalent |
|---|---|---|
| `build-application-images.sh` | First, and again after app source changes | CI image build stage. CI means automated checks and packaging after a code change. |
| `load-images-into-kind.sh` | After local image build, before local deployment | Registry push stage. In enterprise, the cluster pulls images from a registry instead of the developer laptop. |
| `deploy-patient-record-system.sh` | After images are available to the cluster | CD deploy stage or GitOps sync. This means an automated system applies the desired Kubernetes manifests. |
| `verify-patient-record-system.sh` | After deployment or update | Smoke test / post-deploy validation. This proves the critical user path works after release. |
| `observe-patient-record-system.sh` | Any time after deployment | Operator runbook, dashboards, logs, Events. This is how humans inspect what the platform is doing. |
| `simulate-rolling-update.sh` | After a new backend image exists | Progressive delivery / rolling deployment. Kubernetes replaces pods gradually instead of all at once. |
| `rollback-patient-record-api.sh` | When the new backend revision is bad | Automated or manual rollback stage. The platform returns to the previous working pod template. |
| `run-database-backup-now.sh` | Before risky operations or for backup drills | On-demand backup job. A deliberate backup before a change or restore practice. |
| `restore-database-backup.sh` | Only when intentionally restoring data | Controlled restore procedure with approval. Restores change data and should be treated carefully. |
| `rotate-database-password.sh` | When practicing credential rotation | Secret manager rotation workflow. Credentials change, Kubernetes Secret changes, and pods restart to read new env vars. |
| `repush-application-image.sh` | When rebuilding and reloading one image quickly | Re-run one image build job and redeploy one workload. This is a local shortcut for fast learning. |
| `cleanup-patient-record-system.sh` | At the end of the lab | Environment teardown |

## Enterprise Translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Manually run scripts in order | CI/CD pipeline runs ordered stages | Pipelines give repeatability, approvals, logs, and audit history. You can prove who released what, when, and from which commit. |
| Build images on the laptop | CI builds images from Git commit | Enterprise images must be reproducible and traceable to source. A clean CI worker avoids "works on my machine" builds. |
| Load images into kind | Push images to ECR, GCR, ACR, Harbor, or another registry | Real clusters pull from registries, not from a developer laptop. |
| Apply manifests through a script | Argo CD, Flux, Helm, Kustomize, or a deploy job applies desired state | GitOps and deployment systems detect drift, meaning differences between Git's desired state and the live cluster. |
| Run smoke verification manually | Pipeline runs smoke tests and gates promotion | Bad releases should stop before reaching users. Promotion means moving a build to the next environment. |
| Run rollback script manually | Pipeline or GitOps rollback restores the previous known-good revision | Rollback must be fast, documented, and auditable. |

## What to check if something goes wrong

1. You are not sure which script to run:
   Start with the "First deployment" command block above. If the system is already running, use `observe-patient-record-system.sh` before changing anything.

2. Pods show `ImagePullBackOff`:
   The kind cluster cannot see local laptop images yet. Run `load-images-into-kind.sh`, then check the Deployment image tag.

3. Deployment does not become Ready:
   Run `observe-patient-record-system.sh`. Check Events, backend logs, readiness probe output, and whether the database Service has endpoints.

4. You are about to restore or clean up:
   Pause and confirm intent. Restore changes data, and cleanup removes the lab namespace.
