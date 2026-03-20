# Systems Specialises : IA, Debug, Localisation & Accessibilite

Covers debugging tools, localization, accessibility, Unity Inference Engine (ONNX), and Platform Toolkit. Each section is self-contained — jump to what you need.

For animation, 2D development, Shader Graph, and VFX Graph, see `specialized.md`.

## Table of Contents

1. [Debugging](#1-debugging)
2. [Localization](#2-localization)
3. [Accessibility](#3-accessibility)
4. [Unity Inference Engine (ONNX)](#4-unity-inference-engine-onnx)
5. [Platform Toolkit (Unity 6.3+)](#5-platform-toolkit-unity-63)

---

## 1. Debugging

### Visual Debugging (Scene View)

```csharp
// Gizmos — draw in Scene view (only visible in Editor)
private void OnDrawGizmos()
{
    // Always visible
    Gizmos.color = Color.yellow;
    Gizmos.DrawWireSphere(transform.position, _detectionRadius);
}

private void OnDrawGizmosSelected()
{
    // Only visible when this object is selected
    Gizmos.color = Color.red;
    Gizmos.DrawWireSphere(transform.position, _attackRadius);

    // Draw a line to the current target
    if (_currentTarget != null)
    {
        Gizmos.color = Color.green;
        Gizmos.DrawLine(transform.position, _currentTarget.position);
    }
}

// Debug.DrawRay/DrawLine — visible in Scene AND Game view (if Gizmos enabled)
void FixedUpdate()
{
    Debug.DrawRay(transform.position, transform.forward * _rayDistance, Color.cyan);

    if (Physics.Raycast(transform.position, transform.forward, out var hit, _rayDistance))
        Debug.DrawLine(transform.position, hit.point, Color.red);
}
```

### Console Best Practices

```csharp
// Rich text in Console (helps filtering)
Debug.Log("<color=green>[Inventory]</color> Added item: Sword");
Debug.LogWarning("<color=yellow>[AI]</color> No path found for " + name);
Debug.LogError("<color=red>[Save]</color> Failed to write save file");

// Context parameter — click the log to highlight the object in Hierarchy
Debug.Log("Health changed", this);          // 'this' MonoBehaviour
Debug.Log("Spawned enemy", enemyGameObject); // any UnityEngine.Object

// Conditional compilation — stripped from release builds
[System.Diagnostics.Conditional("UNITY_EDITOR")]
[System.Diagnostics.Conditional("DEVELOPMENT_BUILD")]
public static void GameLog(string msg, Object ctx = null) => Debug.Log(msg, ctx);
```

**Console filtering tips:**
- Type text in the Console search bar to filter messages
- Click the three filter buttons (Log / Warning / Error) to toggle categories
- Use `Debug.Log("TAG: message")` prefixes and filter by "TAG:"
- In Play Mode, click a log entry → the Console highlights the source object in Hierarchy
- Use **Console Pro** (Asset Store, free) or **Editor Console Pro** for advanced filtering

### Runtime Debug UI

```csharp
// Quick debug overlay with UI Toolkit (or IMGUI fallback)
public class DebugOverlay : MonoBehaviour
{
    [SerializeField] private bool _showDebug;

    private void OnGUI()
    {
        if (!_showDebug) return;

        GUILayout.BeginArea(new Rect(10, 10, 300, 400));
        GUILayout.Label($"FPS: {1f / Time.unscaledDeltaTime:F0}");
        GUILayout.Label($"Position: {transform.position}");
        GUILayout.Label($"Velocity: {_rb.linearVelocity.magnitude:F1} m/s");
        GUILayout.Label($"State: {_currentState}");
        GUILayout.Label($"Enemies: {_enemySet.Count}");
        GUILayout.EndArea();
    }

    private void Update()
    {
        if (Input.GetKeyDown(KeyCode.F1)) _showDebug = !_showDebug;
    }
}
```

### Physics Debugging

```csharp
// Visualize raycasts, overlap queries, collision normals
private void FixedUpdate()
{
    // OverlapSphere visualization
    #if UNITY_EDITOR
    var colliders = Physics.OverlapSphere(transform.position, _radius, _mask);
    foreach (var col in colliders)
        Debug.DrawLine(transform.position, col.transform.position, Color.magenta, 0.1f);
    #endif
}
```

**Physics Debugger** (Window > Analysis > Physics Debugger):
- Visualizes all colliders, trigger volumes, contacts
- Shows collision layer matrix interactions
- Highlights sleeping/awake Rigidbodies

### Profiler Markers (Custom)

```csharp
using Unity.Profiling;

public class EnemyManager : MonoBehaviour
{
    static readonly ProfilerMarker s_UpdateAI = new("EnemyManager.UpdateAI");

    void Update()
    {
        s_UpdateAI.Begin();
        // ... expensive AI code ...
        s_UpdateAI.End();
    }
}
// Shows up as a labeled block in the Profiler Timeline
```

---

## 2. Localization

### Unity Localization Package Setup

```
1. Install: com.unity.localization (Package Manager)
2. Window > Asset Management > Localization Tables
3. Create Locales: English, French, etc. (Locale assets)
4. Create String Table Collection: "UI_Strings"
5. Add entries: Key → Translated value per locale
```

### Runtime Usage

```csharp
using UnityEngine.Localization;
using UnityEngine.Localization.Settings;

public class LocalizedUI : MonoBehaviour
{
    // Reference directly in Inspector — auto-updates on locale change
    [SerializeField] private LocalizedString _titleString;
    [SerializeField] private TMP_Text _titleText;

    private void OnEnable()
    {
        _titleString.StringChanged += OnStringChanged;
    }

    private void OnDisable()
    {
        _titleString.StringChanged -= OnStringChanged;
    }

    private void OnStringChanged(string value)
    {
        _titleText.text = value;
    }
}
```

### Locale Switching

```csharp
public async void SetLocale(string localeCode)
{
    // "en", "fr", "ja", etc.
    var locale = LocalizationSettings.AvailableLocales.Locales
        .Find(l => l.Identifier.Code == localeCode);

    if (locale != null)
        LocalizationSettings.SelectedLocale = locale;
}
```

### Smart Strings (Variables in Translations)

```
Table entry:  "welcome_msg" → "Welcome, {player-name}! You have {coin-count} coins."

// In code, use SmartFormat arguments:
_welcomeString.Arguments = new object[] {
    new { player_name = "Hero", coin_count = 42 }
};
```

### Best Practices

- **Never hardcode user-facing strings** — even if you only ship in one language initially, localization retrofits are painful
- **Use String Table references** (`LocalizedString`) in Inspector over string keys — they're type-safe and auto-complete
- **Localize assets too** — different sprites, audio, or fonts per locale via Asset Tables
- **Plan for text expansion** — German and French are ~30% longer than English. Design UI with flexible layouts.
- **Right-to-left (RTL)** support needs TextMeshPro RTL settings and mirrored layouts for Arabic/Hebrew

---

## 3. Accessibility

### Input Accessibility

```csharp
// Rebindable controls via New Input System
public class InputRebinder : MonoBehaviour
{
    [SerializeField] private InputActionReference _action;

    public void StartRebind()
    {
        _action.action.PerformInteractiveRebinding()
            .WithControlsExcluding("Mouse")   // optional: exclude devices
            .OnComplete(op =>
            {
                op.Dispose();
                SaveBindings();
            })
            .Start();
    }

    private void SaveBindings()
    {
        // Save overrides as JSON
        var json = _action.action.actionMap.asset.SaveBindingOverridesAsJson();
        PlayerPrefs.SetString("InputBindings", json);
    }

    public void LoadBindings()
    {
        var json = PlayerPrefs.GetString("InputBindings", "");
        if (!string.IsNullOrEmpty(json))
            _action.action.actionMap.asset.LoadBindingOverridesFromJson(json);
    }
}
```

### Visual Accessibility

```csharp
// Color blindness-friendly palette — avoid red/green distinctions
// Use shapes + colors (not color alone) to convey information

[CreateAssetMenu(menuName = "Config/Accessibility Settings")]
public class AccessibilitySettingsSO : ScriptableObject
{
    [Header("Visual")]
    public bool highContrastMode;
    public float uiScale = 1f;                // 0.8 to 1.5
    [Range(14, 32)] public int baseFontSize = 18;
    public bool screenShakeEnabled = true;
    public float screenShakeIntensity = 1f;   // 0 to disable

    [Header("Audio")]
    public bool subtitlesEnabled = true;
    public float subtitleSize = 1f;
    public bool visualAudioCues;              // flash screen on important sounds

    [Header("Gameplay")]
    public bool autoAim;
    public float timingWindowMultiplier = 1f; // >1 = more forgiving QTEs
    public bool holdInsteadOfMash;            // toggle button mashing → hold
}
```

### Checklist

- [ ] **Remappable controls** — let players change every binding
- [ ] **Subtitles** — with speaker identification and size options
- [ ] **Font size options** — minimum 18px readable, scalable up to 32px
- [ ] **Color blind modes** — or better: don't rely on color alone (use icons + color)
- [ ] **Screen shake toggle** — essential for motion-sensitive players
- [ ] **Button mashing alternatives** — hold-to-confirm option
- [ ] **Adjustable difficulty** — separate options for damage, timing, puzzles
- [ ] **High contrast UI option** — solid backgrounds behind text
- [ ] **Audio cues for visual events** — and visual cues for audio events
- [ ] **Pause anywhere** — including cutscenes

---

## 4. Unity Inference Engine (ONNX)

### Overview

Unity Inference Engine (formerly Sentis) runs ONNX models directly inside Unity at runtime.

**Package:** `com.unity.ai.inference` (previously `com.unity.sentis`)

**Use cases:**
- NPC AI (decision making, dialogue generation)
- Computer vision (in-game object detection)
- Procedural generation (textures, levels)
- Audio (text-to-speech, voice recognition)

### Basic Pattern

```csharp
using Unity.InferenceEngine;

public class AIBrain : MonoBehaviour
{
    [SerializeField] private ModelAsset modelAsset;
    private Worker worker;

    void Start()
    {
        var model = ModelLoader.Load(modelAsset);
        worker = new Worker(model, BackendType.GPUCompute);
    }

    public float[] Predict(float[] input)
    {
        using var inputTensor = new Tensor<float>(new TensorShape(1, input.Length), input);
        worker.Schedule(inputTensor);
        var output = worker.PeekOutput() as Tensor<float>;
        return output.ToReadOnlyArray();
    }

    void OnDestroy() => worker?.Dispose();
}
```

### Available Backends

| Backend | Best For | Notes |
|---|---|---|
| `GPUCompute` | PC / console | Recommended default, uses compute shaders |
| `CPU` | Fallback / debugging | Slower but works everywhere |
| `GPUPixel` | Mobile (iOS/Android) | Uses pixel shaders, broader mobile support |

### Tips

- Import `.onnx` files directly into Unity — they become `ModelAsset` references
- Use the **Inference Engine Model Validator** (included in the package) to check operator compatibility before shipping
- Not all ONNX operators are supported — verify your model exports cleanly
- For large models, split inference across multiple frames using `worker.Schedule()` with `worker.FlushSchedule()` to avoid frame spikes
- Dispose tensors and workers when done to avoid GPU memory leaks

### Pattern : Inference repartie sur plusieurs frames

Pour les modeles lourds, eviter de bloquer une frame entiere :

```csharp
public class AsyncInference : MonoBehaviour
{
    private Worker _worker;
    private bool _inferenceInProgress;

    public async Awaitable<float[]> PredictAsync(float[] input)
    {
        if (_inferenceInProgress) return null;
        _inferenceInProgress = true;

        using var inputTensor = new Tensor<float>(new TensorShape(1, input.Length), input);
        _worker.Schedule(inputTensor);

        while (!_worker.hasFinished)
            await Awaitable.NextFrameAsync(destroyCancellationToken);

        var output = _worker.PeekOutput() as Tensor<float>;
        _inferenceInProgress = false;
        return output.ToReadOnlyArray();
    }
}
```

### Quantization workflow

1. Exporter le modele en ONNX depuis PyTorch/TensorFlow
2. Quantizer avec `onnxruntime.quantization` (Python) : FP32 → FP16 ou INT8
3. Importer le modele quantize dans Unity
4. Tester avec le Model Validator du package

Un modele FP16 est ~2x plus petit et ~1.5x plus rapide sur GPU sans perte perceptible pour les cas gaming (NPC AI, detection, generation).

### Backend par plateforme

| Plateforme | Backend recommande | Raison |
|---|---|---|
| PC / Console | `GPUCompute` | Meilleure performance, compute shaders disponibles |
| iOS | `GPUPixel` | Pas de compute sur tous les devices |
| Android (haut de gamme) | `GPUCompute` | Si Vulkan disponible |
| Android (bas de gamme) | `CPU` | Fallback le plus compatible |
| WebGL | `CPU` | Pas de compute dans le navigateur |

## 5. Platform Toolkit (Unity 6.3+)

API unifiee pour les services cross-plateforme (PS5, Xbox, Switch, Steam, Android, iOS). Evite d'integrer chaque SDK plateforme separement.

### Services couverts

| Service | Description |
|---|---|
| Achievements | Trophees/Achievements multi-plateforme |
| Save Data | Sauvegardes cloud par plateforme |
| Accounts | Identite joueur (PSN, Xbox Live, Steam, etc.) |
| Commerce | In-app purchases cross-platform |

### Setup

1. Installer `com.unity.platform-toolkit` via Package Manager
2. Configurer les credentials plateforme dans `Project Settings > Platform Toolkit`
3. Initialiser au boot :
   ```csharp
   await PlatformServices.InitializeAsync();
   ```
4. Les APIs retournent des resultats generiques — le toolkit route vers le bon SDK natif

### Quand l'utiliser

- Projet multi-plateforme (2+ plateformes) avec achievements ou cloud saves
- Nouveau projet Unity 6.3+ — simplifie significativement le code multi-plateforme
- **Ne PAS utiliser si** : une seule plateforme cible, ou Unity < 6.3

**Note** : Le Platform Toolkit est recent. Verifier la documentation officielle pour les APIs exactes car l'API peut evoluer.
