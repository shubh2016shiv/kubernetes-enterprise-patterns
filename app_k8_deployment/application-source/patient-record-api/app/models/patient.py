"""
Module: patient
Purpose: Define typed API contracts for patient intake requests and responses.
Inputs:  JSON submitted by the UI or an API client.
Outputs: Validated Pydantic models used by FastAPI routes and service logic.
Tradeoffs: The lab captures intentionally minimal healthcare information. Real
healthcare platforms require stricter validation, consent handling, encryption,
audit logging, and regulatory controls such as HIPAA-aligned safeguards.
"""

# Standard library: date models the patient's date of birth precisely.
from datetime import date, datetime
from typing import Literal

# Third-party: Pydantic provides validation and OpenAPI schema generation.
# Enterprise: explicit models become API contracts for frontend teams, QA, and
# downstream service consumers.
from pydantic import BaseModel, EmailStr, Field


TriagePriority = Literal["routine", "urgent", "emergency"]


class PatientIntakeRequest(BaseModel):
    """
    Purpose: Validate patient details submitted by the intake form.
    Parameters: JSON body fields from the frontend.
    Return value: A typed request model.
    Failure behavior: FastAPI returns HTTP 422 for invalid payloads.
    Enterprise equivalent: This is the boundary where teams apply domain
    validation before data reaches business logic or storage.
    """

    full_name: str = Field(min_length=2, max_length=160)
    date_of_birth: date
    gender: str = Field(min_length=2, max_length=32)
    phone_number: str = Field(min_length=7, max_length=40)
    email_address: EmailStr | None = None
    primary_symptom: str = Field(min_length=3, max_length=255)
    triage_priority: TriagePriority = "routine"


class PatientRecord(BaseModel):
    """
    Purpose: Represent a stored patient record returned by the API.
    Parameters: Database row values mapped by the repository.
    Return value: A response-safe patient record.
    Failure behavior: Invalid row shapes raise validation errors during mapping.
    Enterprise equivalent: Response models prevent accidental leakage of fields
    that should remain internal.
    """

    patient_id: int
    full_name: str
    date_of_birth: date
    gender: str
    phone_number: str
    email_address: EmailStr | None
    primary_symptom: str
    triage_priority: TriagePriority
    created_at: datetime


class PatientIntakeResponse(BaseModel):
    """
    Purpose: Wrap the created patient record with deployment identity metadata.
    Parameters: created record plus runtime pod identity.
    Return value: JSON response for the frontend.
    Failure behavior: Any invalid field raises a Pydantic validation error.
    Enterprise equivalent: Including pod metadata helps learners connect one API
    response to the Kubernetes pod that served it.
    """

    status: Literal["accepted"]
    record: PatientRecord
    served_by_pod: str
    served_from_node: str
