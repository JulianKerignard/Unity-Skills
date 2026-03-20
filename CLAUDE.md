# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A collection of 15 AI-powered skills for Unity 6+ development. Each skill is a structured instruction set (not executable code) that guides AI assistants through specific Unity workflows. There is no build system, no tests, no runtime — only Markdown files.

## Repository Structure

```
.claude-plugin/
  plugin.json           # Plugin manifest — enables `claude plugin install`

skills/
  unity/                # Reference skill (loaded for any Unity question)
    SKILL.md            # Entry point (~330L) — architecture, patterns, decisions
    references/         # Deep-dive reference files
      architecture.md   # Patterns: SO events, state machines, service locator, MVP, UITK, Cinemachine
      csharp-patterns.md # C# conventions, lifecycle, async Awaitable, C# 9 features
      performance.md    # CPU/GPU/memory budgets, profiling, mobile targets
      project-structure.md # Folder organization, naming, import settings, asmdef
      specialized.md    # Animation, 2D, Shader/VFX Graph, physics, AI/Inference Engine
      workflow.md       # Git, testing, CI/CD, Build Profiles

  unity-<name>/         # 14 execution skills (one per workflow)
    SKILL.md            # Workflow entry (< 200L): decision tree, steps, rules
    references/         # Templates, patterns, recipes loaded on demand
```

## Installation

```bash
# npx (une commande, multi-agent compatible)
npx skills add JulianKerignard/Unity-Skills

# ou plugin natif Claude Code
claude plugin marketplace add JulianKerignard/Unity-Skills
claude plugin install unity-skills
```

## Skill Architecture

Every SKILL.md follows a strict format:
1. **YAML frontmatter** — `name` (Title Case), `description` (single line with trigger keywords)
2. **Ce que fait cette skill** — one-paragraph summary
3. **Prerequis** — what's needed
4. **Demarrage rapide** — 3-5 numbered steps
5. **Arbre de decision** — guides pattern/approach selection (ASCII or table)
6. **Guide etape par etape** — detailed numbered steps
7. **Regles strictes** — TOUJOURS/JAMAIS constraints
8. **Skills connexes** — cross-references to related skills (bidirectional)
9. **Troubleshooting** — table of common issues/solutions

## Key Conventions

- **Language**: All skill content is written in French. Technical terms and code identifiers stay in English.
- **Target**: Unity 6.x (6.0–6.3 LTS). APIs reference Unity 6+ (`Awaitable`, `linearVelocity`, `[UxmlElement]`, Build Profiles, Render Graph, `Object.InstantiateAsync`).
- **Size limits**: SKILL.md < 200 lines. References files can be longer but aim for < 350 lines each.
- **Cross-references**: Use skill command names (`/unity-code-gen`, `/uitk`, `/dots`) and always maintain bidirectional links between related skills.
- **No code execution**: Skills are pure documentation. They don't import packages or run anything — they instruct an AI on what to do.

## The 15 Skills

| Skill | Command | Type |
|-------|---------|------|
| `skills/unity/` | (auto-loaded) | Reference — comprehensive Unity guide |
| `skills/unity-code-gen/` | `/unity-code-gen` | Generate production C# + NUnit tests |
| `skills/unity-test/` | `/test` | NUnit tests (EditMode, PlayMode, async) |
| `skills/unity-debug/` | `/debug` | Systematic bug diagnosis with decision trees |
| `skills/unity-rapid-proto/` | `/proto` | Instant gameplay prototyping |
| `skills/unity-perf-audit/` | `/perf-audit` | Static code analysis for 30+ anti-patterns |
| `skills/unity-editor-tools/` | `/editor` | Custom inspectors, windows, drawers (IMGUI + UITK) |
| `skills/unity-refactor/` | `/unity-refactor` | Safe incremental refactoring |
| `skills/unity-shader-gen/` | `/shader` | HLSL/ShaderLab shaders (URP/HDRP/Built-in) |
| `skills/unity-build-config/` | `/build-config` | CI/CD, build scripts, Build Profiles |
| `skills/unity-ui-toolkit/` | `/uitk` | UI Toolkit (UXML + USS + C# bindings) |
| `skills/unity-multiplayer/` | `/netcode` | Netcode for GameObjects, Lobby, Relay |
| `skills/unity-addressables/` | `/addressables` | Async asset loading, memory management |
| `skills/unity-animation/` | `/anim` | Animator, IK, Timeline, Playables API |
| `skills/unity-dots/` | `/dots` | ECS, Job System, Burst Compiler |

## Editing Skills

When modifying or adding skills:

- **Verify YAML frontmatter**: `name` in Title Case, `description` is a single line with all trigger keywords
- **No trigger overlap**: Each trigger keyword should map to exactly one skill. Grep across all SKILL.md files to verify.
- **Update cross-references**: If skill A references skill B, check that B references A back where relevant.
- **Update README.md**: The root README contains the skill table, skill map diagram, and stats — keep them in sync.
- **Use Context7 MCP** to verify Unity API accuracy before writing patterns or templates that reference specific Unity APIs.
- **French grammar**: Skill content is in French but avoid accented characters in code identifiers.

## Validation Checklist

After any change, verify:
1. Each SKILL.md has all 9 standard sections listed above
2. No SKILL.md exceeds ~200 lines (workflow should be concise, details go to `references/`)
3. Cross-references are bidirectional
4. No stale Unity API references (grep for `Unity 2020`, `Unity 2021`, deprecated APIs)
5. README.md skill count and stats match reality
