# app_k8_deployment

## What is this?
This module teaches a real 3-tier healthcare application deployment on Kubernetes: a browser patient intake form, a FastAPI backend, and a MySQL-compatible SQL database. The goal is to show how backend components are deployed, updated, rolled back, protected, and inspected in an enterprise-style cluster while still fitting on the local Windows 11 + WSL2 + Docker Desktop + kind machine used by this repository.

## Why does this exist?
Enterprise platform teams do not deploy "one pod and hope." They separate frontend, backend, and data tiers; expose only the required entry point; keep runtime configuration outside the image; protect credentials; define readiness gates; reserve resources; control disruption; and let Kubernetes controllers reconcile desired state. This module makes those decision points visible in source code, manifests, and lifecycle scripts. Any comment that starts with `ENTERPRISE EMPHASIS:` marks a place where production-grade deployment behavior is being taught.

## ASCII concept diagram

```text
LOCAL KIND CLUSTER: patient-record-system namespace

  Browser on laptop
        |
        | http://localhost:30001
        v
  patient-intake-ui-service
  type: NodePort
        |
        v
  patient-intake-ui Deployment
  nginx + static patient form
  replicas: 2
        |
        | /api/* proxied by nginx
        | Service DNS: patient-record-api-service
        v
  patient-record-api Deployment
  FastAPI + Pydantic + service/repository layers
  replicas: 2
  readiness: checks database reachability
        |
        | Service DNS: patient-record-database-service
        v
  patient-record-database StatefulSet
  MariaDB / MySQL-compatible SQL engine
  replicas: 1
  PersistentVolumeClaim (PVC): patient-record-database-data
    Meaning: the database asks Kubernetes for durable disk storage so patient
    records survive pod restarts. This is not plumbing PVC. In Kubernetes, PVC
    means "PersistentVolumeClaim" - a request for storage.

  Kubernetes controls around the app:
    - Namespace:
        A named area inside the cluster. It groups this app's resources so they
        are separated from other labs or teams.
    - LimitRange:
        Default and maximum CPU/memory rules for pods in the namespace. This
        prevents one small lab app from accidentally asking for too much laptop
        capacity.
    - ResourceQuota:
        A total budget for the namespace. It limits how much CPU, memory, and
        object count this whole app can consume.
    - ServiceAccount:
        The identity a pod uses when talking to the Kubernetes API.
    - RBAC:
        Role-Based Access Control. It answers: "What is this identity allowed
        to do in the cluster?"
    - Secret:
        Kubernetes object for sensitive values such as database passwords. This
        lab uses fake local values; production should use a real secret manager.
    - ConfigMap:
        Kubernetes object for non-sensitive settings such as app name, log
        level, database host, and timeout values.
    - Service:
        A stable network doorway in front of pods. Pods come and go, but the
        Service name remains stable.
    - Ingress:
        The production-style HTTP entry rule for traffic coming from outside
        the cluster, usually backed by an ingress controller or load balancer.
    - Deployment:
        Runs stateless pods such as the FastAPI backend and nginx UI. It handles
        replica count, rolling updates, and rollback history.
    - StatefulSet:
        Runs stateful pods such as databases where stable identity and storage
        matter more than quick replacement.
    - Job:
        Runs a one-time task, such as creating the database schema before the
        backend starts receiving traffic.
    - CronJob:
        Runs a task on a schedule, such as recurring database backup.
    - Probes:
        Kubernetes health checks. Startup checks boot progress, readiness
        decides whether traffic should be sent, and liveness decides whether a
        stuck container should be restarted.
    - NetworkPolicy:
        Firewall-style rules inside the cluster. They describe which pods are
        allowed to talk to which other pods.
    - PodDisruptionBudget:
        A maintenance safety rule. It tells Kubernetes how many pods must stay
        available during voluntary actions such as node drains.
    - HorizontalPodAutoscaler:
        A scaling rule that increases or decreases backend pod count based on
        metrics such as CPU usage.
```

## Plain-English Vocabulary

Kubernetes often compresses big ideas into short names. In this module, read the
terms this way first:

| Term | Plain meaning |
|---|---|
| `PVC` | PersistentVolumeClaim. A pod's request for durable storage. It is how the database asks for disk space that survives pod restarts. |
| `LimitRange` | Default and maximum CPU/memory guardrails for pods in a namespace. |
| `ResourceQuota` | Total CPU/memory/object budget for the whole namespace. |
| `Service` | Stable network doorway to pods. It is not the app itself. |
| `Deployment` | Controller for stateless app pods, rolling updates, and rollback. |
| `StatefulSet` | Controller for stateful pods that need stable identity and storage. |
| `RBAC` | Permission system for Kubernetes identities. |
| `Probe` | Health check Kubernetes uses to decide startup, traffic routing, or restart behavior. |
| `CI` | Continuous Integration. The automated system that checks code, runs tests, builds images, and catches problems before release. |
| `CD` | Continuous Delivery or Continuous Deployment. The automated system that promotes a tested change into an environment such as dev, staging, or production. |
| `GitOps` | A deployment style where Git stores the desired cluster state, and a controller such as Argo CD or Flux continuously makes the cluster match Git. |
| `Immutable tag` | A container image tag that should never be reused for different code. A Git SHA or release version is safer than repeatedly pushing `latest`. |
| `OCI registry` | A container image registry that stores Open Container Initiative images. Examples include ECR, Artifact Registry, ACR, Harbor, and Docker Hub. |
| `Workload identity` | The identity assigned to a running pod or service so the platform can decide what it is allowed to access. |
| `Ingress/Gateway` | Kubernetes-style HTTP entry points for traffic coming from outside the cluster. They usually connect to a real load balancer. |
| `TLS` | Transport Layer Security. The encryption used by HTTPS. |
| `DNS` | Domain Name System. The naming system that turns a name like `patient-intake.example.com` into an IP address. |
| `WAF` | Web Application Firewall. A security layer that filters suspicious HTTP requests before they reach the app. |
| `ALB` | Application Load Balancer in AWS. It receives user traffic and routes HTTP/HTTPS requests to the right backend. |
| `GCLB` | Google Cloud Load Balancing. Google Cloud's managed load-balancer family. |
| `HPA` | HorizontalPodAutoscaler. Kubernetes object that changes pod count based on metrics such as CPU usage. |
| `PDB` | PodDisruptionBudget. Kubernetes object that protects a minimum number of pods during voluntary maintenance. |

## Learning steps

1. Read [application-source/patient-record-api/app/main.py](application-source/patient-record-api/app/main.py) to see the FastAPI entrypoint kept thin through dependency injection.
2. Read [application-source/patient-record-api/app/core/config.py](application-source/patient-record-api/app/core/config.py) to see centralized typed runtime configuration.
3. Read [application-source/patient-record-api/app/models/patient.py](application-source/patient-record-api/app/models/patient.py), [application-source/patient-record-api/app/services/patient_service.py](application-source/patient-record-api/app/services/patient_service.py), and [application-source/patient-record-api/app/repositories/patient_repository.py](application-source/patient-record-api/app/repositories/patient_repository.py) to see API schema, business logic, and SQL separated by responsibility.
4. Read [kubernetes-manifests/04-access-control-rbac.yaml](kubernetes-manifests/04-access-control-rbac.yaml) to understand workload identity and least-privilege API permissions.
5. Read [kubernetes-manifests/06-database-statefulset.yaml](kubernetes-manifests/06-database-statefulset.yaml) to understand why a database uses StatefulSet and PersistentVolumeClaim (PVC) storage instead of a plain Deployment.
6. Read [kubernetes-manifests/07-database-schema-initialization-job.yaml](kubernetes-manifests/07-database-schema-initialization-job.yaml) to see how schema gets into the database before the backend becomes Ready.
7. Read [kubernetes-manifests/08-backend-deployment.yaml](kubernetes-manifests/08-backend-deployment.yaml) to see rollout strategy, probes, resource requests, Downward API, service account usage, security context, and preferred anti-affinity from the database.
8. Read [networking-and-ports-guide.md](networking-and-ports-guide.md) to understand how browser ports, Service ports, target ports, nginx, and FastAPI listeners connect even when the numbers differ.
9. Read [kubernetes-manifests/11-frontend-service.yaml](kubernetes-manifests/11-frontend-service.yaml) and [kubernetes-manifests/15-frontend-ingress.yaml](kubernetes-manifests/15-frontend-ingress.yaml) to compare local NodePort access with enterprise Ingress traffic entry.
10. Read [kubernetes-manifests/12-network-policy.yaml](kubernetes-manifests/12-network-policy.yaml), [kubernetes-manifests/13-pod-disruption-budgets.yaml](kubernetes-manifests/13-pod-disruption-budgets.yaml), and [kubernetes-manifests/14-horizontal-pod-autoscaler.yaml](kubernetes-manifests/14-horizontal-pod-autoscaler.yaml) to see enterprise controls around the application.
11. Read [kubernetes-manifests/16-database-backup-cronjob.yaml](kubernetes-manifests/16-database-backup-cronjob.yaml) to understand why backup is separate from StatefulSet persistence.
12. Read [kubernetes-manifests/17-observability-service-monitor.yaml](kubernetes-manifests/17-observability-service-monitor.yaml) as an optional Prometheus Operator example. Do not apply it unless the `ServiceMonitor` CRD exists.
13. Read [deployment-lifecycle/README.md](deployment-lifecycle/README.md) to see which scripts are first-deploy entry points, update operations, backup/restore operations, and cleanup operations.
14. Run the lifecycle scripts in order from the repository root.

## Commands

Build the application images:

```bash
bash app_k8_deployment/deployment-lifecycle/build-application-images.sh
```

What you should see:

```text
=== Stage 2.0: Build Backend Image ===
Successfully tagged patient-record-api:1.0.0

=== Stage 3.0: Build Frontend Image ===
Successfully tagged patient-intake-ui:1.0.0
```

Load the images into the local kind cluster:

```bash
bash app_k8_deployment/deployment-lifecycle/load-images-into-kind.sh
```

What you should see:

```text
=== Stage 2.0: Load Backend Image ===
Image: "patient-record-api:1.0.0" with ID ... not yet present on node ...

=== Stage 3.0: Load Frontend Image ===
Image: "patient-intake-ui:1.0.0" with ID ... not yet present on node ...
```

Deploy the 3-tier system:

```bash
bash app_k8_deployment/deployment-lifecycle/deploy-patient-record-system.sh
```

What you should see:

```text
=== Stage 3.0: Deploy Database Tier ===
statefulset.apps/patient-record-database created

=== Stage 4.0: Initialize Database Schema ===
job.batch/patient-record-schema-initializer created

=== Stage 5.0: Deploy Backend Tier ===
deployment "patient-record-api" successfully rolled out

=== Stage 6.0: Deploy Frontend Tier ===
deployment "patient-intake-ui" successfully rolled out
```

Verify the full user-facing path:

```bash
bash app_k8_deployment/deployment-lifecycle/verify-patient-record-system.sh
```

What you should see:

```text
=== Stage 3.0: Check Backend Through Frontend Path ===
{"service":"patient-record-api",...}

=== Stage 4.0: Submit Patient Record ===
{"status":"accepted","record":{"patient_id":1,...}}
```

Open the UI:

```bash
curl http://localhost:30001
```

Then open this URL in your browser:

```text
http://localhost:30001
```

Simulate a backend promotion after building and loading a new tag:

```bash
API_IMAGE=patient-record-api:1.0.1 bash app_k8_deployment/deployment-lifecycle/build-application-images.sh
API_IMAGE=patient-record-api:1.0.1 bash app_k8_deployment/deployment-lifecycle/load-images-into-kind.sh
bash app_k8_deployment/deployment-lifecycle/simulate-rolling-update.sh 1.0.1
```

What you should see:

```text
=== Stage 3.0: Watch Rollout ===
deployment "patient-record-api" successfully rolled out

=== Stage 4.0: Inspect Revision History ===
REVISION  CHANGE-CAUSE
```

Roll back the backend:

```bash
bash app_k8_deployment/deployment-lifecycle/rollback-patient-record-api.sh
```

Observe the system like an operator:

```bash
bash app_k8_deployment/deployment-lifecycle/observe-patient-record-system.sh
```

What you should see:

```text
=== Stage 1.0: Workload Snapshot ===
pod, service, endpoint, ingress, pdb, hpa, and cronjob state

=== Stage 3.0: Metrics ===
kubectl top output, or a clear metrics-server explanation
```

Run a database backup immediately:

```bash
bash app_k8_deployment/deployment-lifecycle/run-database-backup-now.sh
```

Restore from a backup file printed by the backup logs:

```bash
bash app_k8_deployment/deployment-lifecycle/restore-database-backup.sh /backups/patient-record-db-YYYYMMDD-HHMMSS.sql.gz
```

Rotate the local database password and restart backend pods:

```bash
NEW_DATABASE_PASSWORD='new-local-password' bash app_k8_deployment/deployment-lifecycle/rotate-database-password.sh
```

Rebuild and repush a same-tag image for local learning:

```bash
bash app_k8_deployment/deployment-lifecycle/repush-application-image.sh api 1.0.0
bash app_k8_deployment/deployment-lifecycle/repush-application-image.sh ui 1.0.0
```

Clean up the application namespace:

```bash
bash app_k8_deployment/deployment-lifecycle/cleanup-patient-record-system.sh
```

## Enterprise translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Build images on the learner machine | CI builds from a clean commit | CI gives repeatability, audit history, scanning, signing, and promotion gates. |
| `kind load docker-image` | Push immutable tags to ECR, Artifact Registry, ACR, Harbor, or another OCI registry | Real clusters pull images from registries with auth and policy controls. |
| `patient-intake-ui:1.0.0` and `patient-record-api:1.0.0` local tags | Immutable tags such as Git SHA or release version | Mutable tags hide what is actually running and make rollback harder. |
| NodePort `30001` | Ingress/Gateway with ALB, GCLB, Azure Application Gateway, TLS, DNS, and WAF | NodePort is a local access shortcut. Enterprise systems usually use a managed entry point that handles HTTPS, domains, firewall rules, and routing. |
| Ingress host `patient-intake.local.example` | Public/private DNS with managed load balancer, TLS certificates, WAF, and routing rules | Ingress describes how outside HTTP traffic should enter the cluster. The ingress controller or gateway provides the real load balancer behavior. |
| Explicit ServiceAccounts and RBAC | Workload identity, cloud IAM binding, admission policy, and least-privilege reviews | Pods should have a specific identity and only the permissions they need. They should not inherit broad default permissions or unnecessary API tokens. |
| FastAPI backend as Deployment | Same stateless Deployment pattern on EKS, GKE, AKS, or OpenShift | Deployments provide rolling update, rollback, scaling, and ReplicaSet history. |
| MariaDB StatefulSet + PVC | Managed database or operator-managed database cluster | Production databases need backups, encryption, HA, upgrades, failover, and restore drills. |
| Schema initialization Job | CI/CD-controlled migration stage with Flyway, Liquibase, Alembic, or database change-management tooling | CI/CD means the release pipeline controls when schema changes run. Schema is a release artifact, not something hidden inside a request path. |
| Native Kubernetes Secret with fake values | External Secrets Operator plus cloud secret manager or Vault | Base64 is not a secure source of truth for real credentials. |
| Password rotation script | Secret manager rotation workflow plus database credential rotation and automated rollout | Updating a Secret alone does not change the real database password, and env-var consumers need restart. |
| ConfigMap for non-sensitive runtime settings | Helm/Kustomize/GitOps overlays per environment | Environment-specific values live outside the image, so the same image can move from dev to staging to production with different configuration. |
| Readiness checks database reachability | Readiness gates load balancer endpoints and rollout progress | Broken pods should not receive user traffic. |
| Readiness checks schema existence | Migration gates or startup checks block traffic until required tables exist | A live database without the right schema still cannot serve the application. |
| Liveness checks only process health | Same separation in production | A database outage should not cause every app pod to restart endlessly. |
| NetworkPolicy declares frontend -> backend -> database | Enforced zero-trust networking through Calico, Cilium, cloud CNI, or mesh policy | Pods should only communicate along intentional architecture paths. |
| HPA scales backend on CPU | Scale on CPU, memory, request rate, queue depth, or custom metrics | CPU is easy to teach; real bottlenecks depend on workload behavior. |
| PDB keeps at least one API/UI pod available | Required for workloads that must survive node drains and upgrades | PDBs help maintenance respect application availability. |
| Backup CronJob writes to a local PVC | Managed snapshots or object-storage backups with retention, encryption, and restore testing | StatefulSet persistence is not the same as disaster recovery. |
| Optional ServiceMonitor manifest | Prometheus Operator scrape discovery plus dashboards and alerts | Metrics, logs, and traces are first-class production controls, not afterthoughts. |

## What to check if something goes wrong

1. Pods show `ImagePullBackOff`:
Run `docker image ls`, then `bash app_k8_deployment/deployment-lifecycle/load-images-into-kind.sh`. kind cannot pull local laptop images unless they are loaded into the cluster nodes.

2. API pods stay `Pending`:
Run `kubectl describe pod -n patient-record-system -l app=patient-record-api`. The backend prefers to avoid the database node through pod anti-affinity, but the rule is soft so the lab can still run on small clusters.

3. API pods start but are not Ready:
Run `kubectl logs -n patient-record-system deployment/patient-record-api`, `kubectl logs -n patient-record-system job/patient-record-schema-initializer`, and `kubectl get endpoints patient-record-database-service -n patient-record-system`. Readiness depends on database reachability and the `patient_records` table existing.

4. Browser cannot open `http://localhost:30001`:
Check that the kind cluster was created from `setup/01-cluster-setup/kind-cluster-config.yaml`, which maps host port `30001` into the control plane node. Also run `kubectl get svc patient-intake-ui-service -n patient-record-system`.

5. The form loads but submission fails:
Run `kubectl logs -n patient-record-system deployment/patient-intake-ui` and `kubectl logs -n patient-record-system deployment/patient-record-api`. The nginx UI proxies `/api/*` to `patient-record-api-service:8080`.

6. NetworkPolicy seems to do nothing:
That can be normal in kind. NetworkPolicy objects require a CNI that enforces them, such as Calico or Cilium. The YAML still teaches the enterprise intent.

7. HPA shows `<unknown>`:
metrics-server is missing or unhealthy. The HPA object is valid, but Kubernetes needs metrics before it can calculate CPU utilization.

8. Rollback fixes the API but database state stays changed:
That is expected. Deployment rollback restores pod templates for stateless code. Database schema and data rollback require backups, migrations, and a separate operational process.

9. Ingress exists but the hostname does not work:
That is expected until an ingress controller is installed and DNS or `/etc/hosts` points the hostname at the controller entry point. NodePort remains the local access path in this lab.

10. Secret was updated but API pods still fail authentication:
Environment variables are read at container startup. Run `kubectl rollout restart deployment/patient-record-api -n patient-record-system`, or use the rotation script so the database password, Secret, and pod restart happen together.

11. Backup exists but you have not restored it:
Treat that as an incomplete data-protection story. Run `run-database-backup-now.sh`, then use `restore-database-backup.sh` with the printed backup path in a local restore drill.
