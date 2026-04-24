"""
Module: patient_service
Purpose: Hold patient intake business behavior outside route handlers.
Inputs:  Validated API request models.
Outputs: API response models containing stored records and pod identity.
Tradeoffs: The current business rule is intentionally small. The service layer
exists because enterprise applications grow rules quickly, and route handlers
should remain orchestration boundaries rather than business-code dumping grounds.
"""

# Local application: config, API models, and repository are distinct concerns.
from app.core.config import Settings
from app.models.patient import PatientIntakeRequest, PatientIntakeResponse
from app.repositories.patient_repository import PatientRepository


class PatientIntakeService:
    """
    Purpose: Coordinate validation-ready intake requests with persistence.
    Parameters: repository persists records; settings provides pod identity.
    Return value: PatientIntakeResponse.
    Failure behavior: Repository failures propagate and become HTTP 500 at the
    route boundary.
    Enterprise equivalent: This layer is where workflow, events, audit logging,
    and compliance checks usually live.
    """

    def __init__(self, repository: PatientRepository, settings: Settings) -> None:
        self._repository = repository
        self._settings = settings

    def create_patient_record(
        self,
        request: PatientIntakeRequest,
    ) -> PatientIntakeResponse:
        """
        Purpose: Create one patient record from the intake form.
        Parameters: request contains validated patient details.
        Return value: PatientIntakeResponse with stored record metadata.
        Failure behavior: Database failures are not swallowed; callers need the
        real signal for debugging and alerting.
        Enterprise equivalent: A production service may publish a domain event
        after commit so downstream teams can react asynchronously.
        """

        stored_record = self._repository.create_patient_record(request)
        return PatientIntakeResponse(
            status="accepted",
            record=stored_record,
            served_by_pod=self._settings.pod_name,
            served_from_node=self._settings.node_name,
        )
