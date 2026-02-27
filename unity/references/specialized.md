# Unity Specialized Systems

Covers animation, 2D development, Shader Graph / VFX Graph, debugging, localization, and accessibility. Each section is self-contained — jump to what you need.

## Table of Contents

1. [Animation](#1-animation)
2. [2D Development](#2-2d-development)
3. [Shader Graph & VFX Graph](#3-shader-graph--vfx-graph)
4. [Debugging](#4-debugging)
5. [Localization](#5-localization)
6. [Accessibility](#6-accessibility)

---

## 1. Animation

### Animator Controller Best Practices

Animator Controllers can become unmanageable quickly. Keep them clean:

**Cache parameter hashes** — string lookups are slow and typo-prone:

```csharp
public class CharacterAnimator : MonoBehaviour
{
    // Cache as static readonly — shared across all instances, computed once
    private static readonly int SpeedHash     = Animator.StringToHash("Speed");
    private static readonly int IsGroundedHash = Animator.StringToHash("IsGrounded");
    private static readonly int AttackHash    = Animator.StringToHash("Attack");
    private static readonly int DieHash       = Animator.StringToHash("Die");
    private static readonly int HurtHash      = Animator.StringToHash("Hurt");

    [SerializeField] private Animator _animator;

    public void SetSpeed(float speed) => _animator.SetFloat(SpeedHash, speed);
    public void SetGrounded(bool grounded) => _animator.SetBool(IsGroundedHash, grounded);
    public void TriggerAttack() => _animator.SetTrigger(AttackHash);
    public void TriggerDie() => _animator.SetTrigger(DieHash);
    public void TriggerHurt() => _animator.SetTrigger(HurtHash);
}
```

### Animator Layer Guidelines

| Layer | Use Case | Weight | Blending |
|---|---|---|---|
| Base Layer | Locomotion (idle, walk, run, jump) | 1.0 | — |
| Upper Body | Attack, interact, hold weapon | 0-1 | Additive or Override with AvatarMask |
| Face / Head | Look direction, expressions | 0-1 | Additive with head mask |
| Override | Full-body overrides (death, cutscene) | 0-1 | Override, full body |

Create **Avatar Masks** to isolate layers. An upper body mask lets the character swing a sword while legs keep running.

### StateMachineBehaviour

Attach logic directly to Animator states without coupling to external scripts:

```csharp
public class PlaySoundOnEnter : StateMachineBehaviour
{
    [SerializeField] private AudioClip _clip;
    [Range(0f, 1f)]
    [SerializeField] private float _volume = 1f;

    public override void OnStateEnter(Animator animator, AnimatorStateInfo stateInfo, int layerIndex)
    {
        if (_clip != null)
            AudioSource.PlayClipAtPoint(_clip, animator.transform.position, _volume);
    }
}

// Useful for: playing SFX on attack states, spawning VFX on enter,
// enabling/disabling hitboxes, triggering events at state transitions
```

### Animation Events

Use sparingly — they're powerful but fragile (string-based, break silently if method renamed):

```csharp
// Called from an Animation Event keyframe in the Animation window
public void OnFootstep()
{
    _audioManager.PlaySFX(_footstepClips.RandomElement());
}

public void OnAttackHitFrame()
{
    _combat.EnableHitbox();
}

public void OnAttackEnd()
{
    _combat.DisableHitbox();
}
```

**Prefer StateMachineBehaviours or manual timing** for critical gameplay logic. Animation Events are fine for cosmetic effects (particles, sounds) but dangerous for gameplay-critical timing because they depend on the Animation clip being played at normal speed.

### Blend Trees

Use Blend Trees for smooth transitions between movement animations:

```
1D Blend Tree (Speed):
  0.0 → Idle
  0.5 → Walk
  1.0 → Run

2D Freeform (Direction + Speed):
  (0, 0)    → Idle
  (0, 1)    → Forward Walk
  (1, 0)    → Strafe Right
  (-1, 0)   → Strafe Left
  (0, -1)   → Walk Backward
```

### Common Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| Too many parameters | Hard to debug, spaghetti transitions | Use sub-state machines, reduce to essentials |
| Any State → everywhere | Transition spaghetti | Use Any State only for interrupts (death, stun) |
| String-based SetTrigger | Typos fail silently | Cache `Animator.StringToHash()` |
| No exit time on transitions | Animations cut abruptly | Set appropriate exit times or transition durations |
| Huge monolithic Animator | Impossible to navigate | Split into layers + sub-state machines |

---

## 2. 2D Development

### Sprite Atlas

Always use Sprite Atlases in production — they batch draw calls and reduce texture swaps:

```csharp
// In Project: Create > 2D > Sprite Atlas
// Drag folders of sprites into the "Objects for Packing" list

// Late binding (Addressables-friendly):
[SerializeField] private SpriteAtlas _uiAtlas;

public Sprite GetSprite(string name) => _uiAtlas.GetSprite(name);
```

**Rules:**
- Group sprites by usage context (UI atlas, player atlas, enemies atlas, environment atlas)
- Max atlas size: 2048x2048 on mobile, 4096x4096 on PC
- Enable **Tight Packing** for irregular sprites to save atlas space
- Use **Variant atlases** for resolution scaling (1x for mobile, 2x for tablets)

### Tilemaps

```
Scenes/
├── Level_01.unity
│   ├── Grid (Grid component)
│   │   ├── Ground     (Tilemap + TilemapRenderer, sorting order 0)
│   │   ├── Walls      (Tilemap + TilemapRenderer + TilemapCollider2D, order 1)
│   │   ├── Decoration (Tilemap + TilemapRenderer, order 2)
│   │   └── Foreground (Tilemap + TilemapRenderer, order 10)
```

**Best Practices:**
- **Separate Tilemaps by function**: ground, collision, decoration, foreground. This lets you add colliders only to the wall layer.
- **Use Rule Tiles** for auto-tiling (ground edges, wall corners). Saves hours of manual placement.
- **Composite Collider 2D** on collision Tilemaps — merges individual tile colliders into a single optimized collider.
- **Chunk mode** rendering for large Tilemaps: set Tilemap Renderer > Mode > Chunk for better performance on large maps.

### 2D Physics

| Concept | 3D Equivalent | 2D Component |
|---|---|---|
| Rigidbody | Rigidbody | Rigidbody2D |
| Box Collider | BoxCollider | BoxCollider2D |
| Raycast | Physics.Raycast | Physics2D.Raycast |
| Overlap | Physics.OverlapSphere | Physics2D.OverlapCircle |
| Trigger | OnTriggerEnter | OnTriggerEnter2D |

**Critical:** 2D and 3D physics are completely separate systems. A Rigidbody2D will never interact with a BoxCollider (3D), and vice versa. Don't mix them.

```csharp
// 2D movement pattern
public class PlatformerController : MonoBehaviour
{
    [SerializeField] private float _speed = 8f;
    [SerializeField] private float _jumpForce = 12f;
    [SerializeField] private LayerMask _groundLayer;
    [SerializeField] private Transform _groundCheck;

    private Rigidbody2D _rb;
    private bool _isGrounded;

    private void Awake() => _rb = GetComponent<Rigidbody2D>();

    private void FixedUpdate()
    {
        // Ground check with non-allocating overlap
        _isGrounded = Physics2D.OverlapCircle(
            _groundCheck.position, 0.15f, _groundLayer);

        float moveX = Input.GetAxisRaw("Horizontal");
        _rb.linearVelocity = new Vector2(moveX * _speed, _rb.linearVelocity.y);
    }

    public void Jump()
    {
        if (_isGrounded)
            _rb.AddForce(Vector2.up * _jumpForce, ForceMode2D.Impulse);
    }
}
```

### Pixel Perfect (2D Pixel Art)

```
Setup:
1. Install package: com.unity.2d.pixel-perfect
2. Add Pixel Perfect Camera component to your Camera
3. Set Assets Pixels Per Unit (e.g., 16 for 16x16 tiles)
4. Set Reference Resolution (e.g., 320x180 for a retro feel)
5. Enable "Upscale Render Texture" for crisp pixels at any resolution
```

**Sprite Import Settings for Pixel Art:**
- Filter Mode: **Point (no filter)** — bilinear/trilinear blurs pixels
- Compression: **None** — compression creates artifacts on pixel art
- Pixels Per Unit: match your tile size (16, 32, etc.)
- Pivot: **Bottom** for characters, **Center** for props

### Sorting & Rendering Order

```
Sorting Layers (defined in Tags & Layers):
  Background    (far)
  Ground
  Props
  Characters
  Foreground
  UI            (near)

Within a sorting layer, use Order in Layer (int) for fine control.
For Y-sorting (top-down games): set Transparency Sort Mode to Custom Axis (0, 1, 0)
  or use a script: _renderer.sortingOrder = -(int)(transform.position.y * 100);
```

### Unity 6.3+ 2D Improvements

- **Render 3D as 2D**: The 2D URP Renderer now supports Mesh Renderer and Skinned Mesh Renderer alongside sprites in the same scene — great for mixing 3D characters with 2D environments
- **Box2D v3 low-level API**: New `UnityEngine.LowLevelPhysics2D` namespace with multi-threaded physics, enhanced determinism, and visual debugging. Runs alongside the existing API and will eventually replace it.
- **Sprite Atlas Analyser**: Built-in tool to find packing inefficiencies in your Sprite Atlases (wasted space, duplicates, oversized sprites)

---

## 3. Shader Graph & VFX Graph

### Shader Graph Best Practices

| Practice | Why |
|---|---|
| **Name properties descriptively** | `_BaseColor` not `_Color1`. Shows in Material Inspector. |
| **Use SubGraphs for reusable logic** | UV distortion, noise patterns, lighting helpers — DRY principle |
| **Minimize texture samples** | Each sample is a GPU read. Pack channels (R=metal, G=AO, B=detail, A=smooth) |
| **Use `half` precision on mobile** | Properties > Precision > Half. Halves bandwidth for color/UV data |
| **Preview nodes regularly** | Catch issues early. Right-click node > Preview |
| **Group & label nodes** | Use Sticky Notes and Groups in the graph for documentation |

### Common Shader Graph Patterns

**Unity 6.3+ Shader Graph additions:**
- **Terrain shader support** — create custom terrain materials in both URP and HDRP without code
- **8 texture coordinate sets** (up from 4) for complex material layering
- **Template browser** — start from pre-built shader templates
- **Customized lighting content** — more control over lighting in custom shaders

**Dissolve Effect:**
```
Noise Texture (UV) → Step (threshold from property) → Alpha Clip
Add edge glow: Noise → Smoothstep(threshold-0.05, threshold) → Emission
```

**Scrolling UV (Water, Lava):**
```
UV + (Time × Speed property) → Texture Sample
Layer 2 UVs at different speed/direction for depth
```

**Fresnel / Rim Light:**
```
Fresnel Effect node → Multiply by color → Add to Emission
Use for shields, outlines, hologram effects
```

### VFX Graph Overview

VFX Graph is GPU-accelerated (compute shaders). Use it for large particle counts (1000+). For simpler effects (<100 particles), the built-in Particle System (Shuriken) is simpler and sufficient.

| Feature | Shuriken (Particle System) | VFX Graph |
|---|---|---|
| Particle count | Hundreds | Millions |
| Runs on | CPU | GPU (compute) |
| Complexity | Simple inspector | Node-based graph |
| Platform support | Universal | Requires compute shaders |
| Best for | Small effects, mobile | Large effects, PC/console |

**VFX Graph tips:**
- Use **Spawn over Distance** for trails behind moving objects
- **Sample SDF** (Signed Distance Fields) for particles conforming to mesh shapes
- Use **Output Particle Mesh** to render mesh particles instead of billboards
- Keep **Capacity** (max particle count) as low as possible — it pre-allocates GPU memory

---

## 4. Debugging

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

## 5. Localization

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

## 6. Accessibility

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
