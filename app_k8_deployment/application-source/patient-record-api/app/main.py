"""
Module: main
Purpose: Assemble the FastAPI application and HTTP routes.
Inputs:  Kubernetes-injected environment variables and HTTP requests.
Outputs: FastAPI ASGI application exposing patient intake and health endpoints.
Tradeoffs: This lab keeps route count small so the learner can focus on how the
application maps to Kubernetes lifecycle controls. The internal structure still
uses separate config, database, repository, service, and health modules.
"""

# Third-party: FastAPI owns the HTTP layer and OpenAPI generation.
# Enterprise: In production this service would commonly sit behind an ingress
# controller, gateway, service mesh, WAF, and centralized observability stack.
from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware

# Local application: each import reflects one clear responsibility boundary.
from app.core.config import Settings, get_settings
from app.database.connection import DatabaseConnectionFactory
from app.health.health_checks import HealthCheckService
from app.models.patient import PatientIntakeRequest, PatientIntakeResponse
from app.repositories.patient_repository import PatientRepository
from app.services.patient_service import PatientIntakeService


def build_connection_factory(
    settings: Settings = Depends(get_settings),
) -> DatabaseConnectionFactory:
    """
    Purpose: Provide database connections to request-scoped dependencies.
    Parameters: settings is injected by FastAPI.
    Return value: DatabaseConnectionFactory.
    Failure behavior: Configuration errors surface before request processing.
    Enterprise equivalent: This is where a platform library might inject pooled
    clients, TLS configuration, and tracing.
    """

    return DatabaseConnectionFactory(settings)


def build_patient_service(
    settings: Settings = Depends(get_settings),
    connection_factory: DatabaseConnectionFactory = Depends(build_connection_factory),
) -> PatientIntakeService:
    """
    Purpose: Wire the service layer without placing construction in routes.
    Parameters: settings and connection_factory are injected dependencies.
    Return value: PatientIntakeService.
    Failure behavior: Dependency construction errors become request failures.
    Enterprise equivalent: This pattern keeps services testable and replaceable.
    """

    repository = PatientRepository(connection_factory)
    return PatientIntakeService(repository, settings)


def build_health_service(
    settings: Settings = Depends(get_settings),
    connection_factory: DatabaseConnectionFactory = Depends(build_connection_factory),
) -> HealthCheckService:
    """
    Purpose: Wire health checks separately from patient business logic.
    Parameters: settings and connection_factory are injected dependencies.
    Return value: HealthCheckService.
    Failure behavior: Readiness failures return HTTP 503 at the route boundary.
    Enterprise equivalent: Health checks deserve their own ownership because
    Kubernetes lifecycle decisions depend on them.
    """

    return HealthCheckService(connection_factory, settings)


def create_application() -> FastAPI:
    """
    Purpose: Build and configure the FastAPI application.
    Parameters: None.
    Return value: FastAPI app used by Uvicorn.
    Failure behavior: Schema initialization failure prevents the pod from
    becoming healthy, making the rollout stop instead of serving broken traffic.
    Enterprise equivalent: Application factories make testing and deployment
    wiring easier than import-time global side effects.
    """

    settings = get_settings()

    application = FastAPI(
        title="Patient Record API",
        version=settings.api_version,
        description="Healthcare intake backend for the enterprise Kubernetes deployment lab.",
    )
    application.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["GET", "POST"],
        allow_headers=["*"],
    )

    @application.get("/livez", tags=["health"])
    def liveness(
        health_service: HealthCheckService = Depends(build_health_service),
    ) -> dict[str, object]:
        """
        Purpose: Kubernetes liveness endpoint.
        Parameters: health_service is injected by FastAPI.
        Return value: Process-health metadata.
        Failure behavior: Unexpected failures return HTTP 500 and kubelet may
        restart the container after repeated probe failures.
        Enterprise equivalent: Liveness protects against wedged app processes.
        """

        return health_service.get_liveness()

    @application.get("/readyz", tags=["health"])
    def readiness(
        health_service: HealthCheckService = Depends(build_health_service),
    ) -> dict[str, object]:
        """
        Purpose: Kubernetes readiness endpoint.
        Parameters: health_service is injected by FastAPI.
        Return value: Dependency-aware readiness metadata.
        Failure behavior: Database or schema failures become HTTP 503, removing
        the pod from Service endpoints until the dependency recovers.
        Enterprise equivalent: Readiness is the safe-traffic gate during rollouts.
        """

        try:
            return health_service.get_readiness()
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"database dependency is not ready: {exc}",
            ) from exc

    @application.post(
        "/patients",
        response_model=PatientIntakeResponse,
        status_code=status.HTTP_201_CREATED,
        tags=["patients"],
    )
    def create_patient_record(
        request: PatientIntakeRequest,
        patient_service: PatientIntakeService = Depends(build_patient_service),
    ) -> PatientIntakeResponse:
        """
        Purpose: Accept a patient intake form submission.
        Parameters: request is validated by Pydantic; patient_service owns the
        business workflow.
        Return value: Created patient record and pod identity.
        Failure behavior: Validation errors return 422; persistence errors
        return 500 so operators can investigate database health.
        Enterprise equivalent: Route handlers orchestrate; services own rules;
        repositories own storage.
        """

        try:
            return patient_service.create_patient_record(request)
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"unable to create patient record: {exc}",
            ) from exc

    @application.get("/", tags=["metadata"])
    def service_metadata(settings: Settings = Depends(get_settings)) -> dict[str, str]:
        """
        Purpose: Return deployment identity for quick smoke tests.
        Parameters: settings is injected by FastAPI.
        Return value: Service metadata.
        Failure behavior: None expected after app startup succeeds.
        Enterprise equivalent: Build and runtime metadata help incident response.
        """

        return {
            "service": settings.app_name,
            "environment": settings.app_environment,
            "version": settings.api_version,
            "pod_name": settings.pod_name,
            "namespace": settings.pod_namespace,
            "node_name": settings.node_name,
        }

    return application
