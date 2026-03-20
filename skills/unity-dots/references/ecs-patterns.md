# ECS Patterns — Unity 6+ DOTS Reference

Patterns avances pour Entity Component System, Job System et Burst Compiler.

---

## 1. Authoring et Baking detaille

### TransformUsageFlags

Le flag passe a `GetEntity()` indique comment l'entity utilise sa transform :

```csharp
// Dynamic — l'entity bouge a runtime (position, rotation, scale modifies)
var entity = GetEntity(TransformUsageFlags.Dynamic);

// Renderable — l'entity est rendue mais ne bouge pas forcement
var entity = GetEntity(TransformUsageFlags.Renderable);

// WorldSpace — utilise une transform world-space (pas de parent)
var entity = GetEntity(TransformUsageFlags.WorldSpace);

// None — l'entity n'a pas besoin de transform du tout
var entity = GetEntity(TransformUsageFlags.None);

// Combinaison possible
var entity = GetEntity(TransformUsageFlags.Dynamic | TransformUsageFlags.Renderable);
```

### Baking dependencies

```csharp
public class WeaponBaker : Baker<WeaponAuthoring>
{
    public override void Bake(WeaponAuthoring authoring)
    {
        // Depend on another component on the same GameObject
        DependsOn(authoring.statsConfig);

        // Depend on a referenced GameObject (reference vers un autre authoring)
        if (authoring.projectilePrefab != null)
        {
            var prefabEntity = GetEntity(authoring.projectilePrefab,
                TransformUsageFlags.Dynamic);
            AddComponent(GetEntity(TransformUsageFlags.Dynamic),
                new ProjectilePrefab { Value = prefabEntity });
        }
    }
}
```

### Multiple components sur un entity

```csharp
public class EnemyBaker : Baker<EnemyAuthoring>
{
    public override void Bake(EnemyAuthoring authoring)
    {
        var entity = GetEntity(TransformUsageFlags.Dynamic);

        AddComponent(entity, new Health { Value = authoring.maxHealth });
        AddComponent(entity, new MoveSpeed { Value = authoring.speed });
        AddComponent(entity, new EnemyTag());
        AddComponent(entity, new AttackDamage { Value = authoring.damage });

        // Buffer element (collection par entity)
        AddBuffer<WaypointElement>(entity);
    }
}
```

### Prefab baking

```csharp
public class SpawnerBaker : Baker<SpawnerAuthoring>
{
    public override void Bake(SpawnerAuthoring authoring)
    {
        var entity = GetEntity(TransformUsageFlags.None);
        AddComponent(entity, new SpawnerData
        {
            Prefab = GetEntity(authoring.prefab, TransformUsageFlags.Dynamic),
            SpawnRate = authoring.spawnRate,
            SpawnCount = authoring.count
        });
    }
}

// Le prefab doit etre dans un SubScene ou reference par le Baker
// L'entity prefab aura automatiquement le component Prefab (tag)
```

---

## 2. ISystem vs SystemBase

### ISystem (struct) — recommande Unity 6+

```csharp
[BurstCompile]
[UpdateInGroup(typeof(SimulationSystemGroup))]
public partial struct MovementSystem : ISystem
{
    public void OnCreate(ref SystemState state)
    {
        // Require specific components to exist before running
        state.RequireForUpdate<MoveSpeed>();
    }

    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        float dt = SystemAPI.Time.DeltaTime;
        foreach (var (transform, speed) in
            SystemAPI.Query<RefRW<LocalTransform>, RefRO<MoveSpeed>>())
        {
            transform.ValueRW.Position +=
                transform.ValueRO.Forward() * speed.ValueRO.Value * dt;
        }
    }

    public void OnDestroy(ref SystemState state) { }
}
```

Avantages : Burst-compatible, pas d'allocation GC, meilleure perf.

### SystemBase (class) — cas specifiques

```csharp
[UpdateInGroup(typeof(PresentationSystemGroup))]
public partial class UIUpdateSystem : SystemBase
{
    protected override void OnUpdate()
    {
        // Peut acceder a des managed types (UI, string, etc.)
        foreach (var (health, uiRef) in
            SystemAPI.Query<RefRO<Health>, ManagedAPI.UnityEngineComponent<HealthBar>>())
        {
            uiRef.Value.SetHealth(health.ValueRO.Value);
        }
    }
}
```

Quand utiliser SystemBase :
- Acces a des managed types (UI Toolkit, string, UnityEngine.Object)
- Migration progressive depuis du code existant
- Interaction avec des APIs Unity classiques (AudioSource, ParticleSystem)

---

## 3. SystemAPI.Query patterns

### Query simple

```csharp
foreach (var (transform, speed) in
    SystemAPI.Query<RefRW<LocalTransform>, RefRO<MoveSpeed>>())
{
    transform.ValueRW.Position +=
        transform.ValueRO.Forward() * speed.ValueRO.Value * dt;
}
```

### Query avec filtres

```csharp
// WithAll — l'entity doit avoir le component (mais on ne le lit pas)
// WithNone — l'entity ne doit PAS avoir le component
// WithAny — l'entity doit avoir au moins un des components
// WithEntityAccess — acces a l'Entity handle

foreach (var (health, entity) in SystemAPI.Query<RefRO<Health>>()
    .WithAll<EnemyTag>()
    .WithNone<DeadTag>()
    .WithEntityAccess())
{
    if (health.ValueRO.Value <= 0)
    {
        state.EntityManager.AddComponent<DeadTag>(entity);
    }
}
```

### Query avec Shared Component filter

```csharp
foreach (var transform in SystemAPI.Query<RefRW<LocalTransform>>()
    .WithSharedComponentFilter(new TeamId { Value = 1 }))
{
    // Seulement les entites de l'equipe 1
}
```

### Query avec EnableableComponent

```csharp
// Les enableable components sont automatiquement filtres :
// seules les entites ou le component est "enabled" matchent
foreach (var (transform, speed) in
    SystemAPI.Query<RefRW<LocalTransform>, RefRO<MoveSpeed>>()
    .WithAll<ActiveTag>())  // ActiveTag : IEnableableComponent
{
    // Seulement les entites "actives"
}
```

### Query avec DynamicBuffer

```csharp
foreach (var (buffer, entity) in
    SystemAPI.Query<DynamicBuffer<WaypointElement>>()
    .WithEntityAccess())
{
    if (buffer.Length > 0)
    {
        var target = buffer[0].Position;
        // ... naviguer vers le waypoint
    }
}
```

### SystemAPI.GetSingleton / HasSingleton

```csharp
// Acces a un component unique (un seul entity le possede)
if (SystemAPI.HasSingleton<GameSettings>())
{
    var settings = SystemAPI.GetSingleton<GameSettings>();
    // ...
}
```

---

## 4. IJobEntity (traitement parallele)

### Pattern de base

```csharp
[BurstCompile]
public partial struct MoveJob : IJobEntity
{
    public float DeltaTime;

    // Les parametres definissent implicitement la query
    // ref = ReadWrite, in = ReadOnly
    void Execute(ref LocalTransform transform, in MoveSpeed speed)
    {
        transform.Position += transform.Forward() * speed.Value * DeltaTime;
    }
}

// Scheduling dans le system
[BurstCompile]
public partial struct MoveSystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        var job = new MoveJob { DeltaTime = SystemAPI.Time.DeltaTime };

        // ScheduleParallel — execute sur plusieurs worker threads
        job.ScheduleParallel();

        // Schedule — execute sur un seul worker thread
        // job.Schedule();

        // Run — execute immediatement sur le main thread
        // job.Run();
    }
}
```

### IJobEntity avec Entity access

```csharp
[BurstCompile]
public partial struct DamageJob : IJobEntity
{
    public float DamageAmount;
    public EntityCommandBuffer.ParallelWriter Ecb;

    void Execute(ref Health health, in EnemyTag tag,
        [EntityIndexInQuery] int sortKey, Entity entity)
    {
        health.Value -= DamageAmount;
        if (health.Value <= 0)
        {
            Ecb.AddComponent<DeadTag>(sortKey, entity);
        }
    }
}
```

### EntityCommandBuffer (ECB) pour modifications structurelles

```csharp
[BurstCompile]
public partial struct SpawnSystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        var ecb = new EntityCommandBuffer(Allocator.TempJob);

        foreach (var (spawner, transform) in
            SystemAPI.Query<RefRW<SpawnerData>, RefRO<LocalTransform>>())
        {
            spawner.ValueRW.Timer -= SystemAPI.Time.DeltaTime;
            if (spawner.ValueRO.Timer <= 0)
            {
                var instance = ecb.Instantiate(spawner.ValueRO.Prefab);
                ecb.SetComponent(instance, LocalTransform.FromPosition(
                    transform.ValueRO.Position));
                spawner.ValueRW.Timer = spawner.ValueRO.SpawnRate;
            }
        }

        ecb.Playback(state.EntityManager);
        ecb.Dispose();
    }
}
```

Pour les jobs paralleles, utiliser `EntityCommandBuffer.ParallelWriter` :

```csharp
var ecb = new EntityCommandBuffer(Allocator.TempJob);
var ecbParallel = ecb.AsParallelWriter();
// Passer ecbParallel au job, utiliser sortKey pour l'ordre deterministe
// Apres le job : ecb.Playback(...); ecb.Dispose();
```

---

## 5. Burst Compiler

### Attributs

```csharp
// Standard — optimisations par defaut
[BurstCompile]
public partial struct MySystem : ISystem { }

// Performance maximale (moins de precision flottante)
[BurstCompile(FloatPrecision.Low, FloatMode.Fast)]
public partial struct FastMathSystem : ISystem { }

// Debug temporaire (permet le debugging, desactive les optimisations)
[BurstCompile(Debug = true)]
public partial struct DebugSystem : ISystem { }
```

### Contraintes Burst

Ce qui est interdit dans le code `[BurstCompile]` :
- Types managed : `string`, `class`, `List<T>`, arrays managed
- Allocations GC : `new object()`, boxing
- Try/catch (exceptions)
- API Unity main-thread : `Debug.Log`, `GameObject.Find`, etc.
- Delegates, closures avec captures managed

Alternatives :
- `string` -> `FixedString64Bytes`, `FixedString128Bytes`
- `List<T>` -> `NativeList<T>`
- `T[]` -> `NativeArray<T>`
- `Dictionary` -> `NativeHashMap<K,V>`
- `Debug.Log` -> pas dans les jobs ; utiliser des NativeArrays pour remonter des infos

### Burst Inspector

`Window > Burst > Inspector` pour voir le code machine genere. Utile pour verifier que Burst compile bien le code et identifier les chemins non optimises.

---

## 6. NativeContainers

### Types principaux

```csharp
// NativeArray — tableau de taille fixe
var positions = new NativeArray<float3>(1000, Allocator.TempJob);
// ...
positions.Dispose();

// NativeList — liste dynamique
var entities = new NativeList<Entity>(64, Allocator.TempJob);
entities.Add(someEntity);
entities.Dispose();

// NativeHashMap — dictionnaire
var lookup = new NativeHashMap<int, float>(256, Allocator.Persistent);
lookup[entityId] = 42f;
lookup.Dispose(); // dans OnDestroy

// NativeHashSet — ensemble
var visited = new NativeHashSet<int>(128, Allocator.TempJob);
visited.Add(nodeId);
visited.Dispose();

// NativeQueue — file (FIFO)
var queue = new NativeQueue<Entity>(Allocator.TempJob);
queue.Enqueue(entity);
var next = queue.Dequeue();
queue.Dispose();
```

### Allocators

| Allocator | Duree de vie | Dispose requis | Usage |
|-----------|-------------|----------------|-------|
| `Temp` | 1 frame | Non (auto) | Calculs temporaires dans un system |
| `TempJob` | 4 frames | Oui (apres job complete) | Donnees passees a un job |
| `Persistent` | Illimite | Oui (OnDestroy) | Donnees permanentes (lookups, caches) |

### Acces concurrent dans les jobs

```csharp
// Lecture seule dans un job parallele
[ReadOnly] public NativeArray<float3> Positions;

// Ecriture parallele (chaque thread ecrit a un index different)
[NativeDisableParallelForRestriction]
public NativeArray<float> Results;

// HashMap concurrent pour ecriture parallele
public NativeHashMap<int, float>.ParallelWriter ResultMap;
```

---

## 7. Enableable Components et Shared Components

### Enableable Components

Plus performant que d'ajouter/retirer des components car pas de changement d'archetype (pas de move entre chunks).

```csharp
// Definition
public struct Stunned : IComponentData, IEnableableComponent { }
public struct Poisoned : IComponentData, IEnableableComponent
{
    public float DamagePerSecond;
    public float RemainingDuration;
}

// Baker — ajouter le component (desactive par defaut si besoin)
AddComponent(entity, new Stunned());
SetComponentEnabled<Stunned>(entity, false);

// System — activer/desactiver
SystemAPI.SetComponentEnabled<Stunned>(entity, true);

// Query — les disabled sont exclus par defaut
foreach (var (poison, entity) in
    SystemAPI.Query<RefRW<Poisoned>>().WithEntityAccess())
{
    poison.ValueRW.RemainingDuration -= dt;
    if (poison.ValueRO.RemainingDuration <= 0)
    {
        SystemAPI.SetComponentEnabled<Poisoned>(entity, false);
    }
}

// Inclure les disabled explicitement
foreach (var (stunned, entity) in
    SystemAPI.Query<RefRO<Stunned>>()
    .WithOptions(EntityQueryOptions.IgnoreComponentEnabledState)
    .WithEntityAccess())
{
    // Traite toutes les entites, meme celles ou Stunned est disabled
}
```

### Shared Components

Meme valeur partagee par un groupe d'entites. Influence le chunking (entites avec la meme shared value sont dans le meme chunk).

```csharp
// Definition
public struct TeamId : ISharedComponentData
{
    public int Value;
}

public struct LODLevel : ISharedComponentData
{
    public int Level;
}

// Baker
AddSharedComponent(entity, new TeamId { Value = authoring.team });

// Query avec filtre
foreach (var transform in SystemAPI.Query<RefRW<LocalTransform>>()
    .WithSharedComponentFilter(new TeamId { Value = 1 }))
{
    // Seulement l'equipe 1
}

// Changer la shared value (provoque un changement de chunk)
state.EntityManager.SetSharedComponent(entity, new TeamId { Value = 2 });
```

Attention : changer une shared component value deplace l'entity vers un autre chunk. Ne pas le faire frequemment.

---

## 8. Hybride : DOTS + GameObjects

### SubScene workflow

- Le contenu DOTS vit dans des SubScenes (baked au build, streaming possible)
- La scene principale peut contenir des GameObjects classiques (UI, Camera, Audio)
- Le SubScene se charge en mode Play et bake les entities

### Companion GameObjects

Pour les cas ou un entity a besoin d'un composant managed (ParticleSystem, AudioSource) :

```csharp
public class VFXAuthoring : MonoBehaviour
{
    public ParticleSystem particles;
}

public class VFXBaker : Baker<VFXAuthoring>
{
    public override void Bake(VFXAuthoring authoring)
    {
        var entity = GetEntity(TransformUsageFlags.Dynamic);
        AddComponentObject(entity, authoring.particles);
    }
}

// System managed pour acceder au ParticleSystem
public partial class VFXSystem : SystemBase
{
    protected override void OnUpdate()
    {
        foreach (var (health, ps) in
            SystemAPI.Query<RefRO<Health>,
            SystemAPI.ManagedAPI.UnityEngineComponent<ParticleSystem>>())
        {
            if (health.ValueRO.Value <= 0 && !ps.Value.isPlaying)
                ps.Value.Play();
        }
    }
}
```

### Pattern recommande : DOTS simulation, MonoBehaviour presentation

```
[DOTS World]                    [GameObject World]
  Entity + Health        -->      HealthBar UI (Canvas)
  Entity + Position      -->      Camera Follow (Cinemachine)
  Entity + DamageEvent   -->      VFX / AudioSource
```

Un SystemBase de "bridge" lit les donnees DOTS et met a jour les GameObjects correspondants. Ce pattern permet de garder la simulation performante en DOTS tout en utilisant l'ecosysteme Unity classique pour la presentation.

---

## 9. Aspects (encapsulation de queries)

```csharp
public readonly partial struct MovementAspect : IAspect
{
    public readonly RefRW<LocalTransform> Transform;
    public readonly RefRO<MoveSpeed> Speed;
    [Optional] public readonly RefRO<SprintMultiplier> Sprint;

    public void Move(float dt)
    {
        float multiplier = Sprint.IsValid ? Sprint.ValueRO.Value : 1f;
        Transform.ValueRW.Position +=
            Transform.ValueRO.Forward() * Speed.ValueRO.Value * multiplier * dt;
    }
}

// Utilisation dans un system
foreach (var movement in SystemAPI.Query<MovementAspect>())
{
    movement.Move(dt);
}

// Ou dans un job
[BurstCompile]
public partial struct MoveAspectJob : IJobEntity
{
    public float DeltaTime;

    void Execute(MovementAspect movement)
    {
        movement.Move(DeltaTime);
    }
}
```

Les Aspects regroupent plusieurs components en une interface logique. Utile quand plusieurs systems accedent aux memes combinaisons de components.

---

## 10. DynamicBuffer (collections par entity)

```csharp
// Definition
[InternalBufferCapacity(8)] // 8 elements inline dans le chunk, au-dela heap
public struct WaypointElement : IBufferElementData
{
    public float3 Position;
}

public struct InventorySlot : IBufferElementData
{
    public int ItemId;
    public int Quantity;
}

// Baker
public override void Bake(WaypointAuthoring authoring)
{
    var entity = GetEntity(TransformUsageFlags.Dynamic);
    var buffer = AddBuffer<WaypointElement>(entity);
    foreach (var wp in authoring.waypoints)
    {
        buffer.Add(new WaypointElement { Position = wp.position });
    }
}

// Lecture dans un system
foreach (var (buffer, transform) in
    SystemAPI.Query<DynamicBuffer<WaypointElement>, RefRW<LocalTransform>>())
{
    if (buffer.Length > 0)
    {
        var target = buffer[0].Position;
        // ... naviguer, puis buffer.RemoveAt(0) quand atteint
    }
}
```

`InternalBufferCapacity` controle combien d'elements sont stockes directement dans le chunk. Au-dela, un buffer heap est alloue. Ajuster selon le cas d'usage typique.
