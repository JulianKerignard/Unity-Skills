# C# Patterns & Conventions for Unity

Practical patterns that come up repeatedly in Unity C# code. When writing or reviewing scripts, scan the relevant section here.

## Table of Contents

1. [MonoBehaviour Lifecycle](#1-monobehaviour-lifecycle)
2. [Async Patterns](#2-async-patterns)
3. [C# 9+ Features (Unity 6)](#3-c-9-features-unity-6)
4. [Event Patterns](#4-event-patterns)
5. [Extension Methods](#5-useful-extension-methods)
6. [Null Safety in Unity](#6-null-safety-in-unity)
7. [Serialization](#7-serialization)
8. [Editor Scripting](#8-editor-scripting)
9. [Code Style Conventions](#9-code-style-conventions)

---

## 1. MonoBehaviour Lifecycle

Understanding execution order prevents the most common class of Unity bugs — null references caused by accessing something that hasn't been initialized yet.

```
Awake()        → Self-init: cache own components, set defaults
OnEnable()     → Subscribe to events, enable systems
Start()        → Cross-object init: other objects are now Awake'd
FixedUpdate()  → Physics (runs on fixed clock, may run 0+ times per frame)
Update()       → Game logic, input (runs once per rendered frame)
LateUpdate()   → Post-processing: camera follow, UI sync
OnDisable()    → Unsubscribe from events, pause systems
OnDestroy()    → Final cleanup, release resources
```

**Why this order matters:**
- `Awake()` runs even if the component is disabled; `Start()` only runs when enabled. Use Awake for self-init so other scripts can safely reference you in *their* Start.
- Physics runs on a fixed timestep (default 0.02s). Movement code in `Update()` needs `Time.deltaTime`; movement in `FixedUpdate()` already runs at a fixed rate.
- `LateUpdate()` runs after all `Update()` calls, making it ideal for camera follow — the player has already moved.
- The `OnEnable/OnDisable` pair is your subscription lifecycle. Events subscribed in `OnEnable` should always be unsubscribed in `OnDisable` to prevent memory leaks and null reference errors on destroyed objects.

Use `[DefaultExecutionOrder(N)]` when you need one script to consistently initialize before another.

---

## 2. Async Patterns

### Coroutines — Simple Sequences

Coroutines are good for "do X, wait, do Y" sequences. They're easy to write but hard to compose, cancel cleanly, or handle errors.

```csharp
private Coroutine _spawnRoutine;

public void StartSpawning()
{
    StopSpawning();  // prevent duplicates
    _spawnRoutine = StartCoroutine(SpawnLoop(10, 0.5f));
}

public void StopSpawning()
{
    if (_spawnRoutine != null)
    {
        StopCoroutine(_spawnRoutine);
        _spawnRoutine = null;
    }
}

private IEnumerator SpawnLoop(int count, float interval)
{
    for (int i = 0; i < count; i++)
    {
        SpawnEnemy();
        yield return new WaitForSeconds(interval);
    }
}
```

### Awaitable — Modern Async (Unity 6+)

Unity 6 introduced `Awaitable`, which supports `async/await` natively with proper cancellation, error handling, and no GC allocations.

```csharp
public async Awaitable LoadLevelAsync(string scene)
{
    var op = SceneManager.LoadSceneAsync(scene);
    while (!op.isDone)
    {
        OnProgress?.Invoke(op.progress);
        await Awaitable.NextFrameAsync();
    }
}

// With cancellation
private CancellationTokenSource _cts;

public async Awaitable DelayedAction(float seconds)
{
    _cts = new CancellationTokenSource();
    try
    {
        await Awaitable.WaitForSecondsAsync(seconds, _cts.Token);
        DoAction();
    }
    catch (OperationCanceledException) { /* graceful cancel */ }
}

private void OnDisable() => _cts?.Cancel();
```

### destroyCancellationToken — Preferred Cancellation

Every `MonoBehaviour` exposes a `destroyCancellationToken` that fires automatically when the object is destroyed. Always prefer it over manually managing a `CancellationTokenSource` — it prevents fire-and-forget async methods from running on dead objects.

```csharp
async Awaitable FadeOutAsync()
{
    float t = 1f;
    while (t > 0f)
    {
        t -= Time.deltaTime;
        canvasGroup.alpha = t;
        await Awaitable.NextFrameAsync(destroyCancellationToken);
    }
}
```

### Thread Switching — BackgroundThreadAsync / MainThreadAsync

`Awaitable` lets you hop between threads within a single method. Use `BackgroundThreadAsync()` for heavy CPU work (parsing, compression) and `MainThreadAsync()` to return to the main thread before touching any Unity API.

```csharp
async Awaitable<LevelData> LoadLevelAsync(string path)
{
    // Heavy file parsing on background thread
    await Awaitable.BackgroundThreadAsync();
    var json = File.ReadAllText(path);
    var data = JsonUtility.FromJson<LevelData>(json);

    // Back to main thread for Unity API
    await Awaitable.MainThreadAsync();
    return data;
}
```

### AwaitableCompletionSource\<T\> — Custom Async Triggers

When you need to await something that isn't frame-based (a UI button press, a network response, a player choice), create an `AwaitableCompletionSource<T>` and resolve it externally.

```csharp
private AwaitableCompletionSource<bool> dialogChoice;

public async Awaitable<bool> ShowConfirmDialogAsync(string message)
{
    dialogChoice = new AwaitableCompletionSource<bool>();
    ShowDialog(message);
    return await dialogChoice.Awaitable;
}

// Called by UI buttons
public void OnConfirm() => dialogChoice.SetResult(true);
public void OnCancel()  => dialogChoice.SetResult(false);
```

### Common Awaitable APIs

| API | Purpose |
|---|---|
| `Awaitable.NextFrameAsync(token)` | Wait until the next frame |
| `Awaitable.WaitForSecondsAsync(seconds, token)` | Wait for a duration |
| `Awaitable.EndOfFrameAsync(token)` | Wait until end of current frame |
| `Awaitable.FixedUpdateAsync(token)` | Wait until next FixedUpdate |
| `Awaitable.FromAsyncOperation(op)` | Wrap an `AsyncOperation` (scene load, asset bundle) |
| `Awaitable.BackgroundThreadAsync()` | Switch to a background thread |
| `Awaitable.MainThreadAsync()` | Switch back to the main thread |

**Convention:** suffix all methods returning `Awaitable` or `Awaitable<T>` with `Async` (e.g., `LoadLevelAsync`, `FadeOutAsync`).

### When to Use What

| Need | Best Choice | Reason |
|---|---|---|
| Simple delay/sequence | Coroutine | Readable, low overhead |
| IO, async loading (Unity 6+) | `Awaitable` | Cancellation, error handling, composable |
| IO, async loading (pre-6) | UniTask | Zero-alloc async, rich API |
| Frame-precise timing | Update + timer float | Full control, predictable |

---

## 3. C# 9+ Features (Unity 6)

Unity 6 uses Roslyn and supports C# 9 (some C# 10/11 features are also available). These modern syntax features reduce boilerplate and improve readability in Unity scripts.

### Init-only Properties

Init-only properties (`init`) allow setting values only at construction time, giving you immutable-by-default data objects without needing a constructor.

```csharp
public record EnemySpawnConfig
{
    public Vector3 Position { get; init; }
    public Quaternion Rotation { get; init; }
    public int Health { get; init; } = 100;
}

// Usage
var config = new EnemySpawnConfig
{
    Position = Vector3.zero,
    Rotation = Quaternion.identity
};
```

### Target-typed `new`

The compiler infers the type from the left-hand side, reducing repetition — especially helpful with long generic types.

```csharp
// Before
Dictionary<string, List<Enemy>> groups = new Dictionary<string, List<Enemy>>();

// After (C# 9)
Dictionary<string, List<Enemy>> groups = new();
List<Vector3> points = new();
```

### Pattern Matching (switch expressions, relational, logical)

Switch expressions combined with relational patterns (`<`, `>=`) replace bulky if-else chains for value classification.

```csharp
public static string GetDamageLevel(int damage) => damage switch
{
    <= 0  => "None",
    < 25  => "Light",
    < 50  => "Medium",
    < 100 => "Heavy",
    _     => "Critical"
};

// Property pattern — destructure object properties inline
public static float GetSpeedMultiplier(EnemyState state) => state switch
{
    { IsStunned: true }                    => 0f,
    { IsSlowed: true, SlowFactor: var f }  => f,
    { IsSprinting: true }                  => 1.5f,
    _                                      => 1f
};
```

### File-scoped Namespaces

Removes one level of indentation from every type in the file. Prefer this in all new scripts.

```csharp
namespace Game.Combat;  // instead of namespace Game.Combat { ... }

public class DamageSystem { }
```

---

## 4. Event Patterns

### C# Events — Code-to-Code Communication

The fastest and most type-safe option. Use when both publisher and subscriber live in the same scene or reference each other.

```csharp
// Publisher
public class Inventory : MonoBehaviour
{
    public event Action<Item> OnItemAdded;
    public event Action OnChanged;

    public void AddItem(Item item)
    {
        _items.Add(item);
        OnItemAdded?.Invoke(item);
        OnChanged?.Invoke();
    }
}

// Subscriber — note the symmetrical Enable/Disable
public class InventoryUI : MonoBehaviour
{
    [SerializeField] private Inventory _inventory;

    private void OnEnable()  => _inventory.OnChanged += Refresh;
    private void OnDisable() => _inventory.OnChanged -= Refresh;

    private void Refresh() { /* rebuild UI */ }
}
```

### UnityEvents — Designer-Friendly Wiring

Use when you want designers to wire responses in the Inspector without code. Slightly slower than C# events due to reflection, but the workflow benefit is worth it for non-perf-critical paths.

```csharp
public class Button3D : MonoBehaviour
{
    [SerializeField] private UnityEvent _onPressed;
    public void Press() => _onPressed?.Invoke();
}
```

### ScriptableObject Event Channels — Full Decoupling

When systems exist in different scenes, or you want zero compile-time dependencies between them. The full pattern is in the main SKILL.md.

**Rule of thumb:** Start with C# events. Upgrade to SO channels when you need cross-scene communication or want systems to be fully independent.

---

## 5. Useful Extension Methods

Keep a `Utils/UnityExtensions.cs` file with frequently needed helpers:

```csharp
public static class UnityExtensions
{
    // Transform
    public static void DestroyAllChildren(this Transform t)
    {
        for (int i = t.childCount - 1; i >= 0; i--)
            Object.Destroy(t.GetChild(i).gameObject);
    }

    public static T GetOrAddComponent<T>(this GameObject go) where T : Component
        => go.TryGetComponent<T>(out var c) ? c : go.AddComponent<T>();

    // Vector — useful for ignoring the Y axis (ground plane)
    public static Vector3 WithY(this Vector3 v, float y) => new(v.x, y, v.z);
    public static Vector3 Flat(this Vector3 v) => new(v.x, 0f, v.z);

    // Collections
    public static T RandomElement<T>(this IList<T> list)
        => list[UnityEngine.Random.Range(0, list.Count)];

    // Layer mask
    public static bool IsInLayer(this GameObject go, LayerMask mask)
        => (mask.value & (1 << go.layer)) != 0;
}
```

---

## 6. Null Safety in Unity

Unity overrides the `==` operator for its Object types. This means `null` checks behave differently than in standard C#, and getting it wrong is a very common source of bugs.

```csharp
// CORRECT — uses Unity's override, catches both null AND destroyed objects
if (myObj == null) { }
if (myObj != null) { }
myComponent?.DoSomething();

// DANGEROUS — bypasses Unity's override, won't catch destroyed objects
if (myObj is null) { }       // C# 7 pattern matching skips Unity's ==
if (myObj is not null) { }   // same problem
```

Why does this matter? When you `Destroy()` a GameObject, the C# object still exists in memory until GC collects it. Unity's overridden `==` returns `true` for null even while the C# reference is technically non-null. Pattern matching (`is null`) checks the C# reference directly, so it misses destroyed objects.

### Defensive Patterns

```csharp
// Auto-find missing Inspector refs (runs in Editor only)
#if UNITY_EDITOR
private void OnValidate()
{
    _rb ??= GetComponent<Rigidbody>();
    if (_maxHealth <= 0)
    {
        _maxHealth = 1;
        Debug.LogWarning($"{name}: maxHealth clamped to 1", this);
    }
}
#endif

// Guarantee required components at compile time
[RequireComponent(typeof(Rigidbody))]
public class PhysicsMovement : MonoBehaviour { }
```

---

## 7. Serialization

### What Gets Serialized

Unity serializes public fields and `[SerializeField]` private fields of supported types. To serialize a custom struct or class, mark it `[Serializable]`.

```csharp
[Serializable]
public struct WaveConfig
{
    public int enemyCount;
    public float spawnInterval;
    public EnemyDataSO enemyType;
}

public class WaveManager : MonoBehaviour
{
    [SerializeField] private WaveConfig[] _waves;  // editable in Inspector
}
```

### Polymorphic Serialization with SerializeReference

When you need a list that can hold different subtypes:

```csharp
[Serializable]
public abstract class AbilityBase { public string name; }

[Serializable]
public class HealAbility : AbilityBase { public int amount; }

[Serializable]
public class DashAbility : AbilityBase { public float distance; }

public class AbilityHolder : MonoBehaviour
{
    [SerializeReference] private List<AbilityBase> _abilities = new();
    // Inspector shows a polymorphic list with type picker
}
```

---

## 8. Editor Scripting

### Quick Debug Actions (No Custom Editor Needed)

```csharp
[ContextMenu("Reset Health")]
private void DebugResetHealth() => _currentHealth = _maxHealth;

[ContextMenu("Kill")]
private void DebugKill() => TakeDamage(9999);
```

### ReadOnly Attribute

Display a field in the Inspector without allowing edits:

```csharp
public class ReadOnlyAttribute : PropertyAttribute { }

#if UNITY_EDITOR
[CustomPropertyDrawer(typeof(ReadOnlyAttribute))]
public class ReadOnlyDrawer : PropertyDrawer
{
    public override void OnGUI(Rect pos, SerializedProperty prop, GUIContent label)
    {
        GUI.enabled = false;
        EditorGUI.PropertyField(pos, prop, label, true);
        GUI.enabled = true;
    }
}
#endif

// Usage
[ReadOnly, SerializeField] private int _currentLevel;
```

### Inspector Buttons

```csharp
#if UNITY_EDITOR
[CustomEditor(typeof(LevelGenerator))]
public class LevelGeneratorEditor : Editor
{
    public override void OnInspectorGUI()
    {
        DrawDefaultInspector();
        var gen = (LevelGenerator)target;
        if (GUILayout.Button("Generate")) gen.Generate();
        if (GUILayout.Button("Clear"))    gen.Clear();
    }
}
#endif
```

---

## 9. Code Style Conventions

### Script Layout Order

Consistent ordering makes classes scannable. A recommended layout:

```csharp
public class ExampleComponent : MonoBehaviour
{
    // 1. Constants
    private const float TICK_RATE = 0.25f;

    // 2. Serialized fields (grouped with [Header])
    [Header("Config")]
    [SerializeField] private int _maxCount;

    [Header("Refs")]
    [SerializeField] private Transform _target;

    // 3. Public events
    public event Action OnCompleted;

    // 4. Private state
    private float _timer;
    private bool _isActive;

    // 5. Unity lifecycle (Awake → OnEnable → Start → Update → LateUpdate → OnDisable → OnDestroy)
    private void Awake() { }
    private void OnEnable() { }
    private void Update() { }
    private void OnDisable() { }

    // 6. Public API
    public void Activate() { }

    // 7. Private methods
    private void DoInternal() { }

    // 8. Editor-only
    #if UNITY_EDITOR
    private void OnValidate() { }
    #endif
}
```
