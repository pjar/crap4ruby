# GPT-5.6 Sol Skills and Memory Cleanup Implementation Plan

> **For agentic workers:** Execute this plan task-by-task in the main session. Do not use subagents unless the user explicitly requests delegation. Never commit, push, rebase, reset, stash, or discard user changes. Track progress with the checkboxes below.

**Goal:** Reduce global instruction and skill-selection noise for GPT-5.6 Sol while preserving safety boundaries, Rails defaults, Qwen/Pi behavior, and `omg_klocki` expertise.

**Architecture:** Keep universal rules in global `AGENTS.md`, cross-repository workflows in `~/.agents/skills`, and `omg_klocki` workflows in that repository's `.agents/skills`. Disable incompatible plugins through configuration rather than editing their caches. Keep memory disabled until the cleaned setup is evaluated.

**Tech Stack:** Codex `config.toml`, Markdown `AGENTS.md` and `SKILL.md`, YAML `agents/openai.yaml`, shell validation, Ruby/Python YAML tooling, existing Qwen/Pi helper tests.

**Specification:** `docs/superpowers/specs/2026-07-24-gpt-5-6-sol-skills-memory-cleanup-design.md`

## Global Constraints

- Never commit changes.
- Do not edit plugin cache contents or system skills.
- Do not delete or overwrite user data before creating and verifying a rollback snapshot.
- Preserve unrelated changes in `/Users/jarekplonski/Dev/elixir/omg_klocki`.
- Keep `model = "gpt-5.6-sol"`.
- Keep local memories disabled during this plan.
- Keep the OpenAI Developer Docs MCP configured.
- Keep Rails and Qwen/Pi behavioral contracts unchanged except where this plan explicitly updates invocation policy or prompt wording.
- Any write outside `/Users/jarekplonski/Dev/Rails/moje/crap4ruby` requires the normal sandbox approval.

---

## File Map

### Files modified

- `/Users/jarekplonski/.codex/config.toml`
  - change default reasoning effort
  - disable the Superpowers and Codex companion plugins
- `/Users/jarekplonski/.codex/AGENTS.md`
  - replace duplicated global guidance with the concise specification text
- `/Users/jarekplonski/.agents/skills/prompt-refiner/SKILL.md`
  - adopt GPT-5.6-oriented subtraction-first refinement
- `/Users/jarekplonski/.agents/skills/prompt-refiner/agents/openai.yaml`
  - preserve UI metadata after migration
- `/Users/jarekplonski/.agents/skills/grill-with-docs/agents/openai.yaml`
  - make invocation explicit-only
- `/Users/jarekplonski/.agents/skills/plan-for-qwen/agents/openai.yaml`
  - make invocation explicit-only
- `/Users/jarekplonski/.agents/skills/qwen-pi-implementation/agents/openai.yaml`
  - make invocation explicit-only
- `/Users/jarekplonski/.agents/skills/handoff/SKILL.md`
  - remove unsupported frontmatter and preserve the workflow
- `/Users/jarekplonski/.agents/skills/handoff/agents/openai.yaml`
  - add UI metadata and explicit-only policy
- `/Users/jarekplonski/.agents/skills/to-prd/SKILL.md`
  - resolve interaction contradiction and unavailable setup command
- `/Users/jarekplonski/.agents/skills/to-prd/agents/openai.yaml`
  - add UI metadata and explicit-only policy

### Directories copied to the canonical global skill root

- `/Users/jarekplonski/.codex/skills/devops-engineer` → `/Users/jarekplonski/.agents/skills/devops-engineer`
- `/Users/jarekplonski/.codex/skills/grill-me` → `/Users/jarekplonski/.agents/skills/grill-me`
- `/Users/jarekplonski/.codex/skills/grill-with-docs` → `/Users/jarekplonski/.agents/skills/grill-with-docs`
- `/Users/jarekplonski/.codex/skills/plan-for-qwen` → `/Users/jarekplonski/.agents/skills/plan-for-qwen`
- `/Users/jarekplonski/.codex/skills/prompt-refiner` → `/Users/jarekplonski/.agents/skills/prompt-refiner`
- `/Users/jarekplonski/.codex/skills/qwen-pi-implementation` → `/Users/jarekplonski/.agents/skills/qwen-pi-implementation`

### Directories copied to `omg_klocki`

- `/Users/jarekplonski/.codex/skills/codebase-research` → `/Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/codebase-research`
- `/Users/jarekplonski/.codex/skills/create-plan` → `/Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/create-plan`
- `/Users/jarekplonski/.codex/skills/docs-research` → `/Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/docs-research`
- `/Users/jarekplonski/.codex/skills/implement-plan` → `/Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/implement-plan`
- `/Users/jarekplonski/.codex/skills/onboarding-html` → `/Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/onboarding-html`
- `/Users/jarekplonski/.codex/skills/test-runner` → `/Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/test-runner`
- `/Users/jarekplonski/.codex/skills/thoughts-research` → `/Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/thoughts-research`

### Directories retired only after acceptance

- The migrated non-system directories under `/Users/jarekplonski/.codex/skills`
  are moved into the rollback snapshot so they stop participating in discovery
  without being deleted.
- The superseded original versions of:
  - `/Users/jarekplonski/.agents/skills/grill-me`
  - `/Users/jarekplonski/.agents/skills/grill-with-docs`

Cutover is a separate approval-gated step after validation. Until then,
preserve originals in the rollback snapshot.

---

### Task 1: Capture inventory and rollback snapshot

**Files:**

- Read: `/Users/jarekplonski/.codex/config.toml`
- Read: `/Users/jarekplonski/.codex/AGENTS.md`
- Read: `/Users/jarekplonski/.codex/skills`
- Read: `/Users/jarekplonski/.agents/skills`
- Read: `/Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills`
- Create outside repositories: `/private/tmp/codex-gpt-5.6-cleanup-2026-07-24/`

**Produces:** A complete rollback snapshot and a before-state inventory.

- [ ] **Step 1: Verify working trees before any external write**

Run:

```bash
git -C /Users/jarekplonski/Dev/Rails/moje/crap4ruby status --short
git -C /Users/jarekplonski/Dev/elixir/omg_klocki status --short
```

Record both outputs in the session. Treat every listed change as pre-existing and out of scope.

- [ ] **Step 2: Create the rollback directory**

Run:

```bash
mkdir -p /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/codex
mkdir -p /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/agents
mkdir -p /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/omg-klocki
```

- [ ] **Step 3: Copy affected global configuration**

Run:

```bash
cp -p /Users/jarekplonski/.codex/config.toml /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/codex/config.toml
cp -p /Users/jarekplonski/.codex/AGENTS.md /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/codex/AGENTS.md
cp -a /Users/jarekplonski/.codex/skills /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/codex/skills
cp -a /Users/jarekplonski/.agents/skills /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/agents/skills
```

- [ ] **Step 4: Snapshot existing `omg_klocki` agent state**

If `/Users/jarekplonski/Dev/elixir/omg_klocki/.agents` exists, run:

```bash
cp -a /Users/jarekplonski/Dev/elixir/omg_klocki/.agents /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/omg-klocki/agents
```

If it does not exist, record `omg_klocki .agents absent before migration` in the session.

- [ ] **Step 5: Verify snapshot contents**

Run:

```bash
test -f /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/codex/config.toml
test -f /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/codex/AGENTS.md
test -d /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/codex/skills
test -d /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/agents/skills
```

Expected: all commands exit `0`.

---

### Task 2: Simplify global Codex configuration

**Files:**

- Modify: `/Users/jarekplonski/.codex/config.toml`

**Produces:** GPT-5.6 Sol at medium effort with incompatible plugins disabled.

- [ ] **Step 1: Change reasoning effort**

Change:

```toml
model_reasoning_effort = "high"
```

to:

```toml
model_reasoning_effort = "medium"
```

- [ ] **Step 2: Disable Superpowers**

Change:

```toml
[plugins."superpowers@claude-plugins-official"]
enabled = true
```

to:

```toml
[plugins."superpowers@claude-plugins-official"]
enabled = false
```

- [ ] **Step 3: Disable the Codex Claude Code companion**

Change:

```toml
[plugins."codex@openai-codex"]
enabled = true
```

to:

```toml
[plugins."codex@openai-codex"]
enabled = false
```

Keep the existing individual GPT-5.4 skill disable entry. It is redundant after disabling the plugin but harmless and documents intent.

- [ ] **Step 4: Verify required configuration**

Run:

```bash
rg -n '^(model|model_reasoning_effort) =|^\[plugins\."(superpowers@claude-plugins-official|codex@openai-codex)"\]|^enabled =|^\[mcp_servers\.openaiDeveloperDocs\]' /Users/jarekplonski/.codex/config.toml
```

Expected:

- `model = "gpt-5.6-sol"`
- `model_reasoning_effort = "medium"`
- both targeted plugins have `enabled = false`
- `mcp_servers.openaiDeveloperDocs` remains present

- [ ] **Step 5: Confirm memories remain disabled**

Run:

```bash
rg -n '^\[memories\]|^memories = true|^\[features\]' /Users/jarekplonski/.codex/config.toml
```

Expected: the `[features]` table may appear, but there is no `memories = true` and no active `[memories]` table.

---

### Task 3: Replace global `AGENTS.md` with concise guidance

**Files:**

- Modify: `/Users/jarekplonski/.codex/AGENTS.md`

**Produces:** One non-duplicated source for global no-commit, Qwen opt-in, and Rails-skill routing.

- [ ] **Step 1: Replace the file contents**

Use exactly:

```markdown
- Never commit changes.
- Never delegate implementation to Qwen/Pi without explicit user opt-in. Suggest it only for scoped, test-pinned work expected to take more than about 15 minutes and cheap to review. `/plan-for-qwen`, `plan-for-qwen`, and `$plan-for-qwen` count as explicit opt-in and must use `$plan-for-qwen`.
- For Rails application work, use `$rails-basecamp-engineer` before analysis, architecture, planning, implementation, review, refactoring, debugging, or testing. Read repository instructions, ADRs, tests, and nearby code first; deliberate local decisions override personal Rails defaults.
```

- [ ] **Step 2: Verify global requirements**

Run:

```bash
rg -n 'Never commit|Qwen/Pi|plan-for-qwen|rails-basecamp-engineer|deliberate local decisions' /Users/jarekplonski/.codex/AGENTS.md
```

Expected: all five concepts appear.

- [ ] **Step 3: Verify duplicated Rails defaults were removed**

Run:

```bash
rg -n 'app/services|CRUD-only|37signals|repositories|controller concerns' /Users/jarekplonski/.codex/AGENTS.md
```

Expected: no matches. Those rules remain in `rails-basecamp-engineer`.

---

### Task 4: Copy canonical cross-repository skills into `~/.agents/skills`

**Files:**

- Create or replace the six canonical global skill directories listed in the File Map.

**Produces:** One documented user-level home for reusable skills.

- [ ] **Step 1: Copy non-conflicting skills**

Run:

```bash
cp -a /Users/jarekplonski/.codex/skills/devops-engineer /Users/jarekplonski/.agents/skills/devops-engineer
cp -a /Users/jarekplonski/.codex/skills/plan-for-qwen /Users/jarekplonski/.agents/skills/plan-for-qwen
cp -a /Users/jarekplonski/.codex/skills/prompt-refiner /Users/jarekplonski/.agents/skills/prompt-refiner
cp -a /Users/jarekplonski/.codex/skills/qwen-pi-implementation /Users/jarekplonski/.agents/skills/qwen-pi-implementation
```

- [ ] **Step 2: Replace duplicate grill skills with the selected canonical versions**

The rollback snapshot already preserves the existing `~/.agents` versions. Replace them with the richer `~/.codex` versions:

```bash
cp -a /Users/jarekplonski/.codex/skills/grill-me/. /Users/jarekplonski/.agents/skills/grill-me/
cp -a /Users/jarekplonski/.codex/skills/grill-with-docs/. /Users/jarekplonski/.agents/skills/grill-with-docs/
```

- [ ] **Step 3: Verify every canonical global skill**

Run:

```bash
for skill in devops-engineer grill-me grill-with-docs plan-for-qwen prompt-refiner qwen-pi-implementation; do
  test -f "/Users/jarekplonski/.agents/skills/$skill/SKILL.md" || exit 1
done
```

Expected: exit `0`.

- [ ] **Step 4: Verify Qwen helper assets survived relocation**

Run:

```bash
test -f /Users/jarekplonski/.agents/skills/qwen-pi-implementation/scripts/qwen_pi_worktree.sh
test -f /Users/jarekplonski/.agents/skills/qwen-pi-implementation/scripts/qwen_pi_import_patch.sh
test -f /Users/jarekplonski/.agents/skills/qwen-pi-implementation/scripts/test_qwen_pi_helpers.sh
test -f /Users/jarekplonski/.agents/skills/qwen-pi-implementation/pi-skills/qwen-implementation/SKILL.md
```

Expected: all commands exit `0`.

- [ ] **Step 5: Update Qwen usage examples for the canonical location**

In `/Users/jarekplonski/.agents/skills/qwen-pi-implementation/SKILL.md`,
replace all three occurrences of:

```text
~/.codex/skills/qwen-pi-implementation
```

with:

```text
~/.agents/skills/qwen-pi-implementation
```

- [ ] **Step 6: Verify no old Qwen usage path remains**

Run:

```bash
rg -n '~/.codex/skills/qwen-pi-implementation|/Users/jarekplonski/\.codex/skills/qwen-pi-implementation' /Users/jarekplonski/.agents/skills/qwen-pi-implementation
```

Expected: no matches.

---

### Task 5: Move `omg_klocki` skills into the repository

**Files:**

- Create: `/Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills`
- Copy the seven project skill directories listed in the File Map.

**Produces:** Project-only discovery for Phoenix/Elixir workflows.

- [ ] **Step 1: Reconfirm unrelated `omg_klocki` changes**

Run:

```bash
git -C /Users/jarekplonski/Dev/elixir/omg_klocki status --short
```

Compare with Task 1. Stop if new unrelated changes appeared and cannot be attributed.

- [ ] **Step 2: Create the repository skill root**

Run:

```bash
mkdir -p /Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills
```

- [ ] **Step 3: Copy the seven complete skill directories**

Run:

```bash
cp -a /Users/jarekplonski/.codex/skills/codebase-research /Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/codebase-research
cp -a /Users/jarekplonski/.codex/skills/create-plan /Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/create-plan
cp -a /Users/jarekplonski/.codex/skills/docs-research /Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/docs-research
cp -a /Users/jarekplonski/.codex/skills/implement-plan /Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/implement-plan
cp -a /Users/jarekplonski/.codex/skills/onboarding-html /Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/onboarding-html
cp -a /Users/jarekplonski/.codex/skills/test-runner /Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/test-runner
cp -a /Users/jarekplonski/.codex/skills/thoughts-research /Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/thoughts-research
```

- [ ] **Step 4: Verify copied skills**

Run:

```bash
for skill in codebase-research create-plan docs-research implement-plan onboarding-html test-runner thoughts-research; do
  test -f "/Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/$skill/SKILL.md" || exit 1
done
```

Expected: exit `0`.

- [ ] **Step 5: Verify the repository diff is limited to `.agents/skills` plus pre-existing work**

Run:

```bash
git -C /Users/jarekplonski/Dev/elixir/omg_klocki status --short
git -C /Users/jarekplonski/Dev/elixir/omg_klocki diff -- .agents/skills
```

Expected: newly added files are only under `.agents/skills`; existing application changes remain untouched.

---

### Task 6: Modernize `prompt-refiner`

**Files:**

- Modify: `/Users/jarekplonski/.agents/skills/prompt-refiner/SKILL.md`
- Verify: `/Users/jarekplonski/.agents/skills/prompt-refiner/agents/openai.yaml`

**Produces:** A subtraction-first GPT-5.6 prompt-refinement workflow.

- [ ] **Step 1: Replace the description**

Use:

```yaml
description: "Refine unclear, conflicting, or malfunctioning prompts by removing redundancy and preserving the objective, critical context, constraints, approval boundaries, success criteria, and output contract. Use when Codex is asked to improve prompt reliability, length control, grounding, or output behavior."
```

- [ ] **Step 2: Replace the workflow and output sections**

Use:

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

Remove the Claude-command equivalence sentence and the default instruction to improve persona/background/format whether or not they are needed.

- [ ] **Step 3: Verify metadata remains aligned**

Confirm `/Users/jarekplonski/.agents/skills/prompt-refiner/agents/openai.yaml` contains:

```yaml
interface:
  display_name: "Prompt Refiner"
  short_description: "Rewrite unclear prompts precisely"
  default_prompt: "Use $prompt-refiner to refine this prompt for better model behavior."
```

- [ ] **Step 4: Scan for obsolete guidance**

Run:

```bash
rg -n 'Claude|persona, context|context-rich|ceremonial|approval boundaries|success criteria' /Users/jarekplonski/.agents/skills/prompt-refiner/SKILL.md
```

Expected:

- no Claude equivalence
- no unconditional persona/context expansion
- positive matches for subtraction and critical constraints

---

### Task 7: Make consequential skills explicit-only

**Files:**

- Modify: `/Users/jarekplonski/.agents/skills/grill-with-docs/agents/openai.yaml`
- Modify: `/Users/jarekplonski/.agents/skills/plan-for-qwen/agents/openai.yaml`
- Modify: `/Users/jarekplonski/.agents/skills/qwen-pi-implementation/agents/openai.yaml`
- Create: `/Users/jarekplonski/.agents/skills/handoff/agents/openai.yaml`
- Create: `/Users/jarekplonski/.agents/skills/to-prd/agents/openai.yaml`

**Produces:** Explicit invocation boundaries for delegation, publication, and write-capable workflows.

- [ ] **Step 1: Add explicit-only policy to existing metadata**

Append this top-level block to each existing YAML file:

```yaml
policy:
  allow_implicit_invocation: false
```

- [ ] **Step 2: Create `handoff` metadata**

Create:

```yaml
interface:
  display_name: "Handoff"
  short_description: "Prepare a redacted session handoff"
  default_prompt: "Use $handoff to prepare a compact handoff for another agent."

policy:
  allow_implicit_invocation: false
```

- [ ] **Step 3: Create `to-prd` metadata**

Create:

```yaml
interface:
  display_name: "To PRD"
  short_description: "Publish the current context as a PRD"
  default_prompt: "Use $to-prd to turn the current conversation into a PRD."

policy:
  allow_implicit_invocation: false
```

- [ ] **Step 4: Verify policies**

Run:

```bash
for skill in grill-with-docs handoff plan-for-qwen qwen-pi-implementation to-prd; do
  rg -n 'allow_implicit_invocation: false' "/Users/jarekplonski/.agents/skills/$skill/agents/openai.yaml" || exit 1
done
```

Expected: one match per skill and exit `0`.

---

### Task 8: Repair `handoff` and `to-prd`

**Files:**

- Modify: `/Users/jarekplonski/.agents/skills/handoff/SKILL.md`
- Modify: `/Users/jarekplonski/.agents/skills/to-prd/SKILL.md`

**Produces:** Valid frontmatter and internally consistent publication behavior.

- [ ] **Step 1: Remove unsupported `handoff` frontmatter**

Delete:

```yaml
argument-hint: "What will the next session be used for?"
```

Keep:

```yaml
---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
---
```

- [ ] **Step 2: Replace the contradictory `to-prd` interaction rules**

Replace both the unconditional no-interview sentence and the later module/testing confirmation instructions with:

```markdown
Synthesize the PRD from the current conversation and codebase evidence without interviewing when the required decisions are already established. Ask one concise blocking question only when a missing product, architecture, or testing choice would materially change the published PRD.
```

- [ ] **Step 3: Replace unavailable setup behavior**

Remove:

```markdown
run `/setup-matt-pocock-skills` if not
```

Add:

```markdown
Use the issue-tracker and label vocabulary available in the current session. If no issue-tracker publishing tool is available, produce the complete PRD artifact and report publication as blocked; do not invent a tracker, project, or label.
```

- [ ] **Step 4: Verify the repaired skills**

Run:

```bash
rg -n 'argument-hint|setup-matt-pocock-skills|Do NOT interview|Check with the user' /Users/jarekplonski/.agents/skills/handoff/SKILL.md /Users/jarekplonski/.agents/skills/to-prd/SKILL.md
```

Expected: no matches.

Run:

```bash
rg -n 'one concise blocking question|publication as blocked|do not invent' /Users/jarekplonski/.agents/skills/to-prd/SKILL.md
```

Expected: all three behaviors appear.

---

### Task 9: Validate skill structure and relocated Qwen helpers

**Files:**

- Validate all canonical global and `omg_klocki` skill directories.
- Execute: `/Users/jarekplonski/.agents/skills/qwen-pi-implementation/scripts/test_qwen_pi_helpers.sh`

**Produces:** Structural validation and proof that relocation did not break Qwen helper behavior.

- [ ] **Step 1: Create an isolated validator environment**

Run:

```bash
python3 -m venv /private/tmp/codex-skill-validator-2026-07-24
/private/tmp/codex-skill-validator-2026-07-24/bin/pip install PyYAML
```

If dependency download is blocked by the sandbox, request the normal scoped network approval. Do not install PyYAML into the user's global Python.

- [ ] **Step 2: Validate canonical global skills**

Run:

```bash
for skill in devops-engineer grill-me grill-with-docs handoff plan-for-qwen prompt-refiner qwen-pi-implementation to-prd; do
  /private/tmp/codex-skill-validator-2026-07-24/bin/python \
    /Users/jarekplonski/.codex/skills/.system/skill-creator/scripts/quick_validate.py \
    "/Users/jarekplonski/.agents/skills/$skill" || exit 1
done
```

Expected: every skill prints `Skill is valid!`.

- [ ] **Step 3: Validate `omg_klocki` skills**

Run:

```bash
for skill in codebase-research create-plan docs-research implement-plan onboarding-html test-runner thoughts-research; do
  /private/tmp/codex-skill-validator-2026-07-24/bin/python \
    /Users/jarekplonski/.codex/skills/.system/skill-creator/scripts/quick_validate.py \
    "/Users/jarekplonski/Dev/elixir/omg_klocki/.agents/skills/$skill" || exit 1
done
```

Expected: every skill prints `Skill is valid!`.

- [ ] **Step 4: Run Qwen helper tests from the new canonical path**

Run:

```bash
/Users/jarekplonski/.agents/skills/qwen-pi-implementation/scripts/test_qwen_pi_helpers.sh
```

Expected: exit `0` with the helper test suite's full passing summary.

- [ ] **Step 5: Verify no absolute references depend on the old Qwen skill path**

Run:

```bash
rg -n '/Users/jarekplonski/\.codex/skills/qwen-pi-implementation|~/.codex/skills/qwen-pi-implementation' /Users/jarekplonski/.agents/skills/qwen-pi-implementation
```

Expected: no matches. Relative helper paths are valid from the new location.

---

### Task 10: Cut over from legacy global skill copies

**Files:**

- Move only the migrated non-system directories under
  `/Users/jarekplonski/.codex/skills` into the rollback snapshot.

**Produces:** No duplicate or globally leaked skill names.

**Approval boundary:** This task changes global skill discovery. Obtain the
normal explicit sandbox approval immediately before Step 2.

- [ ] **Step 1: List exact removal targets**

Run:

```bash
for skill in codebase-research create-plan devops-engineer docs-research grill-me grill-with-docs implement-plan onboarding-html plan-for-qwen prompt-refiner qwen-pi-implementation test-runner thoughts-research; do
  test -d "/Users/jarekplonski/.codex/skills/$skill" && printf '%s\n' "/Users/jarekplonski/.codex/skills/$skill"
done
```

Compare the output exactly with the expected list. Do not include `/Users/jarekplonski/.codex/skills/.system`.

- [ ] **Step 2: Create the retirement directory**

Run:

```bash
mkdir -p /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/retired-codex-skills
```

- [ ] **Step 3: Move only the approved migrated directories**

After explicit approval, run:

```bash
mv /Users/jarekplonski/.codex/skills/codebase-research /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/retired-codex-skills/codebase-research
mv /Users/jarekplonski/.codex/skills/create-plan /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/retired-codex-skills/create-plan
mv /Users/jarekplonski/.codex/skills/devops-engineer /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/retired-codex-skills/devops-engineer
mv /Users/jarekplonski/.codex/skills/docs-research /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/retired-codex-skills/docs-research
mv /Users/jarekplonski/.codex/skills/grill-me /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/retired-codex-skills/grill-me
mv /Users/jarekplonski/.codex/skills/grill-with-docs /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/retired-codex-skills/grill-with-docs
mv /Users/jarekplonski/.codex/skills/implement-plan /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/retired-codex-skills/implement-plan
mv /Users/jarekplonski/.codex/skills/onboarding-html /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/retired-codex-skills/onboarding-html
mv /Users/jarekplonski/.codex/skills/plan-for-qwen /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/retired-codex-skills/plan-for-qwen
mv /Users/jarekplonski/.codex/skills/prompt-refiner /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/retired-codex-skills/prompt-refiner
mv /Users/jarekplonski/.codex/skills/qwen-pi-implementation /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/retired-codex-skills/qwen-pi-implementation
mv /Users/jarekplonski/.codex/skills/test-runner /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/retired-codex-skills/test-runner
mv /Users/jarekplonski/.codex/skills/thoughts-research /private/tmp/codex-gpt-5.6-cleanup-2026-07-24/retired-codex-skills/thoughts-research
```

Do not use a wildcard and do not target
`/Users/jarekplonski/.codex/skills` itself.

- [ ] **Step 4: Verify system skills remain**

Run:

```bash
test -d /Users/jarekplonski/.codex/skills/.system
test -f /Users/jarekplonski/.codex/skills/.system/skill-creator/SKILL.md
test -f /Users/jarekplonski/.codex/skills/.system/openai-docs/SKILL.md
```

Expected: all commands exit `0`.

- [ ] **Step 5: Verify migrated legacy directories are gone**

Run:

```bash
for skill in codebase-research create-plan devops-engineer docs-research grill-me grill-with-docs implement-plan onboarding-html plan-for-qwen prompt-refiner qwen-pi-implementation test-runner thoughts-research; do
  test ! -e "/Users/jarekplonski/.codex/skills/$skill" || exit 1
done
```

Expected: exit `0`.

- [ ] **Step 6: Verify every retired directory is recoverable**

Run:

```bash
for skill in codebase-research create-plan devops-engineer docs-research grill-me grill-with-docs implement-plan onboarding-html plan-for-qwen prompt-refiner qwen-pi-implementation test-runner thoughts-research; do
  test -d "/private/tmp/codex-gpt-5.6-cleanup-2026-07-24/retired-codex-skills/$skill" || exit 1
done
```

Expected: exit `0`.

---

### Task 11: Restart Codex and run catalog verification

**Files:**

- Read runtime state only.

**Produces:** Proof that disabled plugins and scoped skills load as designed.

- [ ] **Step 1: Restart Codex**

Fully restart the Codex desktop app or CLI host so plugin configuration, hooks, and skill discovery reload.

- [ ] **Step 2: Verify runtime model settings**

In a fresh Codex session, run `/status`.

Expected:

- model: GPT-5.6 Sol
- reasoning: medium

- [ ] **Step 3: Verify global skill catalog outside `omg_klocki`**

Open `/skills` from `/Users/jarekplonski/Dev/Rails/moje/crap4ruby`.

Expected:

- one `grill-me`
- one `grill-with-docs`
- no Superpowers skills
- no `codex:*` Claude companion skills
- no `omg_klocki`-specific skills
- global skills such as `prompt-refiner` and Qwen/Pi remain directly selectable

- [ ] **Step 4: Verify `omg_klocki` skill catalog**

Open a fresh session rooted at `/Users/jarekplonski/Dev/elixir/omg_klocki` and inspect `/skills`.

Expected: all seven project-specific skills appear in addition to canonical global skills.

- [ ] **Step 5: Check disabled plugin hooks**

If Superpowers or Codex companion instructions still appear, inspect plugin and hook status before changing trusted hook-state records. Remove stale hook state only if runtime evidence shows a disabled plugin hook still executes.

---

### Task 12: Run representative behavior evaluation

**Files:**

- No writes expected except those explicitly requested by an evaluation prompt.

**Produces:** A pass/fail matrix for the seven evaluation tasks in the specification.

- [ ] **Step 1: Run the seven specification prompts in fresh sessions**

Use the exact prompts from `Representative Evaluation Tasks` in the specification.

- [ ] **Step 2: Record for each prompt**

Record:

- repository
- model and reasoning effort
- skills shown or invoked
- whether an unnecessary question or approval occurred
- whether Qwen/Pi was suggested
- whether any write or commit was attempted
- whether the final answer met the prompt

- [ ] **Step 3: Apply pass criteria**

Pass only if:

- unrelated skills do not appear
- explicit-only skills remain absent unless directly invoked
- no plugin conflict returns
- no commit is attempted
- prompt refinement removes redundancy
- repo-local skills are visible only in `omg_klocki`

- [ ] **Step 4: Restore from snapshot on a material regression**

If the catalog loses required skills, explicit invocation fails, or Qwen helper tests regress, stop and restore the affected files from `/private/tmp/codex-gpt-5.6-cleanup-2026-07-24`.

Do not proceed to memory evaluation.

---

### Task 13: Close out the baseline rollout

**Files:**

- Read: both repository working trees
- Preserve: rollback snapshot until user acceptance

**Produces:** Final evidence and an explicit deferred memory decision.

- [ ] **Step 1: Recheck repository changes**

Run:

```bash
git -C /Users/jarekplonski/Dev/Rails/moje/crap4ruby status --short
git -C /Users/jarekplonski/Dev/elixir/omg_klocki status --short
```

Expected:

- this planning repository contains only the plan/spec plus its pre-existing `FINDINGS.md` change
- `omg_klocki` contains its pre-existing changes plus `.agents/skills`
- no application file was changed by this cleanup

- [ ] **Step 2: Recheck memory state**

Run:

```bash
sqlite3 -readonly -header -column /Users/jarekplonski/.codex/memories_1.sqlite "SELECT COUNT(*) AS generated_memory_rows FROM stage1_outputs;"
rg -n '^\[memories\]|^memories = true' /Users/jarekplonski/.codex/config.toml
```

Expected:

- memory row count remains unchanged by this plan
- no memory enablement setting exists

- [ ] **Step 3: Report the rollout**

Report:

- configuration changes
- global and repo-local skill locations
- disabled plugins
- validation commands and exact results
- Qwen helper test result
- behavior evaluation matrix
- remaining pre-existing working-tree changes
- rollback snapshot path
- deferred memory and long-skill decisions

- [ ] **Step 4: Ask for acceptance before deleting the snapshot**

Do not delete `/private/tmp/codex-gpt-5.6-cleanup-2026-07-24` automatically. Remove it only after the user accepts the rollout and explicitly approves deletion.

---

## Self-Review

### Spec coverage

- Plugin conflicts: Tasks 2 and 11
- Reasoning baseline: Tasks 2 and 11
- Global instruction duplication: Task 3
- Duplicate and globally leaked skills: Tasks 4, 5, 10, and 11
- Prompt-refiner migration: Task 6
- Explicit invocation policies: Task 7
- Handoff and PRD defects: Task 8
- Structural and helper validation: Task 9
- Memory remains disabled: Tasks 2 and 13
- Evaluation and rollback: Tasks 1, 12, and 13

### Placeholder scan

Every implementation step names concrete files, content, commands, and expected
results. Runtime status output and test counts are verified during execution
rather than predicted.

### Safety review

- No commits are included.
- Global skill cutover uses recoverable moves in Task 10 with explicit approval and exact paths.
- Plugin caches and system skills are never edited.
- Both dirty repositories are inventoried before and after.
- A rollback snapshot precedes every mutation.
- Memory enablement is deferred.
