# Error Classification Reference

Complete taxonomy for classifying data pipeline errors.

## Error Categories

### 1. Parse Errors (PARSE_ERR)

Errors occurring during data parsing/deserialization.

| Subtype    | Description              | Example                       | Recovery   |
| ---------- | ------------------------ | ----------------------------- | ---------- |
| JSON parse | Invalid JSON syntax      | Missing comma, unclosed brace | Manual fix |
| XML parse  | Invalid XML              | Unclosed tag, invalid chars   | Manual fix |
| CSV parse  | Malformed CSV            | Unescaped delimiter           | Manual fix |
| Encoding   | Character encoding issue | Invalid UTF-8 bytes           | Re-encode  |

```python
def is_parse_error(exception: Exception) -> bool:
    error_keywords = [
        "json", "parse", "decode", "deserialize",
        "unexpected", "invalid character", "syntax"
    ]
    return any(kw in str(exception).lower() for kw in error_keywords)
```

### 2. Schema Errors (SCHEMA_ERR)

Errors from schema mismatches.

| Subtype            | Description            | Example                     | Recovery         |
| ------------------ | ---------------------- | --------------------------- | ---------------- |
| Missing column     | Required column absent | Expected 'email', not found | Schema evolution |
| Extra column       | Unexpected column      | Column 'foo' not in schema  | Ignore or add    |
| Type mismatch      | Column type differs    | Expected INT, got STRING    | Type coercion    |
| Nullable violation | Non-null constraint    | NULL in non-nullable column | Data fix         |

```python
def is_schema_error(exception: Exception) -> bool:
    error_keywords = [
        "schema", "column", "field", "not found",
        "missing", "unexpected column", "type mismatch"
    ]
    return any(kw in str(exception).lower() for kw in error_keywords)
```

### 3. Constraint Errors (CONSTRAINT_ERR)

Data constraint violations.

| Subtype           | Code       | Description             | Recovery        |
| ----------------- | ---------- | ----------------------- | --------------- |
| Null constraint   | NULL_ERR   | Null in required field  | Data fix        |
| Unique constraint | UNIQUE_ERR | Duplicate key           | Deduplication   |
| FK constraint     | FK_ERR     | Orphan foreign key      | Wait/fix parent |
| Check constraint  | CHECK_ERR  | Business rule violation | Data fix        |

```python
def classify_constraint_error(exception: Exception) -> str:
    msg = str(exception).lower()
    if "null" in msg or "not null" in msg:
        return "NULL_ERR"
    elif "unique" in msg or "duplicate" in msg:
        return "UNIQUE_ERR"
    elif "foreign" in msg or "reference" in msg:
        return "FK_ERR"
    elif "check" in msg or "constraint" in msg:
        return "CHECK_ERR"
    return "CONSTRAINT_ERR"
```

### 4. Validation Errors (VALIDATION_ERR)

Business rule validation failures.

| Subtype          | Code        | Description             | Recovery |
| ---------------- | ----------- | ----------------------- | -------- |
| Range violation  | RANGE_ERR   | Value outside bounds    | Data fix |
| Pattern mismatch | PATTERN_ERR | Regex validation failed | Data fix |
| Enum violation   | ENUM_ERR    | Invalid enum value      | Data fix |
| Logic violation  | LOGIC_ERR   | Business logic failed   | Review   |

```python
def classify_validation_error(rule_name: str, value: any) -> dict:
    return {
        "error_type": "VALIDATION_ERR",
        "subtype": rule_name,
        "invalid_value": str(value),
        "recoverable": False
    }
```

### 5. Transformation Errors (TRANSFORM_ERR)

Errors during data transformation.

| Subtype    | Description          | Example                   | Recovery |
| ---------- | -------------------- | ------------------------- | -------- |
| Type cast  | Cast failure         | "abc" to INT              | Data fix |
| Arithmetic | Division by zero     | amount/0                  | Data fix |
| Function   | Function error       | Invalid date format       | Data fix |
| Expression | SQL expression error | Syntax error in transform | Code fix |

```python
def is_transformation_error(exception: Exception) -> bool:
    error_keywords = [
        "cast", "convert", "transform", "arithmetic",
        "division by zero", "overflow", "underflow"
    ]
    return any(kw in str(exception).lower() for kw in error_keywords)
```

### 6. External System Errors (EXTERNAL_ERR)

Errors from external dependencies.

| Subtype             | Code        | Description           | Recoverable |
| ------------------- | ----------- | --------------------- | ----------- |
| Timeout             | TIMEOUT_ERR | Connection timeout    | Yes         |
| Rate limit          | RATE_LIMIT  | API throttling        | Yes         |
| Auth failure        | AUTH_ERR    | Authentication failed | No (config) |
| Network             | NETWORK_ERR | Connection failed     | Maybe       |
| Service unavailable | SERVICE_ERR | 503 error             | Yes         |

```python
def classify_external_error(exception: Exception) -> tuple:
    """Returns (error_code, is_recoverable)."""
    msg = str(exception).lower()

    if "timeout" in msg:
        return ("TIMEOUT_ERR", True)
    elif "rate" in msg or "throttl" in msg or "429" in msg:
        return ("RATE_LIMIT", True)
    elif "auth" in msg or "401" in msg or "403" in msg:
        return ("AUTH_ERR", False)
    elif "connect" in msg or "network" in msg:
        return ("NETWORK_ERR", True)
    elif "503" in msg or "unavailable" in msg:
        return ("SERVICE_ERR", True)
    return ("EXTERNAL_ERR", True)
```

## Complete Classification Function

```python
from dataclasses import dataclass
from typing import Optional

@dataclass
class ErrorClassification:
    error_type: str
    subtype: Optional[str]
    is_recoverable: bool
    recommended_action: str
    details: dict

def classify_error_full(
    exception: Exception,
    context: dict = None
) -> ErrorClassification:
    """
    Comprehensive error classification.

    Args:
        exception: The caught exception
        context: Additional context (source, record, etc.)

    Returns:
        ErrorClassification with type, recovery info, and action
    """
    msg = str(exception).lower()
    context = context or {}

    # Parse errors
    if any(kw in msg for kw in ["parse", "json", "xml", "decode"]):
        return ErrorClassification(
            error_type="PARSE_ERR",
            subtype=_get_parse_subtype(msg),
            is_recoverable=False,
            recommended_action="Manual review and fix of source data",
            details={"original_message": str(exception)}
        )

    # Schema errors
    if any(kw in msg for kw in ["schema", "column", "field not found"]):
        return ErrorClassification(
            error_type="SCHEMA_ERR",
            subtype=_get_schema_subtype(msg),
            is_recoverable=False,
            recommended_action="Schema evolution or source fix required",
            details={"original_message": str(exception)}
        )

    # Constraint errors
    if any(kw in msg for kw in ["null", "unique", "duplicate", "foreign", "constraint"]):
        subtype = classify_constraint_error(exception)
        return ErrorClassification(
            error_type="CONSTRAINT_ERR",
            subtype=subtype,
            is_recoverable=subtype == "FK_ERR",  # FK might resolve later
            recommended_action="Data fix or wait for parent record",
            details={"original_message": str(exception)}
        )

    # Transformation errors
    if any(kw in msg for kw in ["cast", "convert", "division", "overflow"]):
        return ErrorClassification(
            error_type="TRANSFORM_ERR",
            subtype=_get_transform_subtype(msg),
            is_recoverable=False,
            recommended_action="Fix source data or transformation logic",
            details={"original_message": str(exception)}
        )

    # External system errors
    if any(kw in msg for kw in ["timeout", "rate", "auth", "connect", "503", "429"]):
        code, recoverable = classify_external_error(exception)
        return ErrorClassification(
            error_type="EXTERNAL_ERR",
            subtype=code,
            is_recoverable=recoverable,
            recommended_action="Retry with backoff" if recoverable else "Fix configuration",
            details={"original_message": str(exception)}
        )

    # Unknown
    return ErrorClassification(
        error_type="UNKNOWN",
        subtype=None,
        is_recoverable=False,
        recommended_action="Manual investigation required",
        details={"original_message": str(exception), "exception_type": type(exception).__name__}
    )

def _get_parse_subtype(msg: str) -> str:
    if "json" in msg:
        return "JSON_PARSE"
    elif "xml" in msg:
        return "XML_PARSE"
    elif "csv" in msg:
        return "CSV_PARSE"
    elif "encoding" in msg or "utf" in msg:
        return "ENCODING"
    return "PARSE"

def _get_schema_subtype(msg: str) -> str:
    if "missing" in msg or "not found" in msg:
        return "MISSING_COLUMN"
    elif "type" in msg:
        return "TYPE_MISMATCH"
    elif "extra" in msg or "unexpected" in msg:
        return "EXTRA_COLUMN"
    return "SCHEMA"

def _get_transform_subtype(msg: str) -> str:
    if "cast" in msg or "convert" in msg:
        return "TYPE_CAST"
    elif "division" in msg:
        return "ARITHMETIC"
    elif "overflow" in msg or "underflow" in msg:
        return "OVERFLOW"
    return "TRANSFORM"
```

## Error Code Quick Reference

| Code        | Category   | Recoverable | Typical Action     |
| ----------- | ---------- | ----------- | ------------------ |
| PARSE_ERR   | Parse      | No          | Fix source data    |
| SCHEMA_ERR  | Schema     | No          | Schema evolution   |
| NULL_ERR    | Constraint | No          | Fix source data    |
| UNIQUE_ERR  | Constraint | No          | Deduplicate        |
| FK_ERR      | Constraint | Maybe       | Wait for parent    |
| RANGE_ERR   | Validation | No          | Fix source data    |
| PATTERN_ERR | Validation | No          | Fix source data    |
| TYPE_CAST   | Transform  | No          | Fix data or logic  |
| TIMEOUT_ERR | External   | Yes         | Retry              |
| RATE_LIMIT  | External   | Yes         | Retry with backoff |
| AUTH_ERR    | External   | No          | Fix credentials    |
| NETWORK_ERR | External   | Yes         | Retry              |
| SERVICE_ERR | External   | Yes         | Retry              |
| UNKNOWN     | Unknown    | Unknown     | Investigate        |

## Usage Example

```python
try:
    result = process_record(record)
except Exception as e:
    classification = classify_error_full(e, {"record": record})

    dlq_record = {
        "error_id": str(uuid.uuid4()),
        "original_record": json.dumps(record),
        "error_type": classification.error_type,
        "error_subtype": classification.subtype,
        "error_message": str(e),
        "is_recoverable": classification.is_recoverable,
        "recommended_action": classification.recommended_action,
        "status": "pending" if classification.is_recoverable else "needs_review"
    }

    write_to_dlq(dlq_record)
```
