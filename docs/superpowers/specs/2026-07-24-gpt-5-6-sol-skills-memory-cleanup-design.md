# GPT-5.6 Sol Skills and Memory Cleanup Specification

**Status:** Proposed  
**Date:** 2026-07-24  
**Owner:** Jarek  
**Scope:** Personal Codex configuration, personal skills, `omg_klocki` project skills, and local Codex memory configuration

## Summary

Reduce prompt and skill-selection noise so GPT-5.6 Sol receives a smaller, more relevant instruction surface while preserving the user's hard safety boundaries, Rails defaults, Qwen/Pi workflow, and project-specific expertise.

The first rollout disables two conflicting plugins, shortens global guidance, consolidates duplicate skills, moves `omg_klocki`-only skills into that repository, modernizes `prompt-refiner`, and makes consequential skills explicit-only. Local memories remain disabled until the cleaned instruction surface has been evaluated.

## Problem Statement

The current setup was accumulated across Claude Code, older GPT models, personal Codex skills, and project-specific workflows. It works, but it presents GPT-5.6 Sol with avoidable instruction and discovery overhead:

- The Superpowers plugin requires skill invocation for nearly every task and contains workflows that tell implementers to commit, conflicting with the global `Never attempt to commit changes` rule.
- The `codex@openai-codex` plugin contains Claude Code runtime helpers and GPT-5.4 prompting guidance even though Codex itself runs GPT-5.6 Sol.
- `grill-me` and `grill-with-docs` are each discoverable twice.
- Seven `omg_klocki`-specific skills are exposed globally in unrelated repositories.
- `prompt-refiner` encourages adding persona, context, format, and constraints by default instead of first removing repetition and preserving only task-critical guidance.
- The global `AGENTS.md` repeats Rails architecture already defined by `rails-basecamp-engineer`.
- Several consequential skills may be invoked implicitly even though they delegate work, modify documentation, write artifacts, or publish externally.
- GPT-5.6 Sol is globally pinned to `high` reasoning even though `medium` is the balanced default for most Codex work.
- Local Codex memories are not enabled and contain no generated entries, so there is no current memory content to tune.

## Evidence

### Current configuration

- `~/.codex/config.toml`
  - `model = "gpt-5.6-sol"`
  - `model_reasoning_effort = "high"`
  - `superpowers@claude-plugins-official` enabled
  - `codex@openai-codex` enabled
  - local memories not enabled
  - OpenAI Developer Docs MCP configured
- `~/.codex/AGENTS.md`
  - contains a permanent no-commit rule
  - contains Qwen/Pi opt-in rules
  - repeats Rails architecture defaults from the Rails skill

### Skill conflicts and duplication

- Duplicate names:
  - `~/.agents/skills/grill-me`
  - `~/.codex/skills/grill-me`
  - `~/.agents/skills/grill-with-docs`
  - `~/.codex/skills/grill-with-docs`
- Superpowers conflict:
  - `using-superpowers` requires invocation when there is even a small chance a skill applies
  - `subagent-driven-development` describes implementers committing changes
- Stale Codex companion plugin:
  - `codex-cli-runtime` is a Claude Code companion workflow
  - `codex-result-handling` contains Claude-side execution rules
  - `gpt-5-4-prompting` targets GPT-5.4 and is already individually disabled

### Memory state

- `~/.codex/config.toml` does not enable `[features].memories`
- `~/.codex/memories/` is absent
- `~/.codex/memories_1.sqlite` contains zero `stage1_outputs` rows

## Goals

1. Present GPT-5.6 Sol with only relevant skill metadata in each repository.
2. State each durable instruction once.
3. Preserve hard safety rules and deliberate Rails/Qwen workflows.
4. Prevent implicit execution of consequential skills.
5. Use `medium` as the general reasoning baseline while allowing task-level escalation.
6. Keep every migration recoverable without Git commits.
7. Validate behavior with representative tasks before removing backups or enabling memory.

## Non-Goals

- Do not edit plugin cache contents.
- Do not rewrite bundled or system skills.
- Do not enable local memories in the baseline rollout.
- Do not rewrite the full Rails or Qwen/Pi workflow in the first rollout.
- Do not change Qwen's model, server, worktree, staging, import, or watchdog behavior.
- Do not change repository application code.
- Do not change `omg_klocki` application behavior or run its full `mix precommit` solely for documentation/skill relocation.
- Do not commit, push, rebase, reset, stash, or discard user changes.
- Do not delete source skill directories until the copied skills pass validation and the user approves the final cleanup.

## Design Principles

### Lean by default

Preserve domain context, hard constraints, approval boundaries, required evidence, success criteria, and output contracts. Remove duplicated rules, ceremonial process, generic reminders, and model-specific scaffolding that no longer corrects a demonstrated failure.

### Scope instructions at the narrowest useful level

- Personal cross-repository defaults belong in `~/.codex/AGENTS.md`.
- Personal cross-repository skills belong in `~/.agents/skills`.
- `omg_klocki`-specific skills belong in `/Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills`.
- Rich, task-specific instructions belong in a selected skill rather than global guidance.
- Generated memory is recall, never the only source of a mandatory rule.

### Match specificity to operational risk

- Keep high freedom for research, prompt refinement, and ordinary planning.
- Keep explicit procedures for Qwen/Pi isolation, import safety, and external publication.
- Require explicit invocation for workflows with delegation or side effects.

### Change one major instruction group at a time

Disable conflicting plugins and clean the skill catalog before deciding whether the Rails and Qwen skills need further shortening. Evaluate the first rollout before enabling memory or making deeper workflow changes.

## Desired End State

### Global Codex configuration

`~/.codex/config.toml` must have:

```toml
model = "gpt-5.6-sol"
model_reasoning_effort = "medium"

[plugins."superpowers@claude-plugins-official"]
enabled = false

[plugins."codex@openai-codex"]
enabled = false
```

The OpenAI Developer Docs MCP entry remains configured. Memory feature settings remain absent.

Stale trusted hook-state records may remain because disabled plugins do not execute them. Removing those records is unnecessary churn and is outside scope unless Codex continues to load the disabled hooks after restart.

### Global `AGENTS.md`

Replace the current duplicated guidance with:

```markdown
- Never commit changes.
- Never delegate implementation to Qwen/Pi without explicit user opt-in. Suggest it only for scoped, test-pinned work expected to take more than about 15 minutes and cheap to review. `/plan-for-qwen`, `plan-for-qwen`, and `$plan-for-qwen` count as explicit opt-in and must use `$plan-for-qwen`.
- For Rails application work, use `$rails-basecamp-engineer` before analysis, architecture, planning, implementation, review, refactoring, debugging, or testing. Read repository instructions, ADRs, tests, and nearby code first; deliberate local decisions override personal Rails defaults.
```

The Rails architecture defaults remain in `rails-basecamp-engineer`, where they load only for Rails work.

### Canonical global skills

The canonical personal skill root is `~/.agents/skills`.

Keep these cross-repository skills there:

| Skill | Source for canonical version | Invocation policy |
| --- | --- | --- |
| `devops-engineer` | `~/.codex/skills/devops-engineer` | implicit allowed |
| `grill-me` | `~/.codex/skills/grill-me` | implicit allowed |
| `grill-with-docs` | `~/.codex/skills/grill-with-docs` | explicit only |
| `handoff` | `~/.agents/skills/handoff` | explicit only |
| `plan-for-qwen` | `~/.codex/skills/plan-for-qwen` | explicit only |
| `prompt-refiner` | `~/.codex/skills/prompt-refiner` | implicit allowed |
| `qwen-pi-implementation` | `~/.codex/skills/qwen-pi-implementation` | explicit only |
| `to-prd` | `~/.agents/skills/to-prd` | explicit only |

After validation, move the migrated copies out of `~/.codex/skills`, except
`.system`, into the rollback snapshot so they stop participating in discovery
without being deleted.

Update the three Qwen/Pi usage examples that reference
`~/.codex/skills/qwen-pi-implementation` so they reference the canonical
`~/.agents/skills/qwen-pi-implementation` location.

### Canonical `omg_klocki` skills

Move these complete directories to `/Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills`:

- `codebase-research`
- `create-plan`
- `docs-research`
- `implement-plan`
- `onboarding-html`
- `test-runner`
- `thoughts-research`

Preserve each directory's `SKILL.md`, `agents/openai.yaml`, scripts, references, and assets. Do not copy build products, caches, or unrelated files.

### Explicit-only skill metadata

Each consequential skill must have an `agents/openai.yaml` containing:

```yaml
policy:
  allow_implicit_invocation: false
```

Apply this policy to:

- `grill-with-docs`
- `handoff`
- `plan-for-qwen`
- `qwen-pi-implementation`
- `to-prd`

Preserve each skill's existing `interface` metadata. Create missing `agents/openai.yaml` files for `handoff` and `to-prd`.

### `prompt-refiner`

The canonical skill must use this behavior:

```markdown
## Workflow

1. Identify the requested outcome and any observed failure.
2. Remove repeated, ceremonial, or conflicting instructions.
3. Preserve necessary domain context, hard constraints, approval boundaries, required evidence, success criteria, and the output contract.
4. Add persona, examples, step sequences, style rules, or extra formatting only when they encode a real requirement or correct the observed failure.
5. Prefer outcome-based instructions and let the model infer routine execution steps.
6. Preserve the user's intent and version/source requirements.

## Output Shape

Return the refined prompt followed by `Explanation of Changes`.
Keep the explanation brief and tie every material change to the behavior it should improve.
```

Update the skill description so it emphasizes removing redundancy and preserving critical constraints rather than making prompts more context-rich by default.

### `to-prd`

Resolve the current contradiction between “Do NOT interview the user” and later instructions to check module and testing choices with the user.

Desired rule:

- Synthesize without interviewing when the conversation already establishes the decisions.
- Ask one concise blocking question only when a missing choice would materially change the published PRD.

Remove the unavailable `/setup-matt-pocock-skills` instruction. If no issue-tracker tool is available, produce the PRD artifact and report that publication is blocked; do not invent a tracker or label vocabulary.

### `handoff`

Remove the unsupported `argument-hint` frontmatter key. Keep `name` and `description` only.

### Rails and Qwen/Pi skills

Do not restructure these skills in the baseline rollout:

- `/Users/jarekplonski/Dev/ai_agents/skills/rails/rails-basecamp-engineer`
- `~/.agents/skills/qwen-pi-implementation`

After the first evaluation, review whether repeated philosophy, runtime details, and lookup tables should move into one-level `references/` files. Any later refactor must preserve:

- Rails repository-precedence rules and architecture hierarchy
- Qwen opt-in, isolation, staging, review, import, timeout, and no-commit guarantees

### Memory

Keep local memories disabled during the baseline rollout.

After at least five representative clean-start sessions, decide separately whether cross-chat recall provides enough value to enable it. If enabled later:

- keep mandatory instructions in `AGENTS.md`
- use `/memories` or supported configuration rather than hand-editing generated memory files
- review generated entries before relying on them
- consider `disable_on_external_context = true` when high-precision local recall is preferred over coverage

## Representative Evaluation Tasks

Run each task in a fresh session after restarting Codex:

1. **Simple explanation in a Rails repository**
   - Prompt: `Explain what this repository contains. Do not change files.`
   - Expected: Rails skill loads only if Rails application analysis is actually required; Superpowers does not load; no implementation ceremony.

2. **Small Rails implementation**
   - Prompt: `Add a validation with a focused test.`
   - Expected: Rails skill loads; Qwen/Pi is not suggested unless the task meets the explicit threshold; no commits are attempted.

3. **Explicit Qwen opt-in**
   - Prompt: `/plan-for-qwen`
   - Expected: `plan-for-qwen` loads and carries the current task through the Qwen/Pi workflow; explicit-only policy does not block direct invocation.

4. **Ordinary plan review**
   - Prompt: `Review this implementation plan and list its three largest risks.`
   - Expected: `grill-me` may match; `grill-with-docs`, `handoff`, `to-prd`, and Qwen skills remain absent unless explicitly requested.

5. **Prompt refinement**
   - Prompt: `Refine this prompt: Be concise. Be very brief. Do not be verbose. Explain all details.`
   - Expected: `prompt-refiner` removes conflicts and repetition instead of adding generic persona or process scaffolding.

6. **Work in `omg_klocki`**
   - Prompt: `Research how authentication routes are organized. Do not change files.`
   - Expected: repo-local `codebase-research` is discoverable and used.

7. **Work outside `omg_klocki`**
   - Prompt: `Research how authentication routes are organized. Do not change files.`
   - Expected: no `omg_klocki`-specific skill appears in the available skill list.

## Acceptance Criteria

- GPT-5.6 Sol remains the selected model.
- Global reasoning effort is `medium`.
- Both conflicting plugins are disabled.
- No Superpowers or Codex-companion skills appear after restart.
- `grill-me` and `grill-with-docs` each appear exactly once.
- No `omg_klocki`-specific skill appears outside that repository.
- All seven `omg_klocki` skills appear inside that repository.
- Consequential skills are explicit-only and remain directly invocable.
- `prompt-refiner` favors subtraction, preserves critical constraints, and adds structure only for a demonstrated requirement.
- `to-prd` has no interview contradiction or unavailable setup command.
- `handoff` has valid frontmatter.
- Qwen/Pi helper tests still pass from the canonical skill location.
- No repository application files are modified.
- No commits are created.
- Memories remain disabled and no generated memory is manually edited.
- A rollback snapshot exists until the representative evaluation passes.

## Rollback

Before implementation, copy the affected configuration and skill directories to a timestamped directory under `/private/tmp`.

Rollback consists of:

1. Restore `~/.codex/config.toml`.
2. Restore `~/.codex/AGENTS.md`.
3. Restore affected directories under `~/.codex/skills` and `~/.agents/skills`.
4. Remove only the newly copied `omg_klocki/.agents/skills` directories.
5. Restart Codex and verify the previous plugin and skill list returns.

Do not remove the rollback snapshot until the user accepts the evaluation results.

## References

- [GPT-5.6 model and prompting guidance](https://developers.openai.com/api/docs/guides/latest-model)
- [Build skills](https://learn.chatgpt.com/docs/build-skills)
- [Custom instructions with AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Local Codex memories](https://learn.chatgpt.com/docs/customization/memories)

## Open Decisions

No decision blocks the baseline rollout.

The following are deliberately deferred:

- Whether to enable local memories.
- Whether to shorten the Rails skill further.
- Whether to split Qwen/Pi runtime details into references.
- Whether to retain a curated subset of Superpowers as personal, explicit-only skills.
