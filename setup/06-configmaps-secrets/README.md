# 06-configmaps-secrets

## What is this?
This module teaches ConfigMaps and Secrets, the Kubernetes primitives that separate application code from environment-specific settings and sensitive values. In the previous modules, Deployments created pods and Services gave those pods stable network identities. This module answers the next production question: how does the same application image behave differently in dev, staging, and prod without rebuilding the image?

## Why does this exist?
Enterprise platform teams want one immutable container image promoted across environments, while configuration changes per environment. A gateway might call `risk-profile-api-clusterip` in this local lab, a staging URL in pre-production, and a different internal DNS name in production. ConfigMaps carry non-sensitive settings such as service URLs, log levels, feature flags, and config files. Secrets carry sensitive values such as API tokens, passwords, and private credentials.

## ASCII concept diagram

```text
KUBERNETES CLUSTER

  04-deployments/                 05-services/                    06-configmaps-secrets/
  ----------------                 ------------                    ----------------------

  Deployment                       Service                         ConfigMap
  owns pod lifecycle               owns stable DNS                 owns non-sensitive config

  inference-gateway pods   --->    risk-profile-api-clusterip  <--- RISK_PROFILE_API_BASE_URL
       |                               |
       |                               v
       |                         backend pods
       |
       +---- reads env vars and mounted files from:
             - ConfigMap: log level, app environment, backend Service URL
             - Secret: fake API token and fake database credentials

  Key lesson:
    Deployments keep pods alive.
    Services make pods discoverable.
    ConfigMaps and Secrets make pods configurable without rebuilding images.
```

## Learning steps

1. Read [app-configmap.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/06-configmaps-secrets/app-configmap.yaml) to see non-sensitive runtime settings, including the backend Service DNS name introduced in `05-services/`.
2. Read [app-secret.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/06-configmaps-secrets/app-secret.yaml) to see fake sensitive values and why base64 is encoding, not encryption.
3. Read [pod-using-config.yaml](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/06-configmaps-secrets/pod-using-config.yaml) to see the two main consumption patterns: environment variables and mounted files.
4. Run [commands.sh](/mnt/d/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/06-configmaps-secrets/commands.sh) to apply the objects, wait for the pod, inspect environment variables, inspect mounted files, and learn the debugging flow.
5. Compare this module with `04-deployments/` and `05-services/`: Deployments decide how many pods exist, Services decide how traffic finds them, and ConfigMaps/Secrets decide what runtime values the pods receive.
6. Move next to `07-rbac/`, because once Secrets exist, the next enterprise concern is controlling who can read them.

## Commands

Run the walkthrough from the repository root in WSL2:

```bash
bash setup/06-configmaps-secrets/commands.sh
```

What you should see on the happy path:

```text
=== Stage 1.0: Preflight Checks ===
applications namespace exists
kubectl can reach the cluster

=== Stage 2.0: Apply ConfigMap and Secret ===
configmap/inference-gateway-runtime-config created
secret/inference-gateway-runtime-secrets created

=== Stage 3.0: Deploy Consumer Pod ===
pod/config-demo created
pod/config-demo condition met

=== Stage 4.0: Verify Environment Variables ===
APP_ENV=development
LOG_LEVEL=info
RISK_PROFILE_API_BASE_URL=http://risk-profile-api-clusterip/profile/rules
API_TOKEN is present but not printed

=== Stage 5.0: Verify Mounted Files ===
gateway-runtime.yaml
db-username
db-password
```

Useful manual commands:

```bash
kubectl get configmap inference-gateway-runtime-config -n applications
kubectl describe configmap inference-gateway-runtime-config -n applications
kubectl get secret inference-gateway-runtime-secrets -n applications
kubectl describe secret inference-gateway-runtime-secrets -n applications
kubectl exec config-demo -n applications -- env | grep -E 'APP_ENV|LOG_LEVEL|RISK_PROFILE'
kubectl exec config-demo -n applications -- cat /etc/gateway/config/gateway-runtime.yaml
kubectl exec config-demo -n applications -- ls -l /etc/gateway/secrets
kubectl delete pod config-demo -n applications
```

If you still want to use the older entrypoint, it now delegates to the canonical module runner:

```bash
bash setup/06-configmaps-secrets/apply-config.sh
```

## Enterprise translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Store non-sensitive settings in a native ConfigMap | Same primitive on EKS, GKE, and AKS, usually managed by GitOps | ConfigMaps are safe to version in Git because they should not contain credentials. |
| Store fake credentials in a native Secret | External Secrets Operator with AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, or HashiCorp Vault | Mature teams avoid committing real Secret manifests because base64 is not encryption. |
| Manually apply YAML with `kubectl apply` | Argo CD or Flux reconciles manifests from Git | Production teams need review, audit history, drift detection, and repeatable promotion. |
| Inject config as environment variables | Common for static values that only change on pod restart | Environment variables are simple, but updates require new pods. |
| Mount config and secrets as files | Common for certificates, config files, and rotated credentials | Mounted files can update while the pod is running, although the application must reread them. |
| Use a local Service DNS name from `05-services/` | Internal service discovery, service mesh, or platform DNS on EKS/GKE/AKS | The idea is the same: callers depend on stable names, not pod IPs. |

## What to check if something goes wrong

1. Pod is stuck in `CreateContainerConfigError`:
Run `kubectl describe pod config-demo -n applications`. This usually means the referenced ConfigMap, Secret, or key does not exist. Apply `app-configmap.yaml` and `app-secret.yaml` before the pod.

2. Environment variable is missing:
Check the key name in `pod-using-config.yaml` and the key under `data:` in the ConfigMap or Secret. Kubernetes key references are exact; `APP_ENV` and `APP_ENVIRONMENT` are different names.

3. Mounted file is missing:
Run `kubectl describe pod config-demo -n applications` and inspect the volume section. If `items.key` does not match a ConfigMap or Secret key, the pod will not mount that file correctly.

4. Secret value looks readable in Git:
That is expected in this learning lab because the values are fake. Base64 only protects YAML formatting, not confidentiality. In enterprise, real secret source of truth belongs in a vault or encrypted GitOps workflow.

5. ConfigMap changed but the environment variable did not:
That is expected. Environment variables are captured when the container starts. Delete or restart the pod to pick up env var changes. Mounted ConfigMap files can update without a pod restart, but the application must reread the file.

6. The backend Service URL does not respond:
This module only demonstrates injecting the URL. To prove Service routing, run `bash setup/05-services/commands.sh` first and verify `risk-profile-api-clusterip` has endpoints.

## Happy path: how to read the output

1. ConfigMap and Secret are created:
The cluster now has separate API objects for non-sensitive and sensitive runtime data.

2. `config-demo` becomes Ready:
The pod spec successfully resolved every required key and mounted every required file.

3. Environment variables show the backend Service URL:
This connects the lesson back to `05-services/`: application config should point at stable Service DNS, not pod IPs.

4. Secret checks avoid printing sensitive values:
That is intentional production behavior. Operators should verify that secret values exist without leaking them into terminal logs.

5. Mounted files appear under `/etc/gateway/config` and `/etc/gateway/secrets`:
This is the file-based pattern used for larger config files, certificates, and credentials that may rotate.
