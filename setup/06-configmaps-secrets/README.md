# 06-configmaps-secrets

## What are ConfigMaps and Secrets?
ConfigMaps and Secrets are Kubernetes objects used to store configuration data separately from application code. 
- **ConfigMaps** store non-sensitive data (like port numbers, debug flags, or entire configuration files like `nginx.conf`).
- **Secrets** store sensitive data (like passwords, API keys, and TLS certificates).

## Why do they exist?
In an enterprise environment, following the "12-Factor App" methodology is mandatory. An application's code must remain identical across all environments (Dev, Staging, Prod). The only thing that changes is the configuration injected into it. ConfigMaps and Secrets allow you to inject environment-specific settings into the same Docker container image without rebuilding it.

## Architecture

```text
┌────────────────────────────────────────────────────────────┐
│                    KUBERNETES CLUSTER                      │
│                                                            │
│  ┌─────────────────┐             ┌─────────────────┐       │
│  │   ConfigMap     │             │     Secret      │       │
│  │ (Non-sensitive) │             │  (Passwords)    │       │
│  │  - APP_ENV      │             │  - DB_PASS      │       │
│  │  - nginx.conf   │             │  - API_KEY      │       │
│  └───────┬─────────┘             └─────────┬───────┘       │
│          │                                 │               │
│          │        Injected at Pod          │               │
│          │        Startup time             │               │
│          ▼                                 ▼               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                        POD                           │  │
│  │                                                      │  │
│  │   [Environment Variables]                            │  │
│  │   $APP_ENV = dev                                     │  │
│  │   $DB_PASS = secret123                               │  │
│  │                                                      │  │
│  │   [Mounted Volume Files]                             │  │
│  │   /etc/nginx/nginx.conf  ◄─── (From ConfigMap)       │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

## Learning Steps

1. **ConfigMap Definition**: Review `app-configmap.yaml`. Notice how it holds both simple key-value pairs AND entire file contents (like `nginx.conf`).
2. **Secret Definition**: Review `app-secret.yaml`. Notice that values are base64-encoded (not encrypted!).
3. **Pod Consumption**: Review `pod-using-config.yaml`. This is the most important file. It shows how to inject these objects as environment variables and as mounted files.
4. **Apply and Inspect**: Run the `apply-config.sh` script to test the injection live.

## Commands

### 1. Apply and Inspect Configuration
```bash
bash setup/06-configmaps-secrets/apply-config.sh
```

**What you should see**:
```
=== Stage 1: Apply ConfigMap and Secret ===
configmap/nginx-app-config created
secret/app-credentials created

=== Stage 3: Exec and Verify Environment Variables ===
APP_ENV=development
LOG_LEVEL=info
DB_USERNAME=admin
DB_PASSWORD=super_secret_password_here
...
```

## Enterprise Translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| Manual Secret YAMLs | External Secrets Operator / HashiCorp Vault | Enterprises **never** store Secrets in git (even base64 encoded). Secrets are stored in cloud vaults (AWS Secrets Manager) and synced into the cluster dynamically. |
| Restart pods manually to pick up config changes | Reloader / GitOps Sync | If you change a ConfigMap, pods don't restart automatically. Enterprises use tools like "Reloader" to restart pods when their ConfigMaps change. |
| Plain base64 encoding | Encrypted at Rest (etcd encryption) / SealedSecrets | By default, Kubernetes stores secrets in plaintext in its internal database (etcd). Enterprises encrypt the etcd drive or use KMS plugins. |

## What to Check If Something Goes Wrong

1. **Pod is stuck in `ContainerCreating`**: Run `kubectl describe pod config-demo -n applications`. It will likely say "configmap not found" or "secret not found". You must apply the ConfigMap and Secret *before* the Pod that uses them.
2. **Mounted file is empty**: Check the `subPath` in the volume mount. If `subPath` is wrong, the file won't appear.
3. **Secret value is wrong**: Did you base64 encode it with a newline character? Always use `echo -n "mysecret" | base64` to avoid the hidden newline `\n` breaking your app.
