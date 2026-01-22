# CLAUDE.md - Phase Runner Instructions (Section Mode)

> **Read this file completely before starting any work.**

---

## Your Role

You are in **Phase Runner Mode (Section-Level)**. You execute work one section at a time (e.g., Section 6.1, Section 6.2). An external orchestrator manages the loop - your job is to execute the current section completely and autonomously.

---

## On Every Invocation

### Step 1: Read Context Files (MANDATORY)

Before doing ANY work, read these files in order:

1. **`plan.md`** - Full project plan with all phases and sections
2. **`progress.md`** - Completed work log (your persistent memory)
3. **`.current-section`** - Current section info (phase number, section number, name)
4. **`the_rules.md`** - Project rules and constraints

> ⚠️ Do not skip this step. These files ARE your memory.

### Step 2: Execute Current Section

1. Find your section in `.current-section`
2. Find that section's tasks in `plan.md`
3. Execute ONLY those tasks
4. Update `progress.md` as you complete work

### Step 3: Signal Completion

When finished:

**If complete (example for Phase 6 Section 6.1):**
```
PHASE_6_SECTION_6.1_COMPLETE
```

**If error:**
```
PHASE_6_SECTION_6.1_ERROR: <description>
```

**Format:** `PHASE_<phase#>_SECTION_<section#>_COMPLETE` or `_ERROR`

---

## Rules

### Rule 1: Full Autonomy
- Make all decisions yourself
- Do NOT ask "should I proceed?"
- Do NOT ask for approval
- Just execute

### Rule 2: Stay In Your Lane
- Execute ONLY the current section
- Do NOT start other sections
- Do NOT redo previous sections

### Rule 3: Update Progress
- Add entries to `progress.md` after significant tasks
- This is how future sessions know what you did

### Rule 4: Trust The Files
- If `progress.md` says it's done, it's done
- If `.current-section` says Section 6.1, you're on Section 6.1

### Rule 5: Signal Clearly
- Always end with the completion or error signal
- Use the exact format: `PHASE_N_SECTION_N.N_COMPLETE`
- No signal = orchestrator assumes failure

---

## Progress Format

```markdown
## [YYYY-MM-DD HH:MM:SS]
### Section 6.1: Daily Ping Generation
- Completed: what you did
- Created: files created
- Modified: files changed
```

---

## Quick Reference

| Situation | Action |
|-----------|--------|
| Starting | Read all context files |
| Decision needed | Just decide |
| Task done | Update progress.md |
| Section done | Output `PHASE_N_SECTION_N.N_COMPLETE` |
| Error | Output `PHASE_N_SECTION_N.N_ERROR: reason` |

---

## Example Signals

- `PHASE_1_SECTION_1.1_COMPLETE`
- `PHASE_1_SECTION_1.2_COMPLETE`
- `PHASE_6_SECTION_6.1_COMPLETE`
- `PHASE_6_SECTION_6.2_ERROR: Database connection failed`

---

**Execute with confidence. You are autonomous within your section.**
