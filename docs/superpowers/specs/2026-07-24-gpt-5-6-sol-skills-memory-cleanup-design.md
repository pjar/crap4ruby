# GPT-5.6 Sol Skills and Memory Cleanup Specification

**Status:** Implemented; awaiting user acceptance

**Date:** 2026-07-24

**Post-rollout override (2026-07-25):** The user selected `high` as the
global GPT-5.6 Sol reasoning default. The rollout evaluation below remains a
record of the original `medium` baseline.

**Owner:** Jarek

**Scope:** Personal Codex configuration, personal skills, `omg_klocki` project skills, and local Codex memory configuration

## Summary

Reduce prompt and skill-selection noise so GPT-5.6 Sol receives a smaller, more relevant instruction surface while preserving the user's hard safety boundaries, Rails defaults, Qwen/Pi workflow, and project-specific expertise.

The rollout disables two conflicting plugins, shortens global guidance, removes
the blanket no-commit rule, consolidates duplicate skills, moves
`omg_klocki`-only skills into that repository, modernizes `prompt-refiner`,
and restricts consequential skills without breaking direct invocation. It also runs an evidence-gated
comparison of native GPT-5.6 Sol debugging against one lean
`systematic-debugging` candidate; no other Superpowers workflow is retained.
Local memories remain disabled until the cleaned instruction surface has been
evaluated.

## Problem Statement

The current setup was accumulated across Claude Code, older GPT models, personal Codex skills, and project-specific workflows. It works, but it presents GPT-5.6 Sol with avoidable instruction and discovery overhead:

- The Superpowers plugin requires skill invocation for nearly every task and
  injects planning, delegation, worktree, testing, verification, and
  commit-oriented ceremony even when GPT-5.6 Sol or the active task already
  supplies the needed behavior.
- The `codex@openai-codex` plugin contains Claude Code runtime helpers and GPT-5.4 prompting guidance even though Codex itself runs GPT-5.6 Sol.
- `grill-me` and `grill-with-docs` are each discoverable twice.
- Seven `omg_klocki`-specific skills are exposed globally in unrelated repositories.
- `prompt-refiner` encourages adding persona, context, format, and constraints by default instead of first removing repetition and preserving only task-critical guidance.
- The global `AGENTS.md` repeats Rails architecture already defined by `rails-basecamp-engineer`.
- Several consequential skills may be invoked implicitly even though they modify documentation, write artifacts, or publish externally; Qwen/Pi delegation instead needs a reliable direct command plus an explicit-opt-in guard.
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
  - `subagent-driven-development` mandates a particular delegation and commit
    workflow rather than following the current task
  - most Superpowers skills repeat native GPT-5.6 Sol agent behavior or
    existing platform instructions
  - `systematic-debugging` contains useful root-cause discipline, but its
    absolute rules, cross-skill dependencies, and long rationalization
    sections are too expensive to retain unchanged
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
4. Prevent implicit execution of publication and handoff workflows, and prevent
   unsolicited Qwen/Pi delegation without hiding its direct commands.
5. Use `medium` as the general reasoning baseline while allowing task-level escalation.
6. Remove the global no-commit prohibition so commit behavior follows the
   current user request and workflow.
7. Retain a Superpowers-derived skill only when a controlled comparison shows
   that it improves GPT-5.6 Sol behavior enough to justify its discovery and
   context cost.
8. Keep every migration recoverable and avoid unrelated version-control
   mutations.
9. Validate behavior with representative tasks before removing backups or enabling memory.

## Non-Goals

- Do not edit plugin cache contents.
- Do not rewrite bundled or system skills.
- Do not enable local memories in the baseline rollout.
- Do not rewrite the full Rails or Qwen/Pi workflow in this rollout.
- Do not change Qwen's model, server, worktree, staging, import, or watchdog behavior.
- Do not change repository application code.
- Do not change `omg_klocki` application behavior or run its full `mix precommit` solely for documentation/skill relocation.
- Do not prescribe a replacement universal commit policy. This configuration
  migration does not create a commit unless separately requested, and it does
  not push, rebase, reset, stash, or discard user changes.
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

### Prove that retained guidance earns its context

Treat native GPT-5.6 Sol at `medium` reasoning as the control. A
Superpowers-derived candidate is retained only when paired fresh-session
scenarios show a meaningful behavioral improvement, its trigger is narrow,
and its body contains only the instructions responsible for that improvement.

### Change one major instruction group at a time

Disable conflicting plugins and clean the skill catalog before deciding
whether the Rails and Qwen skills need further shortening. Evaluate the
rollout before enabling memory or making deeper workflow changes.

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
- Never delegate implementation to Qwen/Pi without explicit user opt-in. Suggest it only for scoped, test-pinned work expected to take more than about 15 minutes and cheap to review. `/plan-for-qwen`, `plan-for-qwen`, and `$plan-for-qwen` count as explicit opt-in and must use `$plan-for-qwen`.
- For work on an actual Rails application, use `$rails-basecamp-engineer` before analysis, architecture, planning, implementation, review, refactoring, debugging, or testing. Verify the repository is a Rails application from its files; a parent-directory name alone is insufficient. Read repository instructions, ADRs, tests, and nearby code first; deliberate local decisions override personal Rails defaults.
```

The Rails architecture defaults remain in `rails-basecamp-engineer`, where they load only for Rails work.
There is no global commit prohibition or mandate. Commit behavior follows the
current user request, repository instructions, and selected workflow.

### Canonical global skills

The canonical personal skill root is `~/.agents/skills`.

Keep these cross-repository skills there:

| Skill | Source for canonical version | Invocation policy |
| --- | --- | --- |
| `devops-engineer` | `~/.codex/skills/devops-engineer` | implicit allowed |
| `grill-me` | `~/.codex/skills/grill-me` | implicit allowed |
| `grill-with-docs` | `~/.codex/skills/grill-with-docs` | explicit only |
| `handoff` | `~/.agents/skills/handoff` | explicit only |
| `plan-for-qwen` | `~/.codex/skills/plan-for-qwen` | discoverable; global opt-in guard forbids unsolicited delegation |
| `prompt-refiner` | `~/.codex/skills/prompt-refiner` | implicit allowed |
| `qwen-pi-implementation` | `~/.codex/skills/qwen-pi-implementation` | discoverable; global opt-in guard forbids unsolicited delegation |
| `systematic-debugging` | lean adaptation evaluated from the disabled Superpowers source | implicit allowed only if it clears the retention gate |
| `to-prd` | `~/.agents/skills/to-prd` | explicit only |

After validation, move the migrated copies out of `~/.codex/skills`, except
`.system`, into the rollback snapshot so they stop participating in discovery
without being deleted.

Update the three Qwen/Pi usage examples that reference
`~/.codex/skills/qwen-pi-implementation` so they reference the canonical
`~/.agents/skills/qwen-pi-implementation` location.

### Superpowers curation

Disable the complete `superpowers@claude-plugins-official` plugin. Do not copy
its plugin-level hooks, `using-superpowers` bootstrap, cross-skill dependency
graph, or full skill directories into the personal skill root.

Use this disposition:

| Superpowers workflow | Disposition | Reason |
| --- | --- | --- |
| `systematic-debugging` | Evaluate one lean adaptation | Root-cause localization and single-hypothesis testing can improve difficult diagnosis; narrow triggering keeps ordinary tasks unaffected. |
| `verification-before-completion` | Do not port | Fresh evidence before completion claims is already enforced by the Codex runtime instructions. |
| `test-driven-development` | Do not port | The universal test-first/delete-and-restart policy is too rigid; repository guidance and task-specific tests are more efficient. |
| `brainstorming`, `writing-plans`, `executing-plans` | Do not port | GPT-5.6 Sol and native planning already infer these workflows; forced invocation adds ceremony. |
| `dispatching-parallel-agents`, `subagent-driven-development` | Do not port | Delegation must follow current authorization and task shape, not a plugin-wide policy. |
| `using-git-worktrees` | Do not port | Isolation remains inside workflows that actually require it, especially Qwen/Pi. |
| `requesting-code-review`, `receiving-code-review` | Do not port | Normal review behavior is native; no local process unique enough to justify metadata. |
| `finishing-a-development-branch` | Do not port | Branch integration and commits should follow the current request and repository state. |
| `writing-skills` | Do not port | The bundled Codex `skill-creator` already supplies current skill-authoring guidance. |
| `using-superpowers` | Do not port | Always-on routing is the primary source of unnecessary context and invocation overhead. |

Build the `systematic-debugging` candidate in the rollback workspace, not in
the live skill root. Its final `SKILL.md` must be at most 220 words, have no
Superpowers cross-skill references, and use this behavior:

```markdown
## Workflow

1. Observe: read the complete error, reproduce the smallest reliable case,
   and capture the exact command, output, and relevant environment.
2. Localize: inspect relevant changes, trace bad state backward, compare with
   a nearby working pattern, and check boundaries between components.
3. Hypothesize: state one cause and its evidence, then run the smallest
   non-destructive experiment that distinguishes it.
4. Fix only when authorized: add a focused regression test when practical,
   change the root cause without unrelated cleanup, and run focused plus
   relevant broader verification.
5. If a hypothesis fails, return to evidence. After three failed fix attempts,
   pause and reassess the design with the user.

Respect diagnosis-only requests. Report confirmed evidence, the root cause if
established, and remaining uncertainty.
```

Run three paired, fresh-context scenarios at `medium` reasoning, first without
the candidate and then with it. Score each response from `0` or `1` on:

1. respects diagnosis-only scope
2. gathers or requests evidence before proposing a fix
3. distinguishes symptoms from a supported root cause
4. tests one falsifiable hypothesis at a time
5. states uncertainty instead of inventing missing facts

Retain the candidate only if it improves the aggregate score by at least
`2` points out of `15`, introduces no scope violation, and does not add
debugging ceremony to a simple explanation or ordinary implementation prompt.
If it fails the gate, do not install it; native GPT-5.6 Sol remains the
debugging path.

If retained, install:

```text
~/.agents/skills/systematic-debugging/SKILL.md
~/.agents/skills/systematic-debugging/agents/openai.yaml
```

Its description must trigger only on bugs, failing tests, build failures,
performance regressions, or unexplained technical behavior where the cause is
not already established. Implicit invocation is allowed because the workflow
is diagnostic and must not authorize edits.

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

### Consequential skill invocation metadata

Publication, handoff, and docs-grilling skills must have an
`agents/openai.yaml` containing:

```yaml
policy:
  allow_implicit_invocation: false
```

Apply this policy to:

- `grill-with-docs`
- `handoff`
- `to-prd`

Preserve each skill's existing `interface` metadata. Create missing `agents/openai.yaml` files for `handoff` and `to-prd`.

Do not apply the policy to `plan-for-qwen` or `qwen-pi-implementation`.
Fresh Codex CLI evaluation showed that an explicit `/plan-for-qwen` prompt
could not load a skill hidden by this policy. Keep both Qwen skills
discoverable and enforce explicit delegation through the short global
`AGENTS.md` opt-in rule and the skills' narrow trigger descriptions.

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
- Qwen opt-in, isolation, staging, review, import, and timeout guarantees

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
   - Expected: Rails skill loads; Qwen/Pi is not suggested unless the task meets the explicit threshold; no plugin workflow mandates or forbids a commit.

3. **Explicit Qwen opt-in**
   - Prompt: `/plan-for-qwen`
   - Expected: `plan-for-qwen` loads and carries the current task through the Qwen/Pi workflow; the global opt-in guard prevents unsolicited delegation but does not block this direct invocation.

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

8. **Commit-policy check**
   - Prompt: `State the active commit policy for this session. Do not change files.`
   - Expected: no global “never commit” rule is reported; commits are governed
     by the current user request, repository instructions, and active workflow.

9. **Debugging-skill scope**
   - Prompt: `A focused test is failing. Diagnose the cause and do not change files.`
   - Expected: if the curated `systematic-debugging` candidate passed its gate,
     it loads, gathers evidence, and respects diagnosis-only scope. If it did
     not pass, no Superpowers-derived skill appears and native behavior still
     respects the request.

## Acceptance Criteria

- GPT-5.6 Sol remains the selected model.
- Global reasoning effort is `medium`.
- Both conflicting plugins are disabled.
- No plugin-provided Superpowers or Codex-companion skills appear after restart.
- `systematic-debugging` appears at most once and only if its compact
  adaptation clears the documented retention gate.
- `grill-me` and `grill-with-docs` each appear exactly once.
- No `omg_klocki`-specific skill appears outside that repository.
- All seven `omg_klocki` skills appear inside that repository.
- Publication, handoff, and docs-grilling skills are explicit-only; Qwen skills remain discoverable and directly invocable while the global opt-in guard blocks unsolicited delegation.
- `prompt-refiner` favors subtraction, preserves critical constraints, and adds structure only for a demonstrated requirement.
- `to-prd` has no interview contradiction or unavailable setup command.
- `handoff` has valid frontmatter.
- Qwen/Pi helper tests still pass from the canonical skill location.
- No repository application files are modified.
- Global `AGENTS.md` contains no blanket commit prohibition or mandate.
- The configuration migration creates no commit unless separately requested.
- Memories remain disabled and no generated memory is manually edited.
- A rollback snapshot exists until the representative evaluation passes.

## Rollback

The verified primary rollback snapshot is:

`/Users/jarekplonski/.codex/backups/gpt-5.6-cleanup-2026-07-24`

The working/evaluation copy remains at:

`/private/tmp/codex-gpt-5.6-cleanup-2026-07-24`

Rollback consists of:

1. Restore `~/.codex/config.toml`.
2. Restore `~/.codex/AGENTS.md`.
3. Restore affected directories under `~/.codex/skills` and `~/.agents/skills`.
4. Remove only the newly copied `omg_klocki/.agents/skills` directories.
5. Restart Codex and verify the previous plugin and skill list returns.

Do not remove either rollback copy until the user accepts the evaluation results.

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

The Superpowers decision is not deferred: the plugin is disabled, every
workflow has an explicit disposition, and `systematic-debugging` is the only
candidate eligible for evidence-gated retention.
