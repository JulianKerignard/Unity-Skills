# C# Patterns & Conventions for Unity

Practical patterns that come up repeatedly in Unity C# code. When writing or reviewing scripts, scan the relevant section here.

## Table of Contents

1. [MonoBehaviour Lifecycle](#1-monobehaviour-lifecycle)
2. [Async Patterns](#2-async-patterns)
3. [Event Patterns](#3-event-patterns)
4. [Extension Methods](#4-useful-extension-methods)
5. [Null Safety in Unity](#5-null-safety-in-unity)
6. [Serialization](#6-serialization)
7. [Editor Scripting](#7-editor-scripting)
8. [Code Style Conventions](#8-code-style-conventions)

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

### When to Use What

| Need | Best Choice | Reason |
|---|---|---|
| Simple delay/sequence | Coroutine | Readable, low overhead |
| IO, async loading (Unity 6+) | `Awaitable` | Cancellation, error handling, composable |
| IO, async loading (pre-6) | UniTask | Zero-alloc async, rich API |
| Frame-precise timing | Update + timer float | Full control, predictable |

---

## 3. Event Patterns

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

## 4. Useful Extension Methods

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

## 5. Null Safety in Unity

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

## 6. Serialization

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

## 7. Editor Scripting

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

## 8. Code Style Conventions

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
