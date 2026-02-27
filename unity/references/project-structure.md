# Unity Project Structure & Asset Organization

How to organize a Unity project so it stays navigable at 100 files and at 10,000. The structure you choose on day one will either save or cost you hundreds of hours over the project's lifetime.

## Table of Contents

1. [Folder Strategy](#1-folder-strategy)
2. [Scripts Organization](#2-scripts-organization)
3. [Art Assets](#3-art-assets)
4. [Audio Assets](#4-audio-assets)
5. [Prefabs](#5-prefabs)
6. [Scenes](#6-scenes)
7. [ScriptableObjects](#7-scriptableobjects)
8. [Special Unity Folders](#8-special-unity-folders)
9. [Asset Naming Conventions](#9-asset-naming-conventions)
10. [Asset Import Settings](#10-asset-import-settings)
11. [Third-Party & Packages](#11-third-party--packages)
12. [Scaling: Small → Medium → Large](#12-scaling-small--medium--large)

---

## 1. Folder Strategy

### Feature-Based vs Type-Based

**Type-based** groups by file type (`Scripts/`, `Textures/`, `Models/`). It seems logical at first, but when you need to work on the "Enemy" feature, you're jumping between 8 different folders. It doesn't scale.

**Feature-based** groups by game system. Everything related to "Enemy" lives together. When you add a new enemy type, you touch one folder. When you delete a feature, you delete one folder.

### Recommended Root Structure

```
Assets/
├── _Project/                   # YOUR game content (underscore pins it to top)
│   ├── Scripts/
│   ├── Prefabs/
│   ├── Scenes/
│   ├── ScriptableObjects/
│   ├── Art/
│   ├── Audio/
│   ├── Animations/
│   ├── VFX/
│   └── UI/
├── Plugins/                    # Native plugins, SDKs
├── ThirdParty/                 # Imported Unity packages & Asset Store content
├── Settings/                   # ProjectSettings symlink or render/quality/input assets
├── StreamingAssets/            # Files copied as-is to build (video, data files)
└── Editor/                     # Editor-only scripts (at root level for global Editor tools)
```

Why `_Project/`? When you import an Asset Store package, it dumps folders into `Assets/`. The underscore ensures your work is always pinned to the top and visually separated from third-party clutter.

### The Golden Rules

- **One feature = one folder.** If you can describe a folder's purpose in one phrase, it's the right size.
- **Nesting depth: 3-4 levels max.** Deeper than that and navigation becomes a chore.
- **Empty folders are clutter.** Delete them. Unity creates `.meta` files for them too.
- **No spaces in paths.** Spaces cause problems with command-line tools, scripts, and some platforms. Use PascalCase or kebab-case.

---

## 2. Scripts Organization

### By Feature Module

```
Scripts/
├── Core/
│   ├── Bootstrap.cs
│   ├── GameLoop.cs
│   ├── ServiceLocator.cs
│   └── Core.asmdef
├── Player/
│   ├── PlayerController.cs
│   ├── PlayerHealth.cs
│   ├── PlayerCombat.cs
│   ├── PlayerInput.cs
│   ├── PlayerAnimator.cs
│   └── Player.asmdef
├── Enemies/
│   ├── EnemyBase.cs
│   ├── EnemySpawner.cs
│   ├── AI/
│   │   ├── PatrolState.cs
│   │   ├── ChaseState.cs
│   │   └── AttackState.cs
│   └── Enemies.asmdef
├── Combat/
│   ├── IDamageable.cs
│   ├── DamageCalculator.cs
│   ├── Projectile.cs
│   └── Combat.asmdef
├── UI/
│   ├── Screens/
│   │   ├── MainMenuScreen.cs
│   │   ├── GameplayHUD.cs
│   │   ├── PauseScreen.cs
│   │   └── GameOverScreen.cs
│   ├── Components/
│   │   ├── HealthBar.cs
│   │   ├── DamagePopup.cs
│   │   └── ScreenManager.cs
│   └── UI.asmdef
├── Data/
│   ├── WeaponDataSO.cs
│   ├── EnemyDataSO.cs
│   ├── LevelConfigSO.cs
│   └── Data.asmdef
├── Audio/
│   ├── AudioManager.cs
│   ├── MusicPlayer.cs
│   └── Audio.asmdef
├── Save/
│   ├── SaveSystem.cs
│   ├── SaveData.cs
│   └── Save.asmdef
└── Utils/
    ├── Extensions/
    │   ├── VectorExtensions.cs
    │   ├── TransformExtensions.cs
    │   └── CollectionExtensions.cs
    ├── Helpers/
    │   ├── Timer.cs
    │   ├── ObjectPool.cs
    │   └── Singleton.cs
    ├── Constants.cs
    └── Utils.asmdef
```

### Assembly Definition Rules

Every feature module gets its own `.asmdef`. This gives you:
- **Faster compilation** — changing a UI script only recompiles `UI.asmdef`, not the whole project
- **Enforced boundaries** — a module can only use what it explicitly references
- **Cleaner dependencies** — forces you to think about what depends on what

Dependency flow should be a tree, not a web:

```
Utils ← Core ← Player
                ├── Combat
                ├── Enemies
                ├── UI
                └── Audio
```

`Utils` depends on nothing. `Core` depends on `Utils`. Feature modules depend on `Core` (and sometimes on each other, but keep that minimal). Circular dependencies between `.asmdef` files are a compile error — that's a feature, not a bug.

### Where to Put Interfaces

Interfaces that are shared across modules go in `Core/` or `Data/`:
```
Core/
├── Interfaces/
│   ├── IDamageable.cs
│   ├── IInteractable.cs
│   └── ISaveable.cs
```

This way any module can reference `Core` to implement the interface without depending on the module that consumes it.

---

## 3. Art Assets

```
Art/
├── Characters/
│   ├── Player/
│   │   ├── Player_Model.fbx
│   │   ├── Player_Diffuse.png
│   │   ├── Player_Normal.png
│   │   ├── Player_Material.mat
│   │   └── Player_Avatar.mask
│   └── Goblin/
│       ├── Goblin_Model.fbx
│       ├── Goblin_Diffuse.png
│       └── Goblin_Material.mat
├── Environment/
│   ├── Trees/
│   ├── Rocks/
│   ├── Buildings/
│   └── Props/
├── Shared/
│   ├── Materials/         # Reusable materials (water, glass, default)
│   ├── Textures/          # Shared textures (noise, gradient, ramp)
│   └── Shaders/           # Custom shaders, shader graphs
└── VFX/
    ├── Particles/
    ├── Textures/          # Particle textures, flipbooks
    └── Materials/
```

### Key Principles

**Keep model + textures + material together.** When you work on the Goblin, everything is in one place. The alternative (all FBX in `Models/`, all PNG in `Textures/`) means constant folder-hopping.

**Shared assets go in `Shared/`.** Materials used by multiple objects (like a default grid material or a water shader) live in `Art/Shared/Materials/`, not duplicated in each character folder.

**Source files stay out of the project.** Photoshop (`.psd`), Blender (`.blend`), Substance files — keep them in a separate `_SourceArt/` folder (Git LFS tracked) or outside the Unity project entirely. Unity imports them, which balloons project size. Export to `.png`/`.fbx` and import those.

---

## 4. Audio Assets

```
Audio/
├── SFX/
│   ├── Player/
│   │   ├── Footstep_Grass_01.wav
│   │   ├── Footstep_Grass_02.wav
│   │   ├── Sword_Swing_01.wav
│   │   └── Sword_Hit_01.wav
│   ├── Enemies/
│   │   ├── Goblin_Hurt_01.wav
│   │   └── Goblin_Death_01.wav
│   ├── UI/
│   │   ├── Button_Click.wav
│   │   └── Menu_Open.wav
│   └── Environment/
│       ├── Wind_Loop.wav
│       └── Water_Stream.wav
├── Music/
│   ├── MainTheme.ogg
│   ├── BattleMusic.ogg
│   └── GameOver.ogg
└── Ambience/
    ├── Forest_Day.ogg
    └── Dungeon.ogg
```

### Naming Convention for Audio

Use the pattern: `Category_Variant_##`

- `Footstep_Grass_01`, `Footstep_Grass_02` — numbered variants for randomization
- `Sword_Swing_01`, `Sword_Hit_Metal_01`
- `Music_Battle`, `Music_MainMenu`
- `Ambience_Forest_Day`, `Ambience_Cave`

### Format Rules

| Usage | Format | Why |
|---|---|---|
| Short SFX (< 5s) | `.wav` or `.ogg` | Quality matters, file size is small |
| Music / Ambience | `.ogg` | Compressed, streamable, good quality |
| Mobile SFX | `.ogg` (low quality) | Smaller file size |

In Unity import settings:
- SFX → **Compressed In Memory**, Vorbis, Quality 70-100%
- Music → **Streaming**, Vorbis, Quality 50-70%
- 3D positioned sounds → **Force Mono** (stereo doubles memory with no spatial benefit)

---

## 5. Prefabs

```
Prefabs/
├── Characters/
│   ├── Player.prefab
│   ├── EnemyGoblin.prefab
│   └── EnemySkeleton.prefab
├── Environment/
│   ├── Tree_Oak.prefab
│   ├── Rock_Large.prefab
│   └── Chest_Wooden.prefab
├── Projectiles/
│   ├── Arrow.prefab
│   └── Fireball.prefab
├── VFX/
│   ├── HitSpark.prefab
│   ├── Explosion.prefab
│   └── HealEffect.prefab
└── UI/
    ├── DamagePopup.prefab
    └── ItemSlot.prefab
```

### Prefab Best Practices

**Prefab Variants for variations.** A `EnemyGoblin_Elite.prefab` variant overrides only what's different (more health, different material) while inheriting the base structure. Changes to the base automatically propagate.

**Nested Prefabs for composition.** A vehicle prefab contains nested wheel prefabs. Editing the wheel prefab updates all vehicles.

**Never modify a prefab instance in a scene and forget to "Apply".** Unpplied overrides (blue text in Inspector) are scene-local — they don't carry to other scenes using the same prefab.

**One prefab per file.** Don't put a prefab inside a prefab that has no reason to exist independently. Keep the prefab hierarchy flat (max 2-3 levels of nesting).

---

## 6. Scenes

```
Scenes/
├── _Bootstrap.unity              # Initialization (Build Settings index 0)
├── _Persistent.unity             # Managers that survive scene loads
├── Menus/
│   ├── MainMenu.unity
│   ├── Settings.unity
│   └── Credits.unity
├── Levels/
│   ├── Level_01_Forest.unity
│   ├── Level_02_Cave.unity
│   └── Level_03_Castle.unity
├── UI/
│   ├── HUD.unity                 # Additively loaded during gameplay
│   └── PauseMenu.unity
├── Testing/
│   ├── TestScene_Combat.unity    # Developer-only test scenes
│   └── TestScene_Physics.unity
└── Loading/
    └── LoadingScreen.unity
```

### Scene Rules

**Bootstrap scene is always index 0.** It initializes services, sets up DontDestroyOnLoad objects, then loads the first real scene additively.

**Separate persistent from disposable.** Managers (audio, input, event system) live in a persistent scene that's never unloaded. Gameplay content lives in scenes that get loaded/unloaded.

**Test scenes for developers.** Create isolated scenes for testing specific systems (combat, physics, UI). They're invaluable for debugging and don't ship in the final build.

**Name scenes descriptively.** `Level_01_Forest` is better than `Level1` — you know what it is at a glance. Use the `_##_` numbering to preserve order in the file browser.

---

## 7. ScriptableObjects

Store SO *class definitions* with your Scripts. Store SO *instances* (the data assets) in a dedicated folder:

```
ScriptableObjects/
├── Weapons/
│   ├── Sword_Iron.asset
│   ├── Sword_Fire.asset
│   ├── Bow_Short.asset
│   └── Staff_Ice.asset
├── Enemies/
│   ├── Goblin_Base.asset
│   ├── Goblin_Elite.asset
│   └── Skeleton_Archer.asset
├── Events/
│   ├── OnPlayerDied.asset
│   ├── OnEnemyKilled.asset
│   ├── OnLevelCompleted.asset
│   └── OnScoreChanged.asset
├── Config/
│   ├── GameSettings.asset
│   ├── DifficultyEasy.asset
│   └── DifficultyHard.asset
└── Variables/
    ├── PlayerHealth.asset
    ├── PlayerScore.asset
    └── CurrentLevel.asset
```

This separation matters because SO class definitions change rarely (they're code), while SO instances are edited constantly by designers. Keeping instances in their own tree makes them easy to find and manage.

---

## 8. Special Unity Folders

Unity gives special behavior to certain folder names. Understanding them prevents surprises:

| Folder | Behavior | Recommendation |
|---|---|---|
| `Resources/` | Everything inside is loaded into memory at app startup, and accessible via `Resources.Load()` | Avoid for production. Use Addressables instead. Keep at most a few tiny essential assets here (like a loading spinner). |
| `StreamingAssets/` | Copied byte-for-byte into the build. Accessible at runtime via `Application.streamingAssetsPath` | Use for data files you need to read as raw files (JSON configs, video, SQLite databases). |
| `Editor/` | Only compiled in the Editor, stripped from builds | Put all editor-only scripts (custom inspectors, tools, menu items) here. Can exist at any depth. |
| `Plugins/` | Native plugins (.dll, .so, .dylib) | Keep third-party native SDKs here. |
| `Gizmos/` | Icons used by `Gizmos.DrawIcon()` | Only for custom gizmo icons in the Editor. |
| `Editor Default Resources/` | Assets loadable only in Editor via `EditorGUIUtility.Load()` | Rarely needed. |

### The `Resources/` Trap

This is the most common structural mistake in Unity projects. When `Resources/` exists:
1. Unity scans it at startup and builds an index of every asset inside
2. All those assets are included in the build, even if unused
3. `Resources.Load()` uses string paths — typos fail silently at runtime

For small projects (game jams), it's fine. For anything shipping to users, migrate to Addressables, which give you:
- Async loading
- Memory management (load/unload on demand)
- Remote content delivery (DLC, hot patches)
- Build time asset management (only include what's referenced)

---

## 9. Asset Naming Conventions

### General Pattern

`Type_Name_Variant_##`

| Asset Type | Convention | Examples |
|---|---|---|
| Models | PascalCase | `Tree_Oak.fbx`, `Rock_Large.fbx` |
| Textures | `Name_Type` | `Goblin_Diffuse.png`, `Goblin_Normal.png`, `Goblin_Mask.png` |
| Materials | PascalCase | `Goblin_Material.mat`, `Water_Stylized.mat` |
| Animations | `Character_Action` | `Player_Run.anim`, `Player_Attack_01.anim` |
| Audio | `Category_Variant_##` | `Footstep_Grass_01.wav`, `Music_Battle.ogg` |
| Prefabs | PascalCase | `EnemyGoblin.prefab`, `Projectile_Arrow.prefab` |
| Scenes | PascalCase with number | `Level_01_Forest.unity`, `MainMenu.unity` |
| ScriptableObjects | PascalCase | `Sword_Iron.asset`, `OnPlayerDied.asset` |
| Shaders | PascalCase | `Toon_Outline.shader`, `Water_Surface.shadergraph` |

### Texture Suffixes

| Suffix | Map Type |
|---|---|
| `_Diffuse` or `_Albedo` | Base color |
| `_Normal` | Normal map |
| `_Mask` | Channel-packed mask (R=metallic, G=AO, B=detail, A=smoothness) |
| `_Emission` | Emission map |
| `_Height` | Height/displacement |
| `_AO` | Ambient occlusion (if standalone) |

### What to Avoid

- **Spaces in file names** — causes issues with CLI tools and some platforms
- **Special characters** (`&`, `#`, `@`) — encoding problems
- **Extremely long paths** — Windows has a 260-character path limit
- **Generic names** — `Texture1.png`, `Material.mat`, `Script.cs` are impossible to find later
- **Inconsistent casing** — pick one convention and enforce it

---

## 10. Asset Import Settings

Asset import settings are just as important as the assets themselves. Wrong settings silently waste memory and build size.

### Textures

| Setting | 3D Objects | UI Sprites | Normal Maps |
|---|---|---|---|
| Texture Type | Default | Sprite (2D and UI) | Normal Map |
| sRGB | ✅ On | ✅ On | ❌ Off |
| Generate Mipmaps | ✅ On (saves GPU when far) | ❌ Off (always viewed at full size) | ✅ On |
| Max Size | Match source (often 1024 or 2048) | Match UI target size | Match diffuse |
| Compression | Platform-appropriate (see below) | Platform-appropriate | Platform-appropriate |
| Read/Write | ❌ Off (doubles memory!) | ❌ Off | ❌ Off |

Platform compression:
- **Mobile**: ASTC (best quality/size ratio, universal on modern devices)
- **PC/Console**: DXT5 / BC7 (BC7 is higher quality)
- **WebGL**: DXT (no ASTC support on all browsers)

**Read/Write Enabled** doubles the texture memory because Unity keeps a CPU copy alongside the GPU copy. Only enable it if you need to read pixel data at runtime (e.g., for procedural modification).

### Models (FBX)

| Setting | Recommendation | Why |
|---|---|---|
| Scale Factor | 1 (model in meters) | Unity unit = 1 meter, matching avoids surprises |
| Import Normals | Import | Use model's normals unless you need Unity to recalculate |
| Import BlendShapes | Only if used | Each blend shape adds memory |
| Read/Write | ❌ Off | Same as textures — doubles mesh memory |
| Mesh Compression | Medium or High | Reduces build size, small quality cost |
| Generate Colliders | ❌ Off | Create colliders manually with primitives |

### Audio

| Setting | SFX (short) | Music / Ambience (long) |
|---|---|---|
| Load Type | Compressed In Memory | Streaming |
| Compression | Vorbis, Quality 70-100% | Vorbis, Quality 50-70% |
| Sample Rate | Preserve | Optimize (or 22050 Hz on mobile) |
| Force Mono | ✅ for 3D sounds | ❌ for stereo music |

---

## 11. Third-Party & Packages

### Imported Assets

```
ThirdParty/
├── DOTween/
├── TextMeshPro/          # (if not via Package Manager)
├── Cinemachine/          # (if not via Package Manager)
└── YourFavoritePlugin/
```

Keep third-party assets isolated. Reasons:
- Easy to update — delete the folder, reimport
- Clear ownership — you know what's yours and what's not
- Git diffs — third-party changes don't pollute your commit history

Prefer **Package Manager** packages over Asset Store imports when available — they're managed separately and don't clutter your Assets folder.

### .unitypackage Management

When you import a `.unitypackage`, always import into a dedicated folder. Never let it scatter files across your project. If it does, reorganize immediately.

---

## 12. Scaling: Small → Medium → Large

### Small Project (Game Jam, Prototype)

Flat structure is fine. Don't over-organize:

```
Assets/
├── Scripts/
├── Prefabs/
├── Scenes/
├── Art/
└── Audio/
```

### Medium Project (Indie, 3-6 Month Dev)

Feature modules, Assembly Definitions, ScriptableObject architecture:

```
Assets/
├── _Project/
│   ├── Scripts/     (feature-based with .asmdef per module)
│   ├── Prefabs/     (categorized)
│   ├── Scenes/      (bootstrap + levels + UI)
│   ├── ScriptableObjects/
│   ├── Art/         (character/environment split)
│   └── Audio/       (SFX/Music/Ambience)
├── ThirdParty/
└── Settings/
```

### Large Project (Studio, 12+ Month, Live Service)

Addressables, strict module boundaries, dedicated build pipeline:

```
Assets/
├── _Project/
│   ├── Modules/                    # Each module is self-contained
│   │   ├── Core/
│   │   ├── Player/
│   │   ├── Combat/
│   │   ├── Inventory/
│   │   ├── Quests/
│   │   ├── Multiplayer/
│   │   └── [Module]/
│   │       ├── Scripts/
│   │       ├── Prefabs/
│   │       ├── Art/
│   │       ├── ScriptableObjects/
│   │       └── [Module].asmdef
│   ├── Scenes/
│   └── SharedAssets/               # Cross-module shared resources
├── AddressableAssetsData/
├── ThirdParty/
└── Settings/
```

At this scale, each module contains *everything* it needs (scripts, prefabs, art, SOs). This enables:
- **Parallel team work** — different teams own different modules
- **Addressable groups per module** — load/unload features independently
- **Feature toggles** — disable a module by removing its Addressable group
- **Clean dependency tracking** — .asmdef enforces module boundaries
