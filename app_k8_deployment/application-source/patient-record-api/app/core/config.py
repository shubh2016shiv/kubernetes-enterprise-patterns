"""
Module: config
Purpose: Centralize runtime configuration for the patient record API.
Inputs:  Environment variables injected by Kubernetes ConfigMaps and Secrets.
Outputs: A typed Settings object used by API, database, and health modules.
Tradeoffs: This lab reads settings directly from environment variables. In a
production enterprise platform, the same pattern usually pulls secret material
from External Secrets Operator, AWS Secrets Manager, GCP Secret Manager, Azure
Key Vault, or HashiCorp Vault before exposing values to the pod.
"""

# Standard library: cache the settings object so it is created once per process.
from functools import lru_cache

# Third-party: Pydantic validates environment-driven configuration at startup.
# Enterprise: failing fast on bad config prevents broken pods from quietly
# accepting traffic and turning into harder-to-debug runtime incidents.
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """
    Purpose: Represent all runtime settings required by the API.
    Parameters: Values are loaded from environment variables by Pydantic.
    Return value: A validated configuration object.
    Failure behavior: Missing or malformed required values raise validation
    errors during application startup.
    Enterprise equivalent: The same object maps cleanly to Helm values, Kustomize
    patches, GitOps environment overlays, or platform-provided env vars.
    """

    # CONFIGURATION EXPLANATION `env_file=None` means this API reads configuration only from the container
    # environment that Kubernetes injects from ConfigMaps, Secrets, and pod metadata. That keeps local files from
    # silently overriding cluster configuration during production-like runs.
    model_config = SettingsConfigDict(env_file=None, extra="ignore")

    # CONFIGURATION EXPLANATION `APP_NAME` is the human-readable service name returned by metadata and health
    # endpoints. Operators use this value in logs and smoke tests to confirm they are talking to the expected API.
    app_name: str = Field(default="patient-record-api", alias="APP_NAME")
    # CONFIGURATION EXPLANATION `APP_ENVIRONMENT` identifies where the same image is running. The image stays the
    # same, while Kubernetes configuration says whether this is local-kind, staging, or production.
    app_environment: str = Field(default="local-kind", alias="APP_ENVIRONMENT")
    # CONFIGURATION EXPLANATION `LOG_LEVEL` controls how much detail the API writes to logs. Production teams
    # tune this for observability and cost: too little hides incidents, too much creates noisy expensive logs.
    log_level: str = Field(default="INFO", alias="LOG_LEVEL")
    # CONFIGURATION EXPLANATION `API_VERSION` exposes the running release version. This helps prove which rollout
    # is serving traffic when multiple ReplicaSets exist during an update or rollback.
    api_version: str = Field(default="1.0.0", alias="API_VERSION")

    # CONFIGURATION EXPLANATION `DATABASE_HOST` is expected to be the Kubernetes Service DNS name, not a pod IP.
    # Pods are replaceable; the Service name is the stable address the API should use for database traffic.
    database_host: str = Field(alias="DATABASE_HOST")
    # CONFIGURATION EXPLANATION `DATABASE_PORT` must match the database Service port and the MariaDB container
    # listener. If this is wrong, the API can start but readiness will fail because it cannot connect to SQL.
    database_port: int = Field(default=3306, alias="DATABASE_PORT")
    # CONFIGURATION EXPLANATION `DATABASE_NAME` selects the schema where patient records are stored. It must match
    # the Secret and schema initialization Job so the API reads and writes the same database that was initialized.
    database_name: str = Field(alias="DATABASE_NAME")
    # CONFIGURATION EXPLANATION `DATABASE_USER` is the application database account. Production apps use a
    # limited user instead of the root account so a compromised API has a smaller database blast radius.
    database_user: str = Field(alias="DATABASE_USER")
    # CONFIGURATION EXPLANATION `DATABASE_PASSWORD` comes from a Kubernetes Secret. A Secret is a Kubernetes
    # object for sensitive values; the code accepts it from the environment and never logs the value.
    database_password: str = Field(alias="DATABASE_PASSWORD")
    # CONFIGURATION EXPLANATION The database connect timeout bounds how long one request or readiness check can
    # wait for SQL. Without a timeout, a broken database dependency can tie up API workers and slow recovery.
    database_connect_timeout_seconds: int = Field(
        default=5,
        alias="DATABASE_CONNECT_TIMEOUT_SECONDS",
    )

    # CONFIGURATION EXPLANATION These pod metadata fields come from the Kubernetes Downward API, which exposes
    # selected pod facts as environment variables. They make responses and logs traceable to the exact pod and
    # node that handled a request.
    pod_name: str = Field(default="unknown-pod", alias="POD_NAME")
    pod_namespace: str = Field(default="unknown-namespace", alias="POD_NAMESPACE")
    node_name: str = Field(default="unknown-node", alias="NODE_NAME")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """
    Purpose: Provide one shared Settings instance for dependency injection.
    Parameters: None.
    Return value: A validated Settings object.
    Failure behavior: Raises a Pydantic validation error if required config is
    missing; Kubernetes will restart the pod and surface the failure in Events.
    Enterprise equivalent: Central config construction keeps service code free
    from ad hoc `os.getenv` calls and makes runtime behavior auditable.
    """

    return Settings()
