# Unity Skills for AI Coding Agents

15 AI-powered skills for Unity 6+ development. Works with Claude Code, Cursor, Windsurf, Codex, Gemini CLI and any agent that supports the Skills standard.

Each skill is a structured instruction set — decision trees, step-by-step workflows, strict rules, code templates — that turns your AI assistant into a Unity expert.

## Quick Install

```bash
npx skills add JulianKerignard/Unity-Skills
```

<details>
<summary>Other installation methods</summary>

```bash
# Claude Code plugin (native)
claude plugin marketplace add JulianKerignard/Unity-Skills
claude plugin install unity-skills

# Manual clone
git clone https://github.com/JulianKerignard/Unity-Skills.git
cp -r Unity-Skills/skills/ .claude/skills/
```

</details>

## The 15 Skills

### Reference (auto-loaded)

| Skill | Triggers |
|-------|----------|
| **[unity](skills/unity/SKILL.md)** | Any Unity question — architecture, C# patterns, performance, URP/HDRP, DOTS, project structure |

### Code & Architecture

| Skill | Command | What it does |
|-------|---------|-------------|
| [unity-code-gen](skills/unity-code-gen/SKILL.md) | `/unity-code-gen` | Generate production C# + NUnit tests with SO events, state machines, async Awaitable |
| [unity-refactor](skills/unity-refactor/SKILL.md) | `/unity-refactor` | Detect code smells, plan safe incremental refactoring, execute one change at a time |
| [unity-rapid-proto](skills/unity-rapid-proto/SKILL.md) | `/proto` | Idea to playable scene in minutes — max 3 scripts, primitives only, no architecture |

### Testing & Debugging

| Skill | Command | What it does |
|-------|---------|-------------|
| [unity-test](skills/unity-test/SKILL.md) | `/unity-test` | NUnit tests — EditMode, PlayMode, async, extract testable logic from MonoBehaviours |
| [unity-debug](skills/unity-debug/SKILL.md) | `/unity-debug` | Systematic bug diagnosis with decision trees for NullRef, physics, async, lifecycle |
| [unity-perf-audit](skills/unity-perf-audit/SKILL.md) | `/perf-audit` | Static analysis for 30+ performance anti-patterns with severity scoring |

### Rendering & UI

| Skill | Command | What it does |
|-------|---------|-------------|
| [unity-shader-gen](skills/unity-shader-gen/SKILL.md) | `/shader` | HLSL/ShaderLab shaders — auto-detects URP/HDRP/Built-in, Render Graph, ShadowCaster |
| [unity-ui-toolkit](skills/unity-ui-toolkit/SKILL.md) | `/uitk` | UI Toolkit — UXML + USS + C# bindings, runtime and editor UI |
| [unity-editor-tools](skills/unity-editor-tools/SKILL.md) | `/editor` | Custom inspectors, EditorWindows, PropertyDrawers (IMGUI + UI Toolkit) |

### Systems

| Skill | Command | What it does |
|-------|---------|-------------|
| [unity-audio](skills/unity-audio/SKILL.md) | `/unity-audio` | Audio system — SFX pooling, music crossfade, AudioMixer, spatial 3D, Audio Random Container |
| [unity-2d](skills/unity-2d/SKILL.md) | `/2d` | 2D development — Tilemaps, 2D physics, Light2D, Sprite Atlas, platformer/top-down patterns |
| [unity-save](skills/unity-save/SKILL.md) | `/unity-save` | Save system — JSON/binary serialization, ISaveable, auto-save, versioning, cloud saves |
| [unity-multiplayer](skills/unity-multiplayer/SKILL.md) | `/netcode` | Netcode for GameObjects — NetworkBehaviour, RPCs, NetworkVariable, Lobby + Relay |
| [unity-addressables](skills/unity-addressables/SKILL.md) | `/addressables` | Async asset loading, groups, memory management, Resources.Load migration |
| [unity-animation](skills/unity-animation/SKILL.md) | `/anim` | Animator, IK, Root Motion, Timeline, Playables API, Animation Rigging |
| [unity-dots](skills/unity-dots/SKILL.md) | `/dots` | ECS, Job System, Burst Compiler for high-performance scenarios |

### DevOps

| Skill | Command | What it does |
|-------|---------|-------------|
| [unity-build-config](skills/unity-build-config/SKILL.md) | `/build-config` | CI/CD (GitHub Actions, GitLab CI), Build Profiles, .gitignore, Git LFS |

## How It Works

```
skills/
  unity-*/
  ├── SKILL.md         # Decision tree + workflow + rules (< 200 lines)
  └── references/      # Code templates, patterns, recipes
```

Each SKILL.md contains:
- **YAML frontmatter** with trigger keywords for automatic activation
- **Decision tree** to pick the right approach
- **Step-by-step workflow** the AI follows
- **TOUJOURS/JAMAIS rules** for quality guardrails
- **Cross-references** to related skills
- **Troubleshooting** table for common issues

## Skill Map

```
                    ┌─────────────┐
         Idea ────> │ rapid-proto │ ──── Prototype works?
                    └─────────────┘            │
                           │                   v
                           │          ┌──────────────┐
                           └────────> │   code-gen   │ ──── Production code
                                      └──────────────┘
                                             │
          ┌──────────┬──────────┬────────────┼──────────┬──────────────┐
          v          v          v            v          v              v
   ┌──────────┐ ┌────────┐ ┌────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
   │  debug   │ │  test  │ │  uitk  │ │  editor  │ │  shader  │ │ netcode  │
   └──────────┘ └────────┘ └────────┘ └──────────┘ └──────────┘ └──────────┘
        │                                                │
        v                                                v
   ┌──────────┐    ┌──────────────┐    ┌──────────┐ ┌──────────┐
   │perf-audit│    │ addressables │    │build-conf│ │   dots   │
   └──────────┘    └──────────────┘    └──────────┘ └──────────┘
        │
        v
   ┌──────────┐    ┌──────────────┐
   │ refactor │    │  animation   │
   └──────────┘    └──────────────┘
```

## Stats

- **18 skills** (1 reference + 17 execution)
- **~13,500 lines** of structured instructions across **46 files**
- **30 reference files** — templates, patterns, recipes
- **30+ C# code templates** — MonoBehaviour, SO Events, State Machines, Pools, Async Awaitable, NetworkBehaviour, ISystem, Editor tools
- **8 shader recipes** — dissolve, outline, toon, hologram, force field, water, triplanar, vertex displacement
- **30+ anti-patterns** with Grep detection rules
- **Unity 6.0 - 6.3 LTS** — Awaitable, Build Profiles, UI Toolkit `[UxmlElement]`, Render Graph, linearVelocity, Platform Toolkit

## Contributing

See [CLAUDE.md](CLAUDE.md) for the skill format specification, conventions, and validation checklist.

## License

MIT
