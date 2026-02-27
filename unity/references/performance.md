# Unity Performance Optimization

How to find and fix performance problems in Unity. The key discipline: profile first, optimize second. Guessing at bottlenecks wastes time.

## Table of Contents

1. [Profiling Workflow](#1-profiling-workflow)
2. [CPU Optimization](#2-cpu-optimization)
3. [GPU & Rendering](#3-gpu--rendering)
4. [Unity 6 Performance Features](#4-unity-6-performance-features)
5. [Memory Management](#5-memory-management)
6. [Physics](#6-physics)
7. [Mobile Targets](#7-mobile-targets)
8. [Build Size](#8-build-size)

---

## 1. Profiling Workflow

### Tools

| Tool | Shows | Use When |
|---|---|---|
| **Unity Profiler** | CPU, GPU, Memory per-frame | First stop for any perf issue |
| **Frame Debugger** | Every draw call in a frame | Too many draw calls / batching issues |
| **Memory Profiler** | Heap snapshots, native memory | Leaks, high allocation |
| **Profile Analyzer** | Statistical comparison of captures | Validating before/after results |
| **RenderDoc** | GPU shader cost, overdraw | GPU-bound rendering |

### Process

1. Build a **Development Build** with "Autoconnect Profiler" enabled — Editor performance is misleading because the Editor itself consumes significant CPU/GPU
2. Let the scene warm up for a few seconds, then capture
3. Check the **Timeline view** for the longest frame sections
4. Look at the **GC.Alloc** column — any allocation inside an Update-type method is a red flag
5. Enable **Deep Profile** for function-level detail when needed (it slows everything down significantly, so use it surgically)

### Frame Budget

| Target | Budget/frame | Typical Use |
|---|---|---|
| 30 fps | 33.3 ms | Mobile, Switch |
| 60 fps | 16.6 ms | PC, consoles |
| 90 fps | 11.1 ms | VR minimum |
| 120 fps | 8.3 ms | Competitive PC |

---

## 2. CPU Optimization

### Don't Do Expensive Work Every Frame

The most impactful CPU optimization is simply doing less per frame. Many operations don't need to run at 60Hz.

```csharp
// Expensive operation staggered to 4 times per second
private float _checkTimer;

void Update()
{
    _checkTimer += Time.deltaTime;
    if (_checkTimer >= 0.25f)
    {
        _checkTimer = 0f;
        CheckForEnemiesInRange();  // expensive, but now runs 4x/sec not 60x
    }
}
```

Even better: replace polling with events. If health only changes when damage is dealt, subscribe to the damage event instead of checking health every frame.

### Avoid GC Allocations in Hot Paths

The garbage collector pauses the entire game when it runs. Allocations in per-frame code are the primary cause.

```csharp
// These all allocate:
var enemies = FindObjectsOfType<Enemy>();     // new array
string s = "HP: " + _hp;                      // new string
var list = new List<int>();                    // new list
var result = enemies.Where(e => e.IsAlive);   // LINQ enumerator + delegate

// Zero-alloc alternatives:
private readonly StringBuilder _sb = new(64);
private readonly List<int> _reusable = new();
private readonly RaycastHit[] _hitBuffer = new RaycastHit[16];

void Update()
{
    _sb.Clear().Append("HP: ").Append(_hp);     // reuse StringBuilder
    _reusable.Clear();                           // reuse list
}
```

### Cache Hash IDs

String-based lookups are slow. Unity provides hash functions that let you look up by int instead:

```csharp
// Cache these as statics — they never change
private static readonly int SpeedHash = Animator.StringToHash("Speed");
private static readonly int MainTexId = Shader.PropertyToID("_MainTex");

void Update()
{
    _animator.SetFloat(SpeedHash, _velocity.magnitude);  // int lookup
}
```

### LINQ: Fine in Init, Risky in Loops

LINQ is readable but allocates enumerators and delegates. It's fine in `Start()` or event handlers that fire rarely. In `Update()` or tight loops, use manual iteration:

```csharp
// Manual loop — zero allocations, uses SqrMagnitude to avoid sqrt
Enemy closest = null;
float closestSqr = float.MaxValue;
for (int i = 0; i < _enemies.Count; i++)
{
    if (!_enemies[i].IsAlive) continue;
    float sqr = (_enemies[i].Position - _playerPos).sqrMagnitude;
    if (sqr < closestSqr) { closestSqr = sqr; closest = _enemies[i]; }
}
```

### Jobs + Burst (Heavy Lifting)

For CPU-bound work that benefits from multithreading (distance checks on 1000+ entities, procedural generation, pathfinding), use Unity's Job System with Burst compilation:

```csharp
[BurstCompile]
public struct DistanceJob : IJobParallelFor
{
    [ReadOnly] public NativeArray<float3> Positions;
    [ReadOnly] public float3 Origin;
    [ReadOnly] public float Range;
    public NativeArray<bool> InRange;

    public void Execute(int i)
    {
        InRange[i] = math.distance(Positions[i], Origin) <= Range;
    }
}
```

Remember to use `Unity.Mathematics` types (`float3`, `quaternion`) instead of `UnityEngine` types — Burst can't compile the latter.

---

## 3. GPU & Rendering

### Reducing Draw Calls

Every draw call has CPU overhead. Fewer draw calls = more headroom.

| Technique | When | How |
|---|---|---|
| **SRP Batcher** | Same shader, different materials | On by default in URP/HDRP |
| **Static Batching** | Non-moving objects | Check "Static" in Inspector |
| **GPU Instancing** | Many copies of same mesh | Enable on Material |
| **Texture Atlasing** | Many small textures | Combine into sprite atlas |

### Shaders

- Minimize variant count: use `shader_feature` (strips unused) over `multi_compile` (keeps all)
- On mobile: use `half` precision where possible, avoid `discard`/`clip` (breaks early-Z rejection)
- Strip unused variants in Player Settings → Graphics

### Lighting

Lighting is often the biggest rendering cost. Bake everything you can:
- **Lightmaps** for static objects
- **Light Probes** for dynamic objects receiving baked light
- **Reflection Probes** (baked) instead of real-time planar reflections
- Limit **real-time shadow distance** and cascade count (2 cascades is enough on mobile)

### LOD Groups

Reducing polygon count with distance is one of the most effective GPU optimizations. Set up LOD Groups on any mesh over ~1000 triangles:

```
LOD0 (< 10m)  — Full detail
LOD1 (10-30m) — ~50% triangles
LOD2 (30-60m) — ~25% triangles
Culled (60m+) — Not rendered
```

### Overdraw

Drawing the same pixel multiple times (overdraw) is the silent killer on mobile. Use the Scene > Overdraw visualization to spot it:
- Prefer opaque materials (transparent objects cause overdraw by definition)
- Reduce particle effect layering
- Sort transparent objects back-to-front

---

## 4. Unity 6 Performance Features

### GPU Resident Drawer

Unity 6 introduit le GPU Resident Drawer qui maintient les donnees de mesh persistantes sur le GPU, reduisant drastiquement les draw calls pour les objets statiques et LODs.

**Activation :** Project Settings > Graphics > GPU Resident Drawer > Enabled

**Impact :**
- Reduction automatique des draw calls sans intervention manuelle
- Particulierement efficace pour les scenes avec beaucoup de meshes statiques
- Compatible avec LOD Groups — le GPU gere les transitions
- Rend les optimisations manuelles de batching (static batching, manual mesh combining) moins critiques

**Quand c'est pertinent :** Scenes avec 1000+ objets statiques, environnements ouverts, levels proceduraux.

### Object.InstantiateAsync (Unity 6)

Alternative asynchrone a `Instantiate()` pour les prefabs complexes, evite les spikes CPU :

```csharp
// Avant — synchrone, cause un spike si le prefab est lourd
var go = Instantiate(complexPrefab, position, rotation);

// Apres — asynchrone, repartit le travail sur plusieurs frames
var op = Object.InstantiateAsync(complexPrefab, position, rotation);
await op; // ou check op.isDone chaque frame
var go = op.Result[0];
```

**Quand l'utiliser :**
- Prefabs avec beaucoup de composants ou d'enfants
- Spawning de groupes d'objets (enemies, items)
- Scenes de loading ou transitions

**Quand NE PAS l'utiliser :**
- Prefabs simples (1-2 composants) — le overhead async n'en vaut pas la peine
- Besoin d'un resultat immediatement dans la meme frame

### Mesh LOD Auto-Generation (Unity 6.3+)

Unity 6.3 introduit la generation automatique de LODs pour les meshes importes :

- Configurable dans l'Import Settings du mesh
- Genere les niveaux de LOD automatiquement (reduction de polygones)
- Reduit le travail artiste pour la creation de LODs manuels
- Cible : projets avec beaucoup de meshes sans LODs existants

---

## 5. Memory Management

### Texture Memory Reference

| Resolution | Uncompressed RGBA32 | ASTC 6x6 (Mobile) | DXT5/BC3 (PC) |
|---|---|---|---|
| 512² | 1 MB | ~170 KB | 256 KB |
| 1024² | 4 MB | ~680 KB | 1 MB |
| 2048² | 16 MB | ~2.7 MB | 4 MB |
| 4096² | 64 MB | ~10.7 MB | 16 MB |

**Compression is non-negotiable.** A single uncompressed 4K texture uses 64 MB — that's the entire memory budget of a low-end phone. Use ASTC on mobile, DXT/BC on PC. Enable mipmaps for 3D objects (saves memory when objects are far away), disable for UI (always viewed at full size).

### Audio Memory

- **Compressed In Memory** for short SFX (< 5 seconds)
- **Streaming** for music and ambient loops
- **Mono** for 3D positional audio (stereo doubles memory for no spatial benefit)
- Vorbis for general use, ADPCM for low-latency SFX

### Leak Prevention

The two most common leak sources:

**1. Event subscriptions not cleaned up:**
```csharp
private void OnEnable()  => GameEvents.OnLevelEnd += HandleEnd;
private void OnDisable() => GameEvents.OnLevelEnd -= HandleEnd;
// If you forget OnDisable, the dead object stays referenced and can't be GC'd
```

**2. Addressable handles not released:**
```csharp
private AsyncOperationHandle<GameObject> _handle;

private void OnDestroy()
{
    if (_handle.IsValid()) Addressables.Release(_handle);
}
```

---

## 6. Physics

### Layer Collision Matrix

In **Edit > Project Settings > Physics > Layer Collision Matrix**, disable every pair of layers that never needs to interact. This is free performance — every unchecked box is an entire category of collision tests that never runs.

### Collider Cost

| Type | Cost | Use For |
|---|---|---|
| Sphere | Cheapest | Characters, projectiles, triggers |
| Capsule | Cheap | Characters, limbs |
| Box | Cheap | Walls, platforms, pickups |
| Mesh (Convex) | Moderate | Simple irregular shapes |
| Mesh (Concave) | Expensive | Static environment only |

Prefer primitive colliders. For complex shapes, use compound colliders (multiple primitives as children) instead of a single mesh collider.

### Non-Allocating Raycasts

```csharp
private readonly RaycastHit[] _hits = new RaycastHit[16];
private readonly Collider[] _overlaps = new Collider[32];

void CheckArea()
{
    int count = Physics.OverlapSphereNonAlloc(
        transform.position, _radius, _overlaps, _enemyLayer);

    for (int i = 0; i < count; i++)
        ProcessTarget(_overlaps[i]);
}
```

The `NonAlloc` variants reuse a pre-allocated buffer instead of creating a new array every call. This matters a lot when you do spatial queries frequently.

---

## 7. Mobile Targets

### Budgets by Device Tier

| Tier | Examples | FPS | Scene Polys | Draw Calls |
|---|---|---|---|---|
| Low | iPhone 8, Galaxy S8 | 30 | < 100K | < 100 |
| Mid | iPhone 12, Pixel 6 | 30-60 | < 300K | < 150 |
| High | iPhone 15, Galaxy S24 | 60 | < 500K | < 200 |

### Budgets actualises (devices 2024-2025)

| Plateforme | FPS | Draw Calls | Triangles/frame | Memoire app |
|---|---|---|---|---|
| Mobile low-end (2022) | 30 | < 150 | < 80K | < 800 MB |
| Mobile mid-range (2024) | 30-60 | < 300 | < 200K | < 1.5 GB |
| Mobile high-end (2024) | 60 | < 500 | < 500K | < 2 GB |
| Console (current gen) | 30-60 | < 3000 | < 5M | < 5 GB |
| PC (mid-range) | 60-144 | < 5000 | < 10M | < 8 GB |

### Mobile Checklist

- ASTC texture compression
- 1-2 real-time lights maximum
- Baked lighting + Light Probes
- Blob shadows or no shadows on low tier
- Aggressive LODs
- Minimal post-processing
- Implement quality tiers (Low / Med / High) so players can choose
- Minimize transparent/alpha objects (overdraw)

### Battery & Thermal Management

Phones throttle when hot. Reduce work during low-intensity moments:

```csharp
void OnEnterMenu()
{
    Application.targetFrameRate = 30;
    OnDemandRendering.renderFrameInterval = 2;  // render every 2nd frame
}

void OnEnterGameplay()
{
    Application.targetFrameRate = 60;
    OnDemandRendering.renderFrameInterval = 1;
}
```

---

## 8. Build Size

### Reduction Strategies

| Strategy | Typical Savings |
|---|---|
| Texture compression (Crunch) | 30-50% on textures |
| Audio compression | 50-80% on audio |
| Strip engine code modules | 5-20 MB |
| IL2CPP code stripping (High) | 10-40% on managed code |
| Addressables (download on demand) | Reduces initial install |
| Remove unused assets | Varies |

### Conditional Compilation

Strip debug code from release builds:

```csharp
// Only compiles in Editor and Development builds
public static class GameLog
{
    [System.Diagnostics.Conditional("UNITY_EDITOR")]
    [System.Diagnostics.Conditional("DEVELOPMENT_BUILD")]
    public static void Log(string msg) => Debug.Log(msg);
}

// Platform-specific code
#if UNITY_IOS
    IOSHaptics.Trigger();
#elif UNITY_ANDROID
    AndroidVibration.Trigger();
#endif
```
