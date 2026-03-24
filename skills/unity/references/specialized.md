# Unity Specialized Systems

Covers animation, 2D development, Shader Graph, VFX Graph, and physics. Each section is self-contained — jump to what you need.

For AI/NavMesh, debugging tools, localization, accessibility, and Inference Engine, see `systems.md`.

## Table of Contents

1. [Animation](#1-animation)
2. [2D Development](#2-2d-development)
3. [Shader Graph & VFX Graph](#3-shader-graph--vfx-graph)

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

### Animation Rigging Package

Package `com.unity.animation.rigging` — adds IK constraints and rigging evaluated at runtime by the Animator.

**Setup:**
1. Add a `Rig Builder` component on the character root
2. Create a child "Rig" GameObject with a `Rig` component
3. Add constraint components as children of the Rig

**Common constraints:**

| Constraint | Use Case | Example |
|---|---|---|
| Two Bone IK | Arms/legs reaching a point | Hand grabs a handle |
| Multi-Aim | Head/torso tracks a target | Character looks at an object |
| Multi-Position | Object follows a position | Weapon in hand |
| Damped Transform | Follow with smoothing | Camera attachment |
| Twist Correction | Fix twist deformation | Forearm rotation |
| Chain IK | Flexible bone chain | Tentacle, tail, rope |

**Runtime control:**
```csharp
[SerializeField] private Rig aimRig;

void Update()
{
    // Blend IK in/out based on situation
    float targetWeight = hasTarget ? 1f : 0f;
    aimRig.weight = Mathf.MoveTowards(aimRig.weight, targetWeight, Time.deltaTime * 5f);
}
```

**Tips:**
- Each constraint has a `weight` property (0-1) for blending
- Use `RigBuilder.Build()` if you add constraints at runtime
- Constraints are evaluated in child order within the Rig hierarchy — order matters for dependent chains
- Combine with Animator layers: the Rig evaluates *after* the Animator, overriding or blending on top of the current pose

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

        float moveX = Input.GetAxisRaw("Horizontal"); // Old Input — use New Input System for production
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

### 2D/3D Mixing Pattern (6.3+)

Le 2D URP Renderer supporte desormais `MeshRenderer` et `SkinnedMeshRenderer` aux cotes des sprites. Cas d'usage : personnages 3D dans un environnement 2D, props 3D dans un jeu 2D.

**Setup** :
1. Utiliser le **2D Renderer** (URP) comme renderer actif
2. Ajouter les objets 3D normalement (Mesh + MeshRenderer + Material URP)
3. Les objets 3D participent au sorting 2D (meme Sorting Layer / Order in Layer)
4. L'eclairage 2D (`Light2D`) affecte les objets 3D si le material est compatible

**Contrainte** : les objets 3D utilisent le meme pipeline de sorting que les sprites. Pour un controle precis de la profondeur, utiliser les Sorting Layers et l'Order in Layer.

### Box2D v3 Physics (Unity 6.3+)

Unity 6.3 integrates Box2D v3 as the 2D physics backend, providing better performance and new APIs:

**What's new:**
- Improved performance for simulations with many bodies (multi-threaded solver)
- Low-level API for custom queries (`UnityEngine.LowLevelPhysics2D`)
- Better joint and contact support
- Enhanced determinism for replays and networking

**Contact Events (new pattern):**
```csharp
// Unity 6.3+ : optimized contact event callbacks
void OnCollisionEnter2D(Collision2D collision)
{
    // Access contact points with the new backend
    foreach (var contact in collision.contacts)
    {
        Debug.Log($"Impact at {contact.point} with force {contact.normalImpulse}");
    }
}
```

**Note:** The backend change is transparent — existing Collider2D/Rigidbody2D code keeps working. Performance gains are automatic. The low-level API (`LowLevelPhysics2D`) runs alongside the high-level API and will eventually replace it.

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
- **Custom Interpolators** — pass custom data between vertex and fragment stages without intermediate nodes
- **Fullscreen Shader Graph** — create post-process effects directly in Shader Graph (URP), no custom render passes needed

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
