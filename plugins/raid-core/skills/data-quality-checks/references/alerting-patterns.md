# Data Quality Alerting Patterns

Patterns for alerting and notification when data quality issues are detected.

## Alert Severity Framework

```python
from enum import Enum
from dataclasses import dataclass
from typing import List, Dict, Optional
from datetime import datetime

class AlertSeverity(Enum):
    CRITICAL = "critical"  # Immediate action required
    HIGH = "high"          # Action required within hours
    MEDIUM = "medium"      # Review within 24 hours
    LOW = "low"            # Informational

class AlertChannel(Enum):
    SLACK = "slack"
    EMAIL = "email"
    PAGERDUTY = "pagerduty"
    TEAMS = "teams"
    WEBHOOK = "webhook"

@dataclass
class QualityAlert:
    dataset: str
    check_name: str
    severity: AlertSeverity
    message: str
    details: Dict
    timestamp: datetime = None
    channels: List[AlertChannel] = None

    def __post_init__(self):
        self.timestamp = self.timestamp or datetime.now()
        self.channels = self.channels or self._default_channels()

    def _default_channels(self) -> List[AlertChannel]:
        """Default channels based on severity."""
        if self.severity == AlertSeverity.CRITICAL:
            return [AlertChannel.PAGERDUTY, AlertChannel.SLACK]
        elif self.severity == AlertSeverity.HIGH:
            return [AlertChannel.SLACK, AlertChannel.EMAIL]
        elif self.severity == AlertSeverity.MEDIUM:
            return [AlertChannel.SLACK]
        else:
            return []  # Low severity: log only
```

## Alert Generation

```python
def generate_alerts(validator_results: List[ValidationResult]) -> List[QualityAlert]:
    """Generate alerts from validation results."""
    alerts = []

    for result in validator_results:
        if result.passed:
            continue

        # Map severity
        severity_map = {
            "critical": AlertSeverity.CRITICAL,
            "high": AlertSeverity.HIGH,
            "medium": AlertSeverity.MEDIUM,
            "low": AlertSeverity.LOW
        }
        severity = severity_map.get(result.severity.value, AlertSeverity.MEDIUM)

        # Create alert
        alert = QualityAlert(
            dataset=result.details.get("dataset", "unknown"),
            check_name=result.name,
            severity=severity,
            message=f"Data quality check '{result.name}' failed: {result.failed_rows:,} rows failed ({1-result.pass_rate:.1%})",
            details={
                "check_type": result.check_type,
                "total_rows": result.total_rows,
                "failed_rows": result.failed_rows,
                "pass_rate": result.pass_rate,
                "sample_failures": result.sample_failures[:3] if result.sample_failures else []
            }
        )
        alerts.append(alert)

    return alerts
```

## Slack Integration

```python
import requests
import json

class SlackAlerter:
    """Send data quality alerts to Slack."""

    def __init__(self, webhook_url: str, channel: str = None):
        self.webhook_url = webhook_url
        self.channel = channel

    def send_alert(self, alert: QualityAlert) -> bool:
        """Send single alert to Slack."""
        color = self._severity_color(alert.severity)

        payload = {
            "channel": self.channel,
            "attachments": [{
                "color": color,
                "title": f"Data Quality Alert: {alert.severity.value.upper()}",
                "text": alert.message,
                "fields": [
                    {"title": "Dataset", "value": alert.dataset, "short": True},
                    {"title": "Check", "value": alert.check_name, "short": True},
                    {"title": "Failed Rows", "value": f"{alert.details['failed_rows']:,}", "short": True},
                    {"title": "Pass Rate", "value": f"{alert.details['pass_rate']:.1%}", "short": True}
                ],
                "footer": f"Data Quality Monitor | {alert.timestamp.strftime('%Y-%m-%d %H:%M:%S')}"
            }]
        }

        response = requests.post(self.webhook_url, json=payload)
        return response.status_code == 200

    def send_summary(self, alerts: List[QualityAlert], dataset: str) -> bool:
        """Send summary of all alerts."""
        if not alerts:
            return True

        critical = sum(1 for a in alerts if a.severity == AlertSeverity.CRITICAL)
        high = sum(1 for a in alerts if a.severity == AlertSeverity.HIGH)

        color = "danger" if critical > 0 else "warning" if high > 0 else "good"

        blocks = [
            {
                "type": "header",
                "text": {"type": "plain_text", "text": f"Data Quality Summary: {dataset}"}
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*Critical:* {critical}"},
                    {"type": "mrkdwn", "text": f"*High:* {high}"},
                    {"type": "mrkdwn", "text": f"*Total Alerts:* {len(alerts)}"}
                ]
            }
        ]

        # Add top failures
        for alert in alerts[:5]:
            blocks.append({
                "type": "section",
                "text": {"type": "mrkdwn", "text": f"*{alert.check_name}*: {alert.message}"}
            })

        payload = {"blocks": blocks}
        response = requests.post(self.webhook_url, json=payload)
        return response.status_code == 200

    def _severity_color(self, severity: AlertSeverity) -> str:
        colors = {
            AlertSeverity.CRITICAL: "danger",
            AlertSeverity.HIGH: "warning",
            AlertSeverity.MEDIUM: "#439FE0",
            AlertSeverity.LOW: "good"
        }
        return colors.get(severity, "warning")

# Usage
slack = SlackAlerter(webhook_url="https://hooks.slack.com/services/xxx")
for alert in alerts:
    if AlertChannel.SLACK in alert.channels:
        slack.send_alert(alert)
```

## Email Integration

```python
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

class EmailAlerter:
    """Send data quality alerts via email."""

    def __init__(
        self,
        smtp_host: str,
        smtp_port: int,
        username: str,
        password: str,
        from_address: str
    ):
        self.smtp_host = smtp_host
        self.smtp_port = smtp_port
        self.username = username
        self.password = password
        self.from_address = from_address

    def send_alert(self, alert: QualityAlert, to_addresses: List[str]) -> bool:
        """Send alert email."""
        msg = MIMEMultipart("alternative")
        msg["Subject"] = f"[{alert.severity.value.upper()}] Data Quality Alert: {alert.dataset}"
        msg["From"] = self.from_address
        msg["To"] = ", ".join(to_addresses)

        # Plain text
        text = f"""
Data Quality Alert

Severity: {alert.severity.value.upper()}
Dataset: {alert.dataset}
Check: {alert.check_name}
Time: {alert.timestamp}

{alert.message}

Details:
- Total Rows: {alert.details['total_rows']:,}
- Failed Rows: {alert.details['failed_rows']:,}
- Pass Rate: {alert.details['pass_rate']:.1%}
"""

        # HTML
        html = f"""
<html>
<body>
<h2 style="color: {'red' if alert.severity == AlertSeverity.CRITICAL else 'orange'}">
    Data Quality Alert: {alert.severity.value.upper()}
</h2>
<table>
    <tr><td><strong>Dataset:</strong></td><td>{alert.dataset}</td></tr>
    <tr><td><strong>Check:</strong></td><td>{alert.check_name}</td></tr>
    <tr><td><strong>Failed Rows:</strong></td><td>{alert.details['failed_rows']:,}</td></tr>
    <tr><td><strong>Pass Rate:</strong></td><td>{alert.details['pass_rate']:.1%}</td></tr>
</table>
<p>{alert.message}</p>
</body>
</html>
"""

        msg.attach(MIMEText(text, "plain"))
        msg.attach(MIMEText(html, "html"))

        try:
            with smtplib.SMTP(self.smtp_host, self.smtp_port) as server:
                server.starttls()
                server.login(self.username, self.password)
                server.sendmail(self.from_address, to_addresses, msg.as_string())
            return True
        except Exception as e:
            print(f"Email send failed: {e}")
            return False
```

## PagerDuty Integration

```python
import requests

class PagerDutyAlerter:
    """Send critical alerts to PagerDuty."""

    def __init__(self, routing_key: str):
        self.routing_key = routing_key
        self.api_url = "https://events.pagerduty.com/v2/enqueue"

    def send_alert(self, alert: QualityAlert) -> bool:
        """Send alert to PagerDuty."""
        if alert.severity != AlertSeverity.CRITICAL:
            return True  # Only send critical alerts

        payload = {
            "routing_key": self.routing_key,
            "event_action": "trigger",
            "dedup_key": f"{alert.dataset}_{alert.check_name}",
            "payload": {
                "summary": f"Data Quality Critical: {alert.dataset} - {alert.check_name}",
                "severity": "critical",
                "source": "data-quality-monitor",
                "custom_details": {
                    "dataset": alert.dataset,
                    "check_name": alert.check_name,
                    "message": alert.message,
                    "failed_rows": alert.details["failed_rows"],
                    "pass_rate": alert.details["pass_rate"]
                }
            }
        }

        response = requests.post(self.api_url, json=payload)
        return response.status_code == 202

    def resolve_alert(self, dataset: str, check_name: str) -> bool:
        """Resolve a previously triggered alert."""
        payload = {
            "routing_key": self.routing_key,
            "event_action": "resolve",
            "dedup_key": f"{dataset}_{check_name}"
        }

        response = requests.post(self.api_url, json=payload)
        return response.status_code == 202
```

## Alert Routing

```python
class AlertRouter:
    """Route alerts to appropriate channels based on configuration."""

    def __init__(
        self,
        slack: SlackAlerter = None,
        email: EmailAlerter = None,
        pagerduty: PagerDutyAlerter = None
    ):
        self.slack = slack
        self.email = email
        self.pagerduty = pagerduty

        # Default email recipients by severity
        self.email_recipients = {
            AlertSeverity.CRITICAL: ["oncall@company.com", "data-team@company.com"],
            AlertSeverity.HIGH: ["data-team@company.com"],
            AlertSeverity.MEDIUM: ["data-team@company.com"],
            AlertSeverity.LOW: []
        }

    def route_alert(self, alert: QualityAlert) -> Dict[str, bool]:
        """Route alert to configured channels."""
        results = {}

        for channel in alert.channels:
            if channel == AlertChannel.SLACK and self.slack:
                results["slack"] = self.slack.send_alert(alert)

            elif channel == AlertChannel.EMAIL and self.email:
                recipients = self.email_recipients.get(alert.severity, [])
                if recipients:
                    results["email"] = self.email.send_alert(alert, recipients)

            elif channel == AlertChannel.PAGERDUTY and self.pagerduty:
                results["pagerduty"] = self.pagerduty.send_alert(alert)

        return results

    def route_all_alerts(self, alerts: List[QualityAlert]) -> Dict[str, int]:
        """Route all alerts and return summary."""
        summary = {"sent": 0, "failed": 0}

        for alert in alerts:
            results = self.route_alert(alert)
            if all(results.values()):
                summary["sent"] += 1
            else:
                summary["failed"] += 1

        return summary

# Usage
router = AlertRouter(
    slack=SlackAlerter(webhook_url="..."),
    pagerduty=PagerDutyAlerter(routing_key="...")
)

alerts = generate_alerts(validator.get_results())
router.route_all_alerts(alerts)
```

## dbt Alert Integration

```yaml
# dbt_project.yml
on-run-end:
  - "{{ send_quality_alerts() }}"
```

```sql
-- macros/send_quality_alerts.sql
{% macro send_quality_alerts() %}
    {% if execute %}
        {% set failed_tests = [] %}

        {% for result in results %}
            {% if result.status == 'fail' %}
                {% do failed_tests.append({
                    'name': result.node.name,
                    'severity': result.node.config.severity,
                    'failures': result.failures
                }) %}
            {% endif %}
        {% endfor %}

        {% if failed_tests | length > 0 %}
            {{ log("Sending alerts for " ~ failed_tests | length ~ " failed tests", info=True) }}
            -- Call external alert system via run_query or post-hook
        {% endif %}
    {% endif %}
{% endmacro %}
```

## Alert Suppression

```python
from datetime import datetime, timedelta

class AlertSuppressor:
    """Suppress duplicate alerts within time window."""

    def __init__(self, suppression_minutes: int = 60):
        self.suppression_minutes = suppression_minutes
        self.sent_alerts: Dict[str, datetime] = {}

    def should_send(self, alert: QualityAlert) -> bool:
        """Check if alert should be sent or suppressed."""
        key = f"{alert.dataset}_{alert.check_name}"
        now = datetime.now()

        if key in self.sent_alerts:
            last_sent = self.sent_alerts[key]
            if now - last_sent < timedelta(minutes=self.suppression_minutes):
                return False

        self.sent_alerts[key] = now
        return True

# Usage
suppressor = AlertSuppressor(suppression_minutes=60)

for alert in alerts:
    if suppressor.should_send(alert):
        router.route_alert(alert)
```
