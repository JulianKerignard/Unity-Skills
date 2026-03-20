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
