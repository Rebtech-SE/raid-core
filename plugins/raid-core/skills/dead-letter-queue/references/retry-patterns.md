# Retry Patterns Reference

Comprehensive retry patterns for resilient data pipelines.

## Retry Strategy Selection

| Scenario                | Strategy                | Parameters                     |
| ----------------------- | ----------------------- | ------------------------------ |
| Transient network error | Exponential backoff     | 3 retries, 1s base, 2x factor  |
| API rate limiting       | Exponential with jitter | 5 retries, respect Retry-After |
| Database deadlock       | Fixed delay             | 3 retries, 100ms delay         |
| External service down   | Circuit breaker         | 5 failures to open, 60s reset  |

## Exponential Backoff

### Basic Implementation

```python
import time
import random
from typing import Callable, TypeVar, Any

T = TypeVar('T')

def retry_with_exponential_backoff(
    func: Callable[[], T],
    max_retries: int = 3,
    base_delay: float = 1.0,
    max_delay: float = 60.0,
    exponential_base: float = 2.0,
    jitter: bool = True,
    retryable_exceptions: tuple = (Exception,)
) -> T:
    """
    Retry with exponential backoff.

    Args:
        func: Function to retry (no arguments)
        max_retries: Maximum number of retries
        base_delay: Initial delay in seconds
        max_delay: Maximum delay cap
        exponential_base: Multiplier for each retry
        jitter: Add randomness to prevent thundering herd
        retryable_exceptions: Exception types to retry

    Returns:
        Result of successful function call

    Raises:
        Last exception if all retries fail
    """
    last_exception = None

    for attempt in range(max_retries + 1):
        try:
            return func()
        except retryable_exceptions as e:
            last_exception = e

            if attempt == max_retries:
                break

            # Calculate delay
            delay = min(base_delay * (exponential_base ** attempt), max_delay)

            # Add jitter (0.5 to 1.5 of calculated delay)
            if jitter:
                delay = delay * (0.5 + random.random())

            print(f"Attempt {attempt + 1}/{max_retries + 1} failed: {e}")
            print(f"Retrying in {delay:.2f} seconds...")
            time.sleep(delay)

    raise last_exception
```

### With Decorator

```python
from functools import wraps

def retry(
    max_retries: int = 3,
    base_delay: float = 1.0,
    exponential_base: float = 2.0,
    retryable_exceptions: tuple = (Exception,)
):
    """Decorator for retry with exponential backoff."""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            return retry_with_exponential_backoff(
                lambda: func(*args, **kwargs),
                max_retries=max_retries,
                base_delay=base_delay,
                exponential_base=exponential_base,
                retryable_exceptions=retryable_exceptions
            )
        return wrapper
    return decorator

# Usage
@retry(max_retries=3, base_delay=1.0, retryable_exceptions=(TimeoutError, ConnectionError))
def call_external_api(url: str) -> dict:
    response = requests.get(url, timeout=30)
    response.raise_for_status()
    return response.json()
```

## Circuit Breaker

### Implementation

```python
from enum import Enum
from datetime import datetime, timedelta
from threading import Lock

class CircuitState(Enum):
    CLOSED = "closed"      # Normal operation
    OPEN = "open"          # Failing, reject requests
    HALF_OPEN = "half_open"  # Testing if recovered

class CircuitBreaker:
    """
    Circuit breaker pattern for external dependencies.

    States:
    - CLOSED: Normal operation, track failures
    - OPEN: Too many failures, reject all requests
    - HALF_OPEN: Allow test request to check recovery
    """

    def __init__(
        self,
        name: str,
        failure_threshold: int = 5,
        recovery_timeout: int = 60,
        half_open_max_calls: int = 3
    ):
        self.name = name
        self.failure_threshold = failure_threshold
        self.recovery_timeout = timedelta(seconds=recovery_timeout)
        self.half_open_max_calls = half_open_max_calls

        self._state = CircuitState.CLOSED
        self._failure_count = 0
        self._last_failure_time = None
        self._half_open_calls = 0
        self._lock = Lock()

    @property
    def state(self) -> CircuitState:
        with self._lock:
            if self._state == CircuitState.OPEN:
                # Check if recovery timeout has passed
                if datetime.now() - self._last_failure_time >= self.recovery_timeout:
                    self._state = CircuitState.HALF_OPEN
                    self._half_open_calls = 0
            return self._state

    def call(self, func: Callable[[], T]) -> T:
        """Execute function with circuit breaker protection."""
        current_state = self.state

        if current_state == CircuitState.OPEN:
            raise CircuitOpenError(f"Circuit {self.name} is OPEN")

        try:
            result = func()
            self._on_success()
            return result
        except Exception as e:
            self._on_failure()
            raise

    def _on_success(self):
        with self._lock:
            if self._state == CircuitState.HALF_OPEN:
                self._half_open_calls += 1
                if self._half_open_calls >= self.half_open_max_calls:
                    # Recovered, close circuit
                    self._state = CircuitState.CLOSED
                    self._failure_count = 0
            elif self._state == CircuitState.CLOSED:
                # Reset failure count on success
                self._failure_count = 0

    def _on_failure(self):
        with self._lock:
            self._failure_count += 1
            self._last_failure_time = datetime.now()

            if self._state == CircuitState.HALF_OPEN:
                # Failed during test, reopen
                self._state = CircuitState.OPEN
            elif self._failure_count >= self.failure_threshold:
                # Too many failures, open circuit
                self._state = CircuitState.OPEN

class CircuitOpenError(Exception):
    """Raised when circuit breaker is open."""
    pass

# Usage
api_circuit = CircuitBreaker("external_api", failure_threshold=5, recovery_timeout=60)

def fetch_data():
    try:
        return api_circuit.call(lambda: requests.get(API_URL).json())
    except CircuitOpenError:
        # Return cached data or default
        return get_cached_data()
```

## Retry Queue Pattern

### For Batch Processing

```python
from collections import deque
from dataclasses import dataclass
from datetime import datetime, timedelta

@dataclass
class RetryItem:
    record: dict
    error: str
    retry_count: int
    next_retry_time: datetime

class RetryQueue:
    """Queue for managing retry attempts in batch processing."""

    def __init__(
        self,
        max_retries: int = 3,
        base_delay_seconds: int = 60
    ):
        self.max_retries = max_retries
        self.base_delay_seconds = base_delay_seconds
        self._queue: deque[RetryItem] = deque()

    def add_for_retry(self, record: dict, error: str, current_retry: int = 0):
        """Add failed record to retry queue."""
        if current_retry >= self.max_retries:
            # Exceeded max retries, route to DLQ
            return False

        delay = self.base_delay_seconds * (2 ** current_retry)
        next_retry = datetime.now() + timedelta(seconds=delay)

        self._queue.append(RetryItem(
            record=record,
            error=error,
            retry_count=current_retry + 1,
            next_retry_time=next_retry
        ))
        return True

    def get_ready_items(self) -> list:
        """Get items ready for retry."""
        now = datetime.now()
        ready = []

        # Check all items (deque doesn't support efficient filtering)
        remaining = deque()
        while self._queue:
            item = self._queue.popleft()
            if item.next_retry_time <= now:
                ready.append(item)
            else:
                remaining.append(item)

        self._queue = remaining
        return ready

    def get_stats(self) -> dict:
        """Get queue statistics."""
        return {
            "pending_count": len(self._queue),
            "by_retry_count": self._count_by_retry(),
            "next_retry": min((i.next_retry_time for i in self._queue), default=None)
        }

    def _count_by_retry(self) -> dict:
        counts = {}
        for item in self._queue:
            counts[item.retry_count] = counts.get(item.retry_count, 0) + 1
        return counts

# Usage in batch processing
retry_queue = RetryQueue(max_retries=3, base_delay_seconds=60)

def process_batch(records: list):
    successful = []
    for record in records:
        try:
            result = process_record(record)
            successful.append(result)
        except RecoverableError as e:
            retry_queue.add_for_retry(record, str(e))

    # Process retries from previous batches
    ready_for_retry = retry_queue.get_ready_items()
    for item in ready_for_retry:
        try:
            result = process_record(item.record)
            successful.append(result)
        except RecoverableError as e:
            if not retry_queue.add_for_retry(item.record, str(e), item.retry_count):
                # Max retries exceeded, send to DLQ
                write_to_dlq(item.record, str(e), item.retry_count)

    return successful
```

## Retry with Dead Letter Queue

```python
from typing import Callable, List, Tuple

def process_with_retry_and_dlq(
    records: List[dict],
    process_func: Callable[[dict], dict],
    max_retries: int = 3,
    retry_delay: float = 1.0
) -> Tuple[List[dict], List[dict]]:
    """
    Process records with retry and DLQ fallback.

    Returns:
        Tuple of (successful_records, dlq_records)
    """
    successful = []
    dlq_records = []

    for record in records:
        success = False
        last_error = None

        for attempt in range(max_retries + 1):
            try:
                result = process_func(record)
                successful.append(result)
                success = True
                break
            except RecoverableError as e:
                last_error = e
                if attempt < max_retries:
                    delay = retry_delay * (2 ** attempt)
                    time.sleep(delay)
            except NonRecoverableError as e:
                last_error = e
                break  # Don't retry non-recoverable errors

        if not success:
            dlq_records.append({
                "original_record": record,
                "error": str(last_error),
                "retry_count": attempt,
                "error_type": type(last_error).__name__
            })

    return successful, dlq_records

# Custom exception classes
class RecoverableError(Exception):
    """Error that may succeed on retry."""
    pass

class NonRecoverableError(Exception):
    """Error that will not succeed on retry."""
    pass
```

## Backoff Strategies Comparison

| Strategy             | Formula                                | Best For              |
| -------------------- | -------------------------------------- | --------------------- |
| Constant             | `delay = base`                         | Testing, simple cases |
| Linear               | `delay = base * attempt`               | Gradual increase      |
| Exponential          | `delay = base * 2^attempt`             | API rate limits       |
| Exponential + Jitter | `delay = random(0, base * 2^attempt)`  | Distributed systems   |
| Decorrelated Jitter  | `delay = random(base, prev_delay * 3)` | AWS recommendation    |

```python
import random

def constant_backoff(base: float, attempt: int) -> float:
    return base

def linear_backoff(base: float, attempt: int) -> float:
    return base * (attempt + 1)

def exponential_backoff(base: float, attempt: int) -> float:
    return base * (2 ** attempt)

def exponential_with_jitter(base: float, attempt: int) -> float:
    exp_delay = base * (2 ** attempt)
    return random.uniform(0, exp_delay)

def decorrelated_jitter(base: float, attempt: int, prev_delay: float = None) -> float:
    if prev_delay is None:
        return base
    return random.uniform(base, prev_delay * 3)
```
