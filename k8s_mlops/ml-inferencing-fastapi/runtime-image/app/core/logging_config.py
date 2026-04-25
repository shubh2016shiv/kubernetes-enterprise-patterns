"""
Module: logging_config
Purpose: Configure structured JSON logging for the inference API.
Inputs:  Log level string from InferenceSettings.
Outputs: Python standard library logging configured with a JSON formatter.
Tradeoffs: This lab uses a simple dict-based JSON formatter to keep the
           dependency list small. Enterprise teams typically use structlog
           or python-json-logger with a centralized log aggregation backend
           such as Elasticsearch, Splunk, or Datadog.
"""

from __future__ import annotations

# Standard library: logging is the foundation. json formats log records as
# structured data that log aggregation systems (Elastic, Splunk, Datadog) can
# parse and index without brittle regex patterns.
import json
import logging
import sys
from datetime import datetime, timezone


class _JsonFormatter(logging.Formatter):
    """
    Purpose:
        Emit each log record as a single JSON line on stdout. Kubernetes
        captures stdout and routes it to the node log driver (typically
        containerd's log driver), from which log aggregators collect it.
    Parameters:
        record: standard Python LogRecord.
    Return value:
        JSON string without a trailing newline (logging adds one).
    Failure behavior:
        If record.exc_info is present, the exception traceback is included
        as a string field so it does not break JSON line parsing.
    Enterprise equivalent:
        Production log pipelines ingest newline-delimited JSON from pod stdout.
        A consistent JSON schema means new engineers do not need to write custom
        parsing rules for each service.

    ENTERPRISE EMPHASIS: Structured logging (JSON or key=value) is essential in
    Kubernetes because pod logs are mixed with logs from dozens of other pods in
    the same namespace. Without structure, searching for a specific prediction
    request across many pod replicas requires manual grep patterns. With JSON,
    log aggregators can filter by model_version, pod_name, or request_id
    instantly.
    """

    def format(self, record: logging.LogRecord) -> str:
        payload: dict = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }

        # Include any extra fields the caller passed via logger.info("...", extra={...})
        for key, value in record.__dict__.items():
            if key not in _STDLIB_LOG_RECORD_FIELDS and not key.startswith("_"):
                payload[key] = value

        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        return json.dumps(payload, default=str)


# Fields that belong to the stdlib LogRecord and should not be re-emitted as
# custom extra fields. This prevents log lines from being padded with noise.
_STDLIB_LOG_RECORD_FIELDS = frozenset(
    {
        "name", "msg", "args", "levelname", "levelno", "pathname",
        "filename", "module", "exc_info", "exc_text", "stack_info",
        "lineno", "funcName", "created", "msecs", "relativeCreated",
        "thread", "threadName", "processName", "process", "message",
        "taskName",
    }
)


def configure_logging(log_level: str = "INFO") -> None:
    """
    Purpose:
        Install the JSON formatter on the root logger and set the log level.
        Call this once at application startup, before any log statements fire.
    Parameters:
        log_level: One of DEBUG, INFO, WARNING, ERROR. Case-insensitive.
    Return value:
        None. Modifies the root logger in place.
    Failure behavior:
        Invalid log level strings default to INFO (logging.getLevelName returns
        a default for unknown level names). No exception is raised.
    Enterprise equivalent:
        Production services configure logging during ASGI lifespan startup so
        that every request handler, background task, and error handler uses the
        same structured format from the first log line onward.
    """
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(_JsonFormatter())

    root_logger = logging.getLogger()
    root_logger.handlers.clear()
    root_logger.addHandler(handler)
    root_logger.setLevel(log_level.upper())

    # Suppress noisy third-party loggers that produce debug output unhelpful
    # in production JSON log streams.
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("httpx").setLevel(logging.WARNING)


def get_logger(name: str) -> logging.Logger:
    """
    Purpose:
        Return a named logger for use in any module.
        Using named loggers preserves the logger hierarchy so log levels can
        be adjusted per module without touching the root logger.
    Parameters:
        name: Typically __name__ from the calling module.
    Return value:
        Standard Python Logger instance.
    """
    return logging.getLogger(name)
