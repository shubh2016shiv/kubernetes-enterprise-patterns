"""
Module: health_checks
Purpose: Separate liveness and readiness logic for Kubernetes probes.
Inputs:  DatabaseConnectionFactory for dependency checks.
Outputs: Small dictionaries returned by FastAPI health endpoints.
Tradeoffs: Liveness is intentionally local-process-only while readiness checks
the database dependency and required schema. This difference is one of the most
important Kubernetes production lessons in the application.
"""

# Standard library: monotonic timing helps report process uptime.
from time import monotonic
from typing import Any

# Local application: readiness reaches the database through the connection layer.
from app.core.config import Settings
from app.database.connection import DatabaseConnectionFactory


class HealthCheckService:
    """
    Purpose: Provide liveness and readiness payloads for Kubernetes.
    Parameters: connection_factory checks database reachability; settings adds
    deployment identity.
    Return value: Health dictionaries consumed by API routes.
    Failure behavior: Readiness reports unhealthy when the database cannot be
    reached or the schema initialization Job has not created the table; liveness
    stays healthy if the process itself is alive.
    Enterprise equivalent: Mature platforms wire these checks into Services,
    load balancers, alerts, and rollout gates.
    """

    def __init__(
        self,
        connection_factory: DatabaseConnectionFactory,
        settings: Settings,
    ) -> None:
        self._connection_factory = connection_factory
        self._settings = settings
        self._started_at = monotonic()

    def get_liveness(self) -> dict[str, Any]:
        """
        Purpose: Answer whether the Python process should stay running.
        Parameters: None.
        Return value: Healthy process metadata.
        Failure behavior: Does not check dependencies, avoiding restart loops
        when only the database is temporarily down.
        Enterprise equivalent: Liveness should prove the process is not wedged,
        not that every dependency is healthy.
        """

        return {
            "status": "alive",
            "service": self._settings.app_name,
            "version": self._settings.api_version,
            "pod_name": self._settings.pod_name,
            "uptime_seconds": round(monotonic() - self._started_at, 2),
        }

    def get_readiness(self) -> dict[str, Any]:
        """
        Purpose: Answer whether this pod should receive Service traffic.
        Parameters: None.
        Return value: Dependency-aware readiness metadata.
        Failure behavior: Raises database exceptions when the dependency is not
        reachable or the schema is absent; the route converts that into HTTP 503.
        Enterprise equivalent: Readiness is the traffic gate for rolling updates,
        autoscaling, and load balancer endpoint registration.
        """

        with self._connection_factory.open_connection() as connection:
            with connection.cursor() as cursor:
                # ENTERPRISE EMPHASIS: Readiness must prove more than "the TCP
                # port accepts connections." If the schema migration Job has not
                # created the table yet, accepting patient-write traffic would
                # produce user-facing 500 errors during rollout.
                cursor.execute("SELECT COUNT(*) AS ready FROM patient_records LIMIT 1;")
                cursor.fetchone()

        return {
            "status": "ready",
            "service": self._settings.app_name,
            "version": self._settings.api_version,
            "database": "reachable",
            "schema": "patient_records table exists",
            "pod_name": self._settings.pod_name,
            "node_name": self._settings.node_name,
        }
