"""
Module: patient_repository
Purpose: Isolate SQL statements from FastAPI routes and business services.
Inputs:  Validated PatientIntakeRequest models.
Outputs: PatientRecord models mapped from database rows.
Tradeoffs: The repository uses direct SQL for clarity. Larger enterprise systems
may use SQLAlchemy or internal data-access tooling, but SQL still belongs behind
a repository boundary instead of inside route handlers.
"""

# Local application: domain models and connection ownership are separate.
from app.database.connection import DatabaseConnectionFactory
from app.models.patient import PatientIntakeRequest, PatientRecord


class PatientRepository:
    """
    Purpose: Persist and read patient records.
    Parameters: connection_factory provides short-lived database connections.
    Return value: PatientRecord objects.
    Failure behavior: Database errors propagate so the API can return a clear
    failure and readiness can honestly reflect dependency health.
    Enterprise equivalent: This class is the right boundary for SQL tracing,
    retry policy, read/write splitting, and data-access auditing.
    """

    def __init__(self, connection_factory: DatabaseConnectionFactory) -> None:
        self._connection_factory = connection_factory

    def create_patient_record(self, request: PatientIntakeRequest) -> PatientRecord:
        """
        Purpose: Insert a patient record and return the stored row.
        Parameters: request is the validated intake payload.
        Return value: PatientRecord for the newly inserted row.
        Failure behavior: Rolls back on SQL failure and lets the caller surface
        the error as an API failure.
        Enterprise equivalent: Production code would add audit IDs, encryption
        controls, and possibly transactional outbox events here.
        """

        insert_sql = """
        INSERT INTO patient_records (
            full_name,
            date_of_birth,
            gender,
            phone_number,
            email_address,
            primary_symptom,
            triage_priority
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s);
        """
        with self._connection_factory.open_connection() as connection:
            try:
                with connection.cursor() as cursor:
                    cursor.execute(
                        insert_sql,
                        (
                            request.full_name,
                            request.date_of_birth,
                            request.gender,
                            request.phone_number,
                            request.email_address,
                            request.primary_symptom,
                            request.triage_priority,
                        ),
                    )
                    patient_id = int(cursor.lastrowid)
                connection.commit()
            except Exception:
                connection.rollback()
                raise

        return self.get_patient_record(patient_id)

    def get_patient_record(self, patient_id: int) -> PatientRecord:
        """
        Purpose: Fetch one patient record by primary key.
        Parameters: patient_id is the database identifier.
        Return value: PatientRecord mapped from the database row.
        Failure behavior: Raises LookupError when the row is absent.
        Enterprise equivalent: This read boundary is where teams add caching,
        row-level authorization, and audit trails.
        """

        select_sql = """
        SELECT
            patient_id,
            full_name,
            date_of_birth,
            gender,
            phone_number,
            email_address,
            primary_symptom,
            triage_priority,
            created_at
        FROM patient_records
        WHERE patient_id = %s;
        """
        with self._connection_factory.open_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(select_sql, (patient_id,))
                row = cursor.fetchone()

        if row is None:
            raise LookupError(f"patient_id={patient_id} was not found")
        return PatientRecord.model_validate(row)
