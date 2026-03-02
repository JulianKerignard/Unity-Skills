# Unity Skills

A collection of 15 AI-powered skills for Unity 6+ project management and development. Each skill is a structured instruction set that guides AI assistants through specific Unity workflows.

## Skills Overview

### Reference

| Skill | Description |
|-------|-------------|
| **[unity](unity/SKILL.md)** | Comprehensive Unity guide covering C# patterns, architecture, performance, rendering (URP/HDRP), DOTS/ECS, and modern Unity 6+ practices |

### Execution

| Skill | Command | Description |
|-------|---------|-------------|
| **[unity-code-gen](unity-code-gen/SKILL.md)** | `/unity-code-gen` | Generate production-ready C# code with proper patterns, conventions, and NUnit tests |
| **[unity-test](unity-test/SKILL.md)** | `/unity-test` | Generate and run Unity tests (NUnit, EditMode, PlayMode, async Awaitable) |
| **[unity-debug](unity-debug/SKILL.md)** | `/unity-debug` | Systematic bug diagnosis using decision trees for NullRef, physics, async, lifecycle issues |
| **[unity-rapid-proto](unity-rapid-proto/SKILL.md)** | `/proto` | Instant gameplay prototyping — idea to playable scene with minimal code, no architecture |
| **[unity-perf-audit](unity-perf-audit/SKILL.md)** | `/perf-audit` | Static code analysis detecting 30+ performance anti-patterns with severity scoring |
| **[unity-editor-tools](unity-editor-tools/SKILL.md)** | `/unity-editor-tools` | Create custom Editor extensions: inspectors, windows, property drawers (IMGUI + UI Toolkit) |
| **[unity-refactor](unity-refactor/SKILL.md)** | `/unity-refactor` | Incremental, safe refactoring with code smell detection and step-by-step execution |
| **[unity-shader-gen](unity-shader-gen/SKILL.md)** | `/shader` | Generate HLSL/ShaderLab shaders with auto pipeline detection (URP/HDRP/Built-in), Render Graph |
| **[unity-build-config](unity-build-config/SKILL.md)** | `/build-config` | Configure CI/CD pipelines, build scripts, Build Profiles (Unity 6+), .gitignore, Git LFS |
| **[unity-ui-toolkit](unity-ui-toolkit/SKILL.md)** | `/uitk` | Create UI with UI Toolkit (UXML + USS + C# bindings), runtime and editor UI |
| **[unity-multiplayer](unity-multiplayer/SKILL.md)** | `/netcode` | Multiplayer with Netcode for GameObjects: NetworkBehaviour, RPCs, Lobby, Relay |
| **[unity-addressables](unity-addressables/SKILL.md)** | `/addressables` | Asset loading with Addressables: async loading, groups, memory management, remote content |
| **[unity-animation](unity-animation/SKILL.md)** | `/anim` | Advanced animation: Animator, IK, Root Motion, Timeline, Playables API, Animation Rigging |
| **[unity-dots](unity-dots/SKILL.md)** | `/dots` | Data-Oriented Technology Stack: ECS, Job System, Burst Compiler for high-performance scenarios |

## How It Works

Each skill follows a consistent structure:

```
skill-name/
├── SKILL.md         # Workflow, decision tree, rules (~150-200 lines)
└── references/      # Detailed templates, patterns, recipes (optional)
    └── *.md
```

A skill file contains:
- **YAML frontmatter** — name, description, trigger keywords
- **Decision tree** — guides pattern/approach selection
- **Step-by-step workflow** — numbered steps the AI follows
- **Rules** — strict constraints (ALWAYS/NEVER) to ensure quality
- **Cross-references** — links to related skills for smooth workflow transitions
- **Troubleshooting** — common issues and solutions

Reference files (`references/*.md`) contain detailed templates, code recipes, and lookup tables loaded on demand to keep the main SKILL.md concise.

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
   │  debug   │ │  test  │ │ui-toolk│ │edit-tools│ │shader-gen│ │multiplyr │
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

## Key Features

- **No MCP dependency** — all skills work with standard file tools (Read, Write, Edit, Grep, Glob)
- **Pipeline-aware** — shader and rendering skills auto-detect URP/HDRP/Built-in
- **Cross-referenced** — each skill points to related skills for seamless workflow transitions
- **Pattern-consistent** — all skills share the same C# conventions (SO Event Channels, SerializeField, namespaces)
- **Quality-layered** — `rapid-proto` intentionally skips architecture for speed, `code-gen` enforces production patterns

## Installation

Copy the skill folders into your AI assistant's skills directory:

```bash
git clone https://github.com/JulianKerignard/Unity-Skills.git
cp -r Unity-Skills/* ~/.claude/skills/
```

Or symlink for easy updates:

```bash
ln -s $(pwd)/Unity-Skills/* ~/.claude/skills/
```

## Stats

- **15 skills** (1 reference + 14 execution)
- **~11,000 lines** of structured instructions
- **19 reference files** covering architecture, C# patterns, performance, templates, specialized topics, and workflow
- **30+ C# templates** (MonoBehaviour, ScriptableObject, Event Channels, State Machines, Object Pools, Async Awaitable, NetworkBehaviour, ISystem, Editor tools)
- **8 shader recipes** (dissolve, outline, toon, hologram, force field, water, triplanar, vertex displacement)
- **30+ performance anti-patterns** with Grep detection rules
- **Unity 6+ ready** — Awaitable async, Build Profiles, UI Toolkit [UxmlElement], Render Graph, GPU Resident Drawer, DOTS production API

## License

MIT
