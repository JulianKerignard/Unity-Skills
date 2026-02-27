# Unity Architecture Guide

Patterns and structures for scalable Unity projects. Choose your approach based on project scale — over-engineering a prototype is as costly as under-engineering a live service game.

## Table of Contents

1. [ScriptableObject Architecture](#1-scriptableobject-architecture)
2. [Scene Management](#2-scene-management)
3. [Service Locator](#3-service-locator)
4. [Dependency Injection](#4-dependency-injection)
5. [State Machines](#5-state-machines)
6. [Save System](#6-save-system)
7. [UI Architecture (MVP)](#7-ui-architecture)
8. [Audio Architecture](#8-audio-architecture)
9. [UI Toolkit Architecture](#9-ui-toolkit-architecture)
10. [Cinemachine](#10-cinemachine)
11. [Project Startup Checklist](#11-project-startup-checklist)

---

## 1. ScriptableObject Architecture

ScriptableObjects (SOs) are assets that persist across scenes and outside the gameplay lifecycle. They're the recommended default architecture for small-to-medium projects because they provide decoupling without the complexity of a DI framework.

### Runtime Sets — Track Active Instances

Track all living enemies, all open doors, all active quests — without any system knowing about each other directly.

```csharp
public abstract class RuntimeSet<T> : ScriptableObject
{
    private readonly List<T> _items = new();
    public IReadOnlyList<T> Items => _items;
    public int Count => _items.Count;

    public void Register(T item)   { if (!_items.Contains(item)) _items.Add(item); }
    public void Unregister(T item) { _items.Remove(item); }
}

[CreateAssetMenu(menuName = "Runtime Sets/Enemy Set")]
public class EnemyRuntimeSet : RuntimeSet<EnemyController> { }
```

Components self-register:
```csharp
public class EnemyController : MonoBehaviour
{
    [SerializeField] private EnemyRuntimeSet _set;
    private void OnEnable()  => _set.Register(this);
    private void OnDisable() => _set.Unregister(this);
}
```

Any system can read the set without knowing about enemies directly:
```csharp
public class Minimap : MonoBehaviour
{
    [SerializeField] private EnemyRuntimeSet _enemies;
    void Update()
    {
        foreach (var e in _enemies.Items) DrawBlip(e.transform.position);
    }
}
```

### Shared Variables — Cross-System State

When multiple systems need to read/write the same value (player HP, score, currency) without referencing each other:

```csharp
[CreateAssetMenu(menuName = "Variables/Float Variable")]
public class FloatVariable : ScriptableObject
{
    [SerializeField] private float _initialValue;
    [NonSerialized] public float Value;
    public event Action<float> OnChanged;

    private void OnEnable() => Value = _initialValue;

    public void Set(float v) { Value = v; OnChanged?.Invoke(v); }
    public void Add(float v) { Value += v; OnChanged?.Invoke(Value); }
}
```

Health system writes → UI reads. Neither references the other:
```csharp
// Writer
public class PlayerHealth : MonoBehaviour
{
    [SerializeField] private FloatVariable _hp;
    public void TakeDamage(float d) => _hp.Add(-d);
}

// Reader
public class HealthBar : MonoBehaviour
{
    [SerializeField] private FloatVariable _hp;
    [SerializeField] private Slider _slider;

    private Action<float> _onHpChanged;

    private void Awake() => _onHpChanged = v => _slider.value = v;
    private void OnEnable()  => _hp.OnChanged += _onHpChanged;
    private void OnDisable() => _hp.OnChanged -= _onHpChanged;
}
```

---

## 2. Scene Management

### Multi-Scene Loading

Don't put everything in one scene. Separate persistent systems from level content:

```
Scenes/
├── _Bootstrap.unity         # Init, never unloaded
├── _Persistent.unity        # Audio, EventSystem, main Canvas
├── MainMenu.unity
├── Gameplay/
│   ├── Level_01.unity       # Level geometry, enemies, triggers
│   └── Level_02.unity
└── UI/
    ├── HUD.unity            # In-game overlay
    └── PauseMenu.unity
```

### Bootstrap Pattern

The bootstrap scene (Build Settings index 0) initializes core systems, then additively loads the first real scene:

```csharp
public class Bootstrap : MonoBehaviour
{
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
    static void Init()
    {
        Application.targetFrameRate = 60;
    }

    async void Start()
    {
        // Register services
        ServiceLocator.Register<IAudio>(GetComponentInChildren<AudioManager>());
        DontDestroyOnLoad(gameObject);

        // Load first scene
        await SceneManager.LoadSceneAsync("MainMenu", LoadSceneMode.Additive);
    }
}
```

### Scene Loading with Progress

```csharp
public async Awaitable LoadScene(string target)
{
    // Show loading screen
    await SceneManager.LoadSceneAsync("Loading", LoadSceneMode.Additive);

    // Unload current gameplay
    var current = SceneManager.GetActiveScene();
    if (current.name != "_Bootstrap")
        await SceneManager.UnloadSceneAsync(current);

    // Load target
    var op = SceneManager.LoadSceneAsync(target, LoadSceneMode.Additive);
    op.allowSceneActivation = false;

    while (op.progress < 0.9f)
    {
        OnProgress?.Invoke(op.progress);
        await Awaitable.NextFrameAsync();
    }

    op.allowSceneActivation = true;
    await Awaitable.NextFrameAsync();
    SceneManager.SetActiveScene(SceneManager.GetSceneByName(target));

    await SceneManager.UnloadSceneAsync("Loading");
}
```

---

## 3. Service Locator

A lightweight alternative to DI for accessing global services. Simple to implement, easy to understand, and sufficient for most projects.

```csharp
public static class Services
{
    private static readonly Dictionary<Type, object> _reg = new();

    public static void Register<T>(T svc) where T : class => _reg[typeof(T)] = svc;
    public static T Get<T>() where T : class
        => _reg.TryGetValue(typeof(T), out var s) ? (T)s : null;
    public static void Clear() => _reg.Clear();
}

// Bootstrap
Services.Register<IAudio>(audioManager);
Services.Register<ISave>(saveManager);

// Anywhere
Services.Get<IAudio>()?.PlaySFX("click");
```

The tradeoff vs DI: service locator makes dependencies implicit (you can't see them in the constructor), which makes large codebases harder to reason about. For 10+ interacting systems, consider a real DI container.

---

## 4. Dependency Injection

For large projects, **VContainer** (lightweight, Unity-native) or **Zenject** (full-featured, more complex) provide constructor injection, lifecycle management, and testability.

```csharp
// VContainer — define bindings
public class GameScope : LifetimeScope
{
    protected override void Configure(IContainerBuilder b)
    {
        b.Register<IScoreService, ScoreService>(Lifetime.Singleton);
        b.Register<IEnemyFactory, EnemyFactory>(Lifetime.Singleton);
        b.RegisterComponentInHierarchy<PlayerController>();
        b.RegisterEntryPoint<GameLoop>();
    }
}

// Consumer — dependencies injected via constructor
public class GameLoop : IStartable, ITickable
{
    readonly IScoreService _score;
    readonly IEnemyFactory _enemies;

    public GameLoop(IScoreService score, IEnemyFactory enemies)
    {
        _score = score;
        _enemies = enemies;
    }

    public void Start() => _enemies.SpawnWave(1);
    public void Tick() { /* per-frame logic */ }
}
```

---

## 5. State Machines

### Class-Based FSM

Cleaner than enum switches for complex states with enter/exit logic:

```csharp
public interface IState
{
    void Enter();
    void Update();
    void Exit();
}

public class StateMachine
{
    private IState _current;

    public void ChangeState(IState next)
    {
        _current?.Exit();
        _current = next;
        _current?.Enter();
    }

    public void Update() => _current?.Update();
}
```

Usage:
```csharp
public class IdleState : IState
{
    readonly PlayerController _player;
    public IdleState(PlayerController p) => _player = p;

    public void Enter() => _player.Animator.Play("Idle");
    public void Update()
    {
        if (_player.Input.Move.magnitude > 0.1f)
            _player.FSM.ChangeState(_player.RunState);
    }
    public void Exit() { }
}
```

Use state machines for: player behavior, AI, game flow (menu → loading → gameplay → pause → game over), UI screen navigation.

---

## 6. Save System

### JSON-Based (Simple & Debuggable)

```csharp
[Serializable]
public class SaveData
{
    public int level;
    public float health;
    public SerializableVector3 position;
    public List<string> inventory = new();
    public string savedAt;
}

[Serializable]
public struct SerializableVector3
{
    public float x, y, z;
    public SerializableVector3(Vector3 v) { x = v.x; y = v.y; z = v.z; }
    public Vector3 ToVector3() => new(x, y, z);
}

public static class SaveSystem
{
    static string Path => System.IO.Path.Combine(
        Application.persistentDataPath, "save.json");

    public static void Save(SaveData data)
    {
        data.savedAt = DateTime.Now.ToString("o");
        File.WriteAllText(Path, JsonUtility.ToJson(data, true));
    }

    public static SaveData Load()
        => File.Exists(Path)
            ? JsonUtility.FromJson<SaveData>(File.ReadAllText(Path))
            : null;

    public static void Delete() { if (File.Exists(Path)) File.Delete(Path); }
}
```

For production, consider: multiple save slots, binary format for speed/size, encryption for anti-cheat, cloud saves via platform SDKs.

---

## 7. UI Architecture

### MVP Pattern (Model-View-Presenter)

Keeps UI code testable and maintainable by separating data, visuals, and logic:

```csharp
// Model — pure data
public class StatsModel
{
    public int Level { get; set; }
    public int XP { get; set; }
    public int XPToNext { get; set; }
    public float XPPercent => XPToNext > 0 ? (float)XP / XPToNext : 0;
}

// View — only visual operations
public class StatsView : MonoBehaviour
{
    [SerializeField] private TMP_Text _levelText;
    [SerializeField] private Slider _xpBar;

    public void SetLevel(int lv) => _levelText.text = $"Lv. {lv}";
    public void SetXP(float pct) => _xpBar.value = pct;
}

// Presenter — wires model to view
public class StatsPresenter : MonoBehaviour
{
    [SerializeField] private StatsView _view;
    private StatsModel _model;

    public void Bind(StatsModel m)
    {
        _model = m;
        Refresh();
    }

    public void Refresh()
    {
        _view.SetLevel(_model.Level);
        _view.SetXP(_model.XPPercent);
    }
}
```

### Screen Stack

Manage UI screens (main menu → settings → credits) with a stack:

```csharp
public class ScreenManager : MonoBehaviour
{
    [SerializeField] private UIScreen[] _screens;
    private readonly Stack<UIScreen> _stack = new();

    public void Push<T>() where T : UIScreen
    {
        if (_stack.TryPeek(out var prev)) prev.Hide();
        var screen = System.Array.Find(_screens, s => s is T);
        _stack.Push(screen);
        screen.Show();
    }

    public void Pop()
    {
        if (_stack.Count <= 1) return;
        _stack.Pop().Hide();
        if (_stack.TryPeek(out var prev)) prev.Show();
    }
}
```

---

## 8. Audio Architecture

### Pooled Audio Manager

A single AudioSource per sound effect is wasteful. Pool them:

```csharp
public class AudioManager : MonoBehaviour, IAudio
{
    [SerializeField] private AudioMixer _mixer;
    [SerializeField] private int _sfxPoolSize = 16;

    private AudioSource _music;
    private AudioSource[] _sfxPool;
    private int _poolIdx;

    void Awake()
    {
        _music = gameObject.AddComponent<AudioSource>();
        _music.loop = true;
        _music.outputAudioMixerGroup = _mixer.FindMatchingGroups("Music")[0];

        var sfxGroup = _mixer.FindMatchingGroups("SFX")[0];
        _sfxPool = new AudioSource[_sfxPoolSize];
        for (int i = 0; i < _sfxPoolSize; i++)
        {
            _sfxPool[i] = gameObject.AddComponent<AudioSource>();
            _sfxPool[i].outputAudioMixerGroup = sfxGroup;
        }
    }

    public void PlaySFX(AudioClip clip, float vol = 1f)
    {
        if (!clip) return;
        var src = _sfxPool[_poolIdx];
        src.clip = clip; src.volume = vol; src.Play();
        _poolIdx = (_poolIdx + 1) % _sfxPoolSize;
    }

    public void SetVolume(string param, float normalized)
    {
        float db = normalized > 0.001f ? Mathf.Log10(normalized) * 20f : -80f;
        _mixer.SetFloat(param, db);
    }
}
```

---

## 9. UI Toolkit Architecture

UI Toolkit is Unity's modern UI framework (replacing uGUI for editor and runtime UI). It uses a web-like paradigm: UXML for structure, USS for styling, C# for logic.

### When to Use UI Toolkit vs uGUI

| Scenario | Recommended | Reason |
|---|---|---|
| Menus, HUD, inventory, settings | **UI Toolkit** | Better performance, styling, data binding |
| In-world UI (health bars above enemies) | **uGUI** | UI Toolkit world-space support is limited |
| Legacy project with existing uGUI | **uGUI** | Migration cost rarely worth it mid-project |
| Editor tools & custom inspectors | **UI Toolkit** | First-class support, recommended by Unity |

### Basic Screen Pattern (UXML + C#)

```xml
<!-- MainMenuScreen.uxml -->
<ui:UXML xmlns:ui="UnityEngine.UIElements">
    <ui:VisualElement class="screen">
        <ui:Label text="My Game" class="title" />
        <ui:Button name="play-btn" text="Play" class="btn-primary" />
        <ui:Button name="settings-btn" text="Settings" class="btn-secondary" />
        <ui:Button name="quit-btn" text="Quit" class="btn-secondary" />
    </ui:VisualElement>
</ui:UXML>
```

```css
/* MainMenu.uss */
.screen {
    flex-grow: 1;
    align-items: center;
    justify-content: center;
}
.title {
    font-size: 48px;
    -unity-font-style: bold;
    margin-bottom: 40px;
    color: white;
}
.btn-primary {
    width: 200px;
    height: 50px;
    font-size: 20px;
    margin: 5px;
    background-color: rgb(60, 120, 200);
    color: white;
    border-radius: 8px;
}
.btn-secondary {
    width: 200px;
    height: 50px;
    font-size: 18px;
    margin: 5px;
}
```

```csharp
// MainMenuScreen.cs
public class MainMenuScreen : MonoBehaviour
{
    [SerializeField] private UIDocument _document;

    private Button _playBtn;
    private Button _settingsBtn;
    private Button _quitBtn;

    private void OnEnable()
    {
        var root = _document.rootVisualElement;
        _playBtn = root.Q<Button>("play-btn");
        _settingsBtn = root.Q<Button>("settings-btn");
        _quitBtn = root.Q<Button>("quit-btn");

        _playBtn.clicked += OnPlayClicked;
        _settingsBtn.clicked += OnSettingsClicked;
        _quitBtn.clicked += OnQuitClicked;
    }

    private void OnDisable()
    {
        _playBtn.clicked -= OnPlayClicked;
        _settingsBtn.clicked -= OnSettingsClicked;
        _quitBtn.clicked -= OnQuitClicked;
    }

    private void OnPlayClicked() => SceneManager.LoadSceneAsync("Gameplay");
    private void OnSettingsClicked() { /* push settings screen */ }
    private void OnQuitClicked() => Application.Quit();
}
```

### Data Binding (Unity 6+)

UI Toolkit supports runtime data binding, reducing boilerplate:

```csharp
// Define a data source
[CreateAssetMenu(menuName = "UI/Player Stats Binding")]
public class PlayerStatsBinding : ScriptableObject
{
    [CreateProperty] public int Level { get; set; }
    [CreateProperty] public float HealthPercent { get; set; }
    [CreateProperty] public string PlayerName { get; set; }
}

// Bind in code
var root = _document.rootVisualElement;
root.dataSource = _playerStats;  // SO instance

// In UXML, use data-binding attributes:
// <ui:Label binding-path="PlayerName" />
// <ui:ProgressBar binding-path="HealthPercent" />
```

### Custom Controls (Unity 6+)

Unity 6 replaces `UxmlFactory`/`UxmlTraits` with `[UxmlElement]` and `[UxmlAttribute]` attributes, much simpler:

```csharp
[UxmlElement]
public partial class HealthBar : VisualElement
{
    [UxmlAttribute]
    public float MaxValue { get; set; } = 100f;

    [UxmlAttribute]
    public float CurrentValue
    {
        get => currentValue;
        set
        {
            currentValue = Mathf.Clamp(value, 0, MaxValue);
            fill.style.width = Length.Percent(currentValue / MaxValue * 100f);
        }
    }
    private float currentValue = 100f;

    private readonly VisualElement fill;

    public HealthBar()
    {
        style.height = 20;
        style.backgroundColor = new Color(0.2f, 0.2f, 0.2f);
        style.borderBottomLeftRadius = style.borderBottomRightRadius =
            style.borderTopLeftRadius = style.borderTopRightRadius = 4;

        fill = new VisualElement();
        fill.style.height = Length.Percent(100);
        fill.style.backgroundColor = Color.green;
        fill.style.borderBottomLeftRadius = fill.style.borderBottomRightRadius =
            fill.style.borderTopLeftRadius = fill.style.borderTopRightRadius = 4;
        Add(fill);
    }
}
// Usable directly in UXML: <HealthBar max-value="200" current-value="150" />
```

### New Controls (Unity 6)

| Control | Usage |
|---------|-------|
| `ToggleButtonGroup` | Group of mutually exclusive toggles (toolbar) |
| `Tab` / `TabView` | Tab navigation (settings, inventory) |
| `MultiColumnTreeView` | Tree with columns (data editor) |

### Data Binding — Runtime Bidirectional (Unity 6+)

`[CreateProperty]` + `INotifyBindablePropertyChanged` for runtime two-way binding:

```csharp
public class InventoryViewModel : MonoBehaviour, INotifyBindablePropertyChanged
{
    public event EventHandler<BindablePropertyChangedEventArgs> propertyChanged;

    [CreateProperty]
    public int Gold
    {
        get => gold;
        set { gold = value; Notify(); }
    }
    private int gold;

    private void Notify([System.Runtime.CompilerServices.CallerMemberName] string prop = "")
        => propertyChanged?.Invoke(this, new BindablePropertyChangedEventArgs(prop));
}
// UXML: <ui:IntegerField binding-path="Gold" />
```

### Key Practices

- **Query elements once in `OnEnable`**, cache references — repeated `Q<T>()` is wasteful
- **Use USS classes** for theming and state (`AddToClassList("active")`) rather than inline styles
- **Separate UXML per screen** — don't put your entire UI in one document
- **Use `VisualElement.schedule`** for delayed or repeated callbacks instead of coroutines

---

## 10. Cinemachine

Cinemachine is the standard camera system for Unity. Use it instead of writing custom camera scripts.

### Setup Pattern

```csharp
// No custom camera script needed — Cinemachine handles it.
// Just reference virtual cameras via SO or direct references.
public class CameraManager : MonoBehaviour
{
    [SerializeField] private CinemachineCamera _gameplayCam;
    [SerializeField] private CinemachineCamera _dialogueCam;
    [SerializeField] private CinemachineCamera _bossCam;

    public void SwitchTo(CinemachineCamera cam)
    {
        // Cinemachine uses priority-based blending.
        // Set high priority on the active cam, low on others.
        _gameplayCam.Priority = 0;
        _dialogueCam.Priority = 0;
        _bossCam.Priority = 0;
        cam.Priority = 10;
    }
}
```

### Common Camera Setups

| Game Type | Cinemachine Setup |
|---|---|
| 3rd Person | CinemachineCamera + CinemachineThirdPersonFollow + CinemachineRotationComposer |
| Top-Down / RTS | CinemachineCamera + CinemachineFollow (offset) + CinemachineRotationComposer |
| 2D Platformer | CinemachineCamera + CinemachinePositionComposer + CinemachineConfiner2D |
| Cutscene / Rail | Dolly Track + CinemachineSplineDolly |
| Boss Fight | Separate virtual camera with group target (CinemachineTargetGroup) |

### Impulse (Screen Shake)

```csharp
// On the camera: add CinemachineImpulseListener component
// On the source (e.g., explosion):
[SerializeField] private CinemachineImpulseSource _impulse;

public void Explode()
{
    _impulse.GenerateImpulse();  // triggers shake on all listening cameras
}
```

### Tips

- **One CinemachineBrain** on your main Camera — it manages all virtual cameras
- **Use Cinemachine Confiner** to keep cameras within level bounds
- **Noise profiles** for subtle handheld camera feel (built-in presets work well)
- **CinemachineDeoccluder** (formerly CinemachineDecollider in CM 2.x) to prevent camera clipping through walls in 3D

---

## 11. Project Startup Checklist

When starting a new Unity project:

1. Choose render pipeline (URP for most projects)
2. Set up Git + LFS (see `references/workflow.md`)
3. Create folder structure (see SKILL.md §1)
4. Add Assembly Definitions for each code module
5. Configure quality settings per target platform
6. Create bootstrap scene with init logic
7. Set serialization to Force Text (Edit > Project Settings > Editor)
8. Install core packages: Input System, TextMeshPro, Addressables
9. Create base SO event channels (Void, Int, Float, String)
10. Add `.editorconfig` for team code style consistency
11. Configure Build Profiles (Unity 6+) — create per-platform profiles instead of using Build Settings
12. Evaluate the New Input System (default in Unity 6) — configure an Input Actions asset
