# Unity Skills

A collection of 9 AI-powered skills for Unity project management and development. Each skill is a structured instruction set that guides AI assistants through specific Unity workflows.

## Skills Overview

### Reference

| Skill | Description |
|-------|-------------|
| **[unity](unity/SKILL.md)** | Comprehensive Unity guide covering C# patterns, architecture, performance, rendering (URP/HDRP), DOTS/ECS, and modern Unity 6+ practices |

### Execution

| Skill | Command | Description |
|-------|---------|-------------|
| **[unity-code-gen](unity-code-gen/SKILL.md)** | `/unity-code-gen` | Generate production-ready C# code with proper patterns, conventions, and NUnit tests |
| **[unity-debug](unity-debug/SKILL.md)** | `/unity-debug` | Systematic bug diagnosis using decision trees for NullRef, physics, serialization, lifecycle issues |
| **[unity-rapid-proto](unity-rapid-proto/SKILL.md)** | `/proto` | Instant gameplay prototyping — idea to playable scene with minimal code, no architecture |
| **[unity-perf-audit](unity-perf-audit/SKILL.md)** | `/perf-audit` | Static code analysis detecting 20+ performance anti-patterns with severity scoring |
| **[unity-editor-tools](unity-editor-tools/SKILL.md)** | `/unity-editor-tools` | Create custom Editor extensions: inspectors, windows, property drawers, menu items |
| **[unity-refactor](unity-refactor/SKILL.md)** | `/unity-refactor` | Incremental, safe refactoring with code smell detection and step-by-step execution |
| **[unity-shader-gen](unity-shader-gen/SKILL.md)** | `/shader` | Generate HLSL/ShaderLab shaders with auto pipeline detection (URP/HDRP/Built-in) |
| **[unity-build-config](unity-build-config/SKILL.md)** | `/build-config` | Configure CI/CD pipelines (GitHub Actions, GitLab CI), build scripts, .gitignore, Git LFS |

## How It Works

Each skill follows a consistent structure:

```
skill-name/
└── SKILL.md    # Self-contained instruction file
```

A skill file contains:
- **YAML frontmatter** — name, description, trigger keywords
- **Step-by-step workflow** — numbered steps the AI follows
- **Templates & patterns** — reusable C# code, shader snippets, CI configs
- **Rules** — strict constraints (ALWAYS/NEVER) to ensure quality
- **Cross-references** — links to related skills for smooth workflow transitions
- **Troubleshooting** — common issues and solutions

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
                      ┌──────────────────────┼──────────────────────┐
                      v                      v                      v
              ┌──────────────┐     ┌──────────────┐      ┌──────────────┐
              │    debug     │     │ editor-tools │      │  shader-gen  │
              └──────────────┘     └──────────────┘      └──────────────┘
                      │                                         │
                      v                                         v
              ┌──────────────┐                          ┌──────────────┐
              │  perf-audit  │                          │ build-config │
              └──────────────┘                          └──────────────┘
                      │
                      v
              ┌──────────────┐
              │   refactor   │
              └──────────────┘
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

- **9 skills** (1 reference + 8 execution)
- **~5,800 lines** of structured instructions
- **6 reference files** covering architecture, C# patterns, performance, project structure, specialized topics, and workflow
- **20+ C# templates** (MonoBehaviour, ScriptableObject, Event Channels, State Machines, Object Pools, Editor tools)
- **8 shader recipes** (dissolve, outline, toon, hologram, force field, water, triplanar, vertex displacement)
- **30+ performance anti-patterns** with Grep detection rules

## License

MIT
