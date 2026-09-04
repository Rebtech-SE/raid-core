# Playbooks

A **playbook** is the order you do things in for one shape of task. A **skill** is a
capability you invoke. If a user could reasonably run it standalone and get a result, it is
a skill. If its value is the sequence, it is a playbook and it lives here.

## The rule

Match the task to a playbook, open its file, and **copy its steps into your todolist
verbatim, before any task-specific todos and before you reason about the task.** The
failure this prevents is reading a playbook and then writing a looser plan of your own that
quietly drops its named steps.

**A step you choose not to do stays in the list with `skip: <reason>`.** Skipping silently
is not allowed.

When no playbook fits, say so and work the route from `raid-mode` directly. Do not force a
task into the nearest playbook.

## Index

- **Autonomous run** -- a long task driven to a checkable predicate without stopping.
  `autonomous-run.md`

More will be added as the shapes prove themselves. A playbook earns its place by recurring,
not by being imaginable.
