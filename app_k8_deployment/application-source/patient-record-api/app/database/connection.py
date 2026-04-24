"""
Module: connection
Purpose: Own MySQL-compatible database connection creation for the API.
Inputs:  Typed Settings values injected from Kubernetes configuration.
Outputs: Short-lived PyMySQL connections used by repositories.
Tradeoffs: This lab opens short-lived connections for clarity. A larger service
would use connection pooling and explicit retry/backoff tuned to SLOs.
"""

# Standard library: context managers provide safe cleanup around connections.
from contextlib import contextmanager
from typing import Iterator

# Third-party: PyMySQL is a small pure-Python MySQL/MariaDB client.
# Enterprise: teams may standardize on SQLAlchemy, async drivers, or an internal
# database access library, but the repository boundary remains the same.
import pymysql
from pymysql.connections import Connection
from pymysql.cursors import DictCursor

# Local application: Settings is the single source of runtime configuration.
from app.core.config import Settings


class DatabaseConnectionFactory:
    """
    Purpose: Build database connections from validated settings.
    Parameters: settings contains host, port, schema, user, and password.
    Return value: Context-managed PyMySQL connections.
    Failure behavior: Connection errors propagate to readiness checks and API
    calls so Kubernetes and clients see an honest failure.
    Enterprise equivalent: This class is where production teams often add TLS,
    IAM database authentication, connection pools, and query tracing.
    """

    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    @contextmanager
    def open_connection(self) -> Iterator[Connection]:
        """
        Purpose: Open and close a database connection around one unit of work.
        Parameters: None; connection details come from Settings.
        Return value: Yields an active PyMySQL connection.
        Failure behavior: Raises PyMySQL exceptions on network, auth, or SQL
        errors; callers decide whether that means readiness failure or 500.
        Enterprise equivalent: Use the same boundary for pooled connections.
        """

        connection = pymysql.connect(
            host=self._settings.database_host,
            port=self._settings.database_port,
            user=self._settings.database_user,
            password=self._settings.database_password,
            database=self._settings.database_name,
            connect_timeout=self._settings.database_connect_timeout_seconds,
            cursorclass=DictCursor,
            autocommit=False,
            charset="utf8mb4",
        )
        try:
            yield connection
        finally:
            connection.close()
