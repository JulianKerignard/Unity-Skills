# Architecture Avancee : UI Toolkit & Cinemachine

Patterns avances pour UI Toolkit, Cinemachine, et checklist de demarrage projet. Pour les patterns fondamentaux (SO events, state machine, service locator, MVP, audio), voir `architecture.md`.

## Table of Contents

1. [UI Toolkit Architecture](#1-ui-toolkit-architecture)
2. [Cinemachine](#2-cinemachine)
3. [Project Startup Checklist](#3-project-startup-checklist)

---

## 1. UI Toolkit Architecture

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

## 2. Cinemachine

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

### Migration Cinemachine 2.x → 3.x

Unity 6 ship Cinemachine 3.x par defaut. Les projets existants en CM 2.x doivent migrer. L'upgrader automatique (`Window > Cinemachine > Upgrade from 2.x`) gere la majorite mais certains changements requierent une intervention manuelle.

#### Table de renommage des composants

| CM 2.x | CM 3.x |
|---|---|
| `CinemachineVirtualCamera` | `CinemachineCamera` |
| `CinemachineFreeLook` | `CinemachineCamera` + `CinemachineOrbitalFollow` + `CinemachineRotationComposer` |
| `Cinemachine3rdPersonFollow` | `CinemachineThirdPersonFollow` |
| `CinemachineComposer` | `CinemachineRotationComposer` |
| `CinemachineFramingTransposer` | `CinemachinePositionComposer` |
| `CinemachineTransposer` | `CinemachineFollow` |
| `CinemachinePOV` | `CinemachinePanTilt` |
| `CinemachineCollider` | `CinemachineDeoccluder` |
| `CinemachineSmoothPath` / `CinemachinePath` | `SplineContainer` (Unity Splines package) |
| `CinemachineDollyCart` | `CinemachineSplineCart` |
| `CinemachineTrackedDolly` | `CinemachineSplineDolly` |

#### Changements breaking

- **Input** : CM 3.x decouple l'input. Utiliser `CinemachineInputAxisController` au lieu de l'ancien input integre. Ajouter ce composant sur le `CinemachineCamera` et configurer les Input Actions.
- **Splines** : Les paths custom sont remplaces par le package Unity Splines (`com.unity.splines`). Utiliser `SplineContainer` + `CinemachineSplineDolly`.
- **Priority** : En CM 3.x, la priorite est un `int` simple sur `CinemachineCamera.Priority` (plus haut = plus prioritaire). L'ancien systeme de canaux est supprime.
- **Extensions** : Les extensions CM 2.x deviennent des components CM 3.x. Les ajouter directement sur le `CinemachineCamera`.

#### Workflow de migration

1. Backup du projet (commit propre avant migration)
2. Lancer l'upgrader : `Window > Cinemachine > Upgrade from 2.x`
3. Verifier les warnings dans la Console
4. Tester chaque camera dans le jeu
5. Reconfigurer l'input si necessaire (`CinemachineInputAxisController`)
6. Remplacer les paths par des `SplineContainer` si utilises

---

## 3. Project Startup Checklist

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
