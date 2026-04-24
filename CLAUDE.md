# CLAUDE.md — Claude Agent Compatibility File
#
# =============================================================================
# PURPOSE
# =============================================================================
# This file exists for Claude tool compatibility.
# Claude reads CLAUDE.md at project root as its primary instruction source.
# All actual instructions live in AGENTS.md (the Single Source of Truth).
#
# DO NOT add rules here. Add all rules to AGENTS.md.
# This file is intentionally thin. Its only job is to point you to AGENTS.md.
# =============================================================================

## Reading Order

Before doing anything in this repository — before reading any code, planning
any change, or writing a single line — read these files in this exact order:

1. `AGENTS.md` (this directory) — **read all sections, cover to cover**
2. `setup/AGENTS.md` — if you are working in the `setup/` subtree
3. `ml-serving/AGENTS.md` — if you are working in the `ml-serving/` subtree

## What AGENTS.md Contains

- Project identity and mission (Section 0)
- The teaching persona you must embody (Section 1)
- Learner machine profile — 16 GB RAM, RTX 2060, Docker Desktop, WSL2 (Section 2)
- Non-negotiable engineering rules (Section 3)
- Mandatory annotation standards for every file type (Section 4)
- Directory and naming standards (Section 5)
- Repository module map — the canonical learning order (Section 6)
- Kubernetes terminology standards (Section 7)
- Local-to-enterprise translation rules (Section 8)
- Verification and debugging standards (Section 9)
- How to extend instructions (Section 10)
- Instruction hierarchy (Section 11)

## Why This Architecture

The repository uses a Single Source of Truth model:
- Adding a rule to `AGENTS.md` = that rule applies to the entire repository.
- Subproject `AGENTS.md` files add local specializations, never override.
- This file (`CLAUDE.md`) adds zero rules — it only routes Claude here.

## Enforcement

You must follow `AGENTS.md` strictly. The learner and platform owner will add
new sections to `AGENTS.md` over time. When that happens, those new rules apply
to every file in the repository from the moment they are added.
