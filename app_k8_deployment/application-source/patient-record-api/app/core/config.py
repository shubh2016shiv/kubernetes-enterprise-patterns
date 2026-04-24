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

    model_config = SettingsConfigDict(env_file=None, extra="ignore")

    app_name: str = Field(default="patient-record-api", alias="APP_NAME")
    app_environment: str = Field(default="local-kind", alias="APP_ENVIRONMENT")
    log_level: str = Field(default="INFO", alias="LOG_LEVEL")
    api_version: str = Field(default="1.0.0", alias="API_VERSION")

    database_host: str = Field(alias="DATABASE_HOST")
    database_port: int = Field(default=3306, alias="DATABASE_PORT")
    database_name: str = Field(alias="DATABASE_NAME")
    database_user: str = Field(alias="DATABASE_USER")
    database_password: str = Field(alias="DATABASE_PASSWORD")
    database_connect_timeout_seconds: int = Field(
        default=5,
        alias="DATABASE_CONNECT_TIMEOUT_SECONDS",
    )

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
