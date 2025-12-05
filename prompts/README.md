# Miaou Prompt Workspace

This directory mirrors the automation workflow used in octez-setup. Tasks are
stored as Markdown prompts under the subdirectories below:

- `active/` – tasks ready for Agent2 to pick up
- `lite/` – lightweight tasks that skip the planning/review cycle
- `ongoing/` – tasks currently being developed
- `done/` – tasks awaiting review
- `reviewed/` – post-review archive (read-only for Agent2)

Keep prompts small and self-contained. When Octez-setup depends on new Miaou
capabilities, add tasks here for the library work, and reference the matching
Octez-setup task once Miaou changes are ready to consume.
