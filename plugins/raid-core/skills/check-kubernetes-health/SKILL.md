---
name: check-kubernetes-health
description: >-
  Use when the user asks 'is the cluster healthy', 'check the Kubernetes cluster', 'why are
  pods failing', 'which pods are crashlooping', or wants scheduled cluster monitoring.
  Read-only health report of a Kubernetes cluster: node readiness and pressure, workloads
  short of replicas, and failed, pending, crashlooping, evicted or OOM-killed pods, each
  with the next read-only command to run. Exit code drives scheduled alerts.
argument-hint: "[--context <ctx>] [--namespace <ns>] [--since-pending <min>]"
---

# Kubernetes Health Check

A fast, read-only sweep of a Kubernetes cluster that answers "is it healthy right now, and
what needs attention?". It is the cluster-level counterpart of `check-platform-health`, which
checks data pipelines, freshness and data quality.

It observes and reports. It **never** restarts, deletes, scales, cordons, drains or patches
anything. Remediation is a separate, human decision.

## Inputs

<input> #$ARGUMENTS </input>

- `--context <ctx>`: the kubeconfig context. Blank = the current one. Say which context you
  checked in the report, so nobody mistakes a dev cluster for production.
- `--namespace <ns>`: one namespace. Blank = all namespaces the credentials can list.
- Thresholds: `--pending-minutes` (default 5) and `--restart-threshold` (default 5).

## Workflow

### 1. Confirm access, read-only

Check `kubectl` is installed and which context is current
(`kubectl config current-context`). If the user named a cluster, use its context. If the
credentials can do more than read, say so once and recommend the read-only role in
`references/readonly-rbac.yaml`; never use the extra rights.

### 2. Run the check

```bash
python3 <this-skill>/scripts/k8s_health.py --context <ctx> [--namespace <ns>]
```

The script runs only `kubectl get` (nodes, pods, deployments, statefulsets, daemonsets,
events) and scores three dimensions:

| Dimension | ALERT | WARN |
|---|---|---|
| **Nodes** | Ready is not True | Memory, disk or PID pressure; network unavailable; cordoned |
| **Workloads** | Deployment, StatefulSet or DaemonSet with 0 available | Fewer available than desired |
| **Pods** | CrashLoopBackOff, ImagePullBackOff, ErrImagePull, container config errors, Failed | Evicted, OOMKilled, pending past the threshold, restarts at or above the threshold |

Each finding carries the newest Warning event for that object and the next **read-only**
command to run (`kubectl describe ...`, `kubectl logs ... --previous`).

A signal the script cannot gather (forbidden, cluster unreachable) is reported as
`UNKNOWN`, never as OK. Exit code: 0 OK, 1 WARN, 2 ALERT, 3 UNKNOWN. An ALERT outranks
UNKNOWN, so a missing signal never hides a failure that was seen.

### 3. Report

Print the script's board, then explain only what needs attention: what is wrong, the likely
cause from the event or scheduler message, and the next read-only command. For a
CrashLoopBackOff, run the suggested `logs --previous` yourself and quote the failing lines.
Group findings that share one cause (five pods pending on "Insufficient cpu" is one capacity
problem, not five). All green: say so and stop.

### 4. Hand off

- A fix is needed: describe the options (roll back the image, raise a limit, add capacity)
  and leave the change to the user. Changing the cluster is outside this skill.
- A recurring problem: file it on the engagement's issue tracker.

## Scheduled monitoring

The script is built to run unattended: `--format json` for machines, the exit code for
alerting. Any scheduler that can run a command and act on a non-zero exit works:

- **A CI pipeline on a schedule** (Azure Pipelines `schedules:`, GitHub Actions `cron`) with
  a read-only kubeconfig secret; fail the run on exit 2 so the team's normal pipeline-failure
  notification fires.
- **A Kubernetes CronJob** in the cluster itself, with the read-only service account from
  `references/readonly-rbac.yaml`, posting the JSON to a chat webhook when the exit code is
  not 0.

Keep the schedule read-only too. Notification is the only side effect.

## Rules

- Read-only. Only `kubectl get`, `describe` and `logs`; never a verb that changes the
  cluster, even when the fix looks obvious.
- Least privilege: recommend `references/readonly-rbac.yaml` (get/list/watch on the
  resources above, and `pods/log`). It grants no access to Secrets.
- Unknown is not OK.
- Name the context and namespace in every report.
