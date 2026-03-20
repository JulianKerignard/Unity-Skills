# ECS Avance : Burst, Containers & Hybrid

Patterns avances pour Burst Compiler, NativeContainers, enableable components,
shared components, approche hybride DOTS/GameObjects, Aspects et DynamicBuffer.

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
