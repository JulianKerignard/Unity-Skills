## Recettes de refactoring Unity courantes

### Singleton MonoBehaviour vers SO Service

Avant :
```csharp
public class AudioManager : MonoBehaviour
{
    public static AudioManager Instance { get; private set; }
    void Awake() { if (Instance != null) Destroy(gameObject); else Instance = this; }
    public void PlaySFX(string name) { /* ... */ }
}
// Appel : AudioManager.Instance.PlaySFX("click");
```

Apres :
```csharp
// 1. ScriptableObject service
[CreateAssetMenu(menuName = "Services/Audio")]
public class AudioService : ScriptableObject
{
    [SerializeField] AudioClip[] _clips;
    public void PlaySFX(string name) { /* ... */ }
}

// 2. Consommateur avec injection par SerializeField
public class UIButton : MonoBehaviour
{
    [SerializeField] AudioService _audio;
    void OnClick() => _audio.PlaySFX("click");
}
```

Etapes : Creer le SO, migrer la logique, creer l'asset, remplacer tous les `AudioManager.Instance` par des `[SerializeField] AudioService`.

### God Manager vers services separes

Avant :
```csharp
public class GameManager : MonoBehaviour // 800+ lignes
{
    // Scoring, spawning, UI, audio, save, settings...
}
```

Apres :
```csharp
// Separer par responsabilite
public class ScoreService : MonoBehaviour { /* scoring */ }
public class SpawnService : MonoBehaviour { /* spawning */ }
public class SaveService : MonoBehaviour { /* persistence */ }

// GameManager ne coordonne que le flow de haut niveau
public class GameManager : MonoBehaviour
{
    [SerializeField] ScoreService _score;
    [SerializeField] SpawnService _spawner;
    [SerializeField] SaveService _save;
}
```

### Magic strings vers constantes/enum

Avant :
```csharp
if (other.CompareTag("Player")) { }
animator.SetTrigger("Jump");
var go = GameObject.Find("SpawnPoint");
```

Apres :
```csharp
public static class Tags
{
    public const string Player = "Player";
}

public static class AnimParams
{
    public static readonly int Jump = Animator.StringToHash("Jump");
}

// Usage
if (other.CompareTag(Tags.Player)) { }
animator.SetTrigger(AnimParams.Jump);
```

### Coroutine spaghetti vers async/await

Avant :
```csharp
IEnumerator SpawnSequence()
{
    yield return new WaitForSeconds(1f);
    SpawnWave();
    yield return new WaitUntil(() => enemies.Count == 0);
    yield return new WaitForSeconds(2f);
    SpawnBoss();
}
```

Apres (avec UniTask ou Awaitable Unity 6+) :
```csharp
async Awaitable SpawnSequence(CancellationToken ct)
{
    await Awaitable.WaitForSecondsAsync(1f, ct);
    SpawnWave();
    await Awaitable.WaitUntilAsync(() => enemies.Count == 0, ct);
    await Awaitable.WaitForSecondsAsync(2f, ct);
    SpawnBoss();
}
```

#### Mapping complet des yields

| Coroutine (ancien) | Awaitable (nouveau) |
|---------------------|---------------------|
| `yield return null` | `await Awaitable.NextFrameAsync(destroyCancellationToken)` |
| `yield return new WaitForSeconds(x)` | `await Awaitable.WaitForSecondsAsync(x, destroyCancellationToken)` |
| `yield return new WaitForEndOfFrame()` | `await Awaitable.EndOfFrameAsync(destroyCancellationToken)` |
| `yield return new WaitForFixedUpdate()` | `await Awaitable.FixedUpdateAsync(destroyCancellationToken)` |
| `yield return new WaitUntil(() => cond)` | `while (!cond) await Awaitable.NextFrameAsync(destroyCancellationToken)` |
| `yield return new WaitWhile(() => cond)` | `while (cond) await Awaitable.NextFrameAsync(destroyCancellationToken)` |
| `yield return StartCoroutine(Other())` | `await OtherAsync()` |
| `yield return asyncOperation` | `await asyncOperation` |

**Important** : Toujours passer `destroyCancellationToken` pour annuler automatiquement si le MonoBehaviour est detruit.

**Signature** : Changer `IEnumerator` en `async Awaitable` et ajouter le suffixe `Async` au nom :
```csharp
// Avant
IEnumerator DoSequence() { ... }
StartCoroutine(DoSequence());

// Apres
async Awaitable DoSequenceAsync() { ... }
_ = DoSequenceAsync(); // fire and forget (ou await si appele depuis un autre async)
```

### References directes vers Event Channel SO

Avant :
```csharp
// Couplage direct
public class Player : MonoBehaviour
{
    [SerializeField] UIHealth _healthUI;
    void TakeDamage(int dmg) { _health -= dmg; _healthUI.UpdateBar(_health); }
}
```

Apres :
```csharp
using System;
using UnityEngine;

// Event channel ScriptableObject (meme pattern que unity-code-gen)
[CreateAssetMenu(fileName = "New Int Event", menuName = "Game/Events/Int Event")]
public class IntEventChannelSO : ScriptableObject
{
    private Action<int> _onRaised;

    public void Raise(int value) => _onRaised?.Invoke(value);
    public void Subscribe(Action<int> listener) => _onRaised += listener;
    public void Unsubscribe(Action<int> listener) => _onRaised -= listener;
}

// Publisher (Player) ne connait pas le subscriber (UI)
public class Player : MonoBehaviour
{
    [SerializeField] IntEventChannelSO _onHealthChanged;
    void TakeDamage(int dmg) { _health -= dmg; _onHealthChanged.Raise(_health); }
}

// Subscriber (UI) ne connait pas le publisher
public class UIHealth : MonoBehaviour
{
    [SerializeField] IntEventChannelSO _onHealthChanged;
    void OnEnable() => _onHealthChanged.Subscribe(UpdateBar);
    void OnDisable() => _onHealthChanged.Unsubscribe(UpdateBar);
    void UpdateBar(int hp) { /* update slider */ }
}
```

### Old Input vers New Input System

Le New Input System est le defaut dans Unity 6. Migrer depuis `UnityEngine.Input` vers `UnityEngine.InputSystem`.

Avant :
```csharp
using UnityEngine;

public class PlayerInput : MonoBehaviour
{
    [SerializeField] private float speed = 5f;
    [SerializeField] private float jumpForce = 10f;

    private Rigidbody _rb;

    void Awake() => _rb = GetComponent<Rigidbody>();

    void Update()
    {
        float h = Input.GetAxis("Horizontal");
        float v = Input.GetAxis("Vertical");
        transform.Translate(new Vector3(h, 0, v) * (speed * Time.deltaTime));

        if (Input.GetKeyDown(KeyCode.Space))
            _rb.AddForce(Vector3.up * jumpForce, ForceMode.Impulse);
    }
}
```

Apres :
```csharp
using UnityEngine;
using UnityEngine.InputSystem;

public class PlayerInput : MonoBehaviour
{
    [SerializeField] private float speed = 5f;
    [SerializeField] private float jumpForce = 10f;
    [SerializeField] private InputActionReference moveAction;
    [SerializeField] private InputActionReference jumpAction;

    private Rigidbody _rb;

    void Awake() => _rb = GetComponent<Rigidbody>();

    void OnEnable()
    {
        moveAction.action.Enable();
        jumpAction.action.Enable();
        jumpAction.action.performed += OnJump;
    }

    void OnDisable()
    {
        jumpAction.action.performed -= OnJump;
        moveAction.action.Disable();
        jumpAction.action.Disable();
    }

    void Update()
    {
        Vector2 input = moveAction.action.ReadValue<Vector2>();
        transform.Translate(new Vector3(input.x, 0, input.y) * (speed * Time.deltaTime));
    }

    private void OnJump(InputAction.CallbackContext ctx)
    {
        _rb.AddForce(Vector3.up * jumpForce, ForceMode.Impulse);
    }
}
```

Etapes de migration :
1. Installer le package Input System (`com.unity.inputsystem`)
2. Creer un Input Actions asset (`.inputactions`)
3. Definir les actions (Move: Value/Vector2, Jump: Button)
4. Binder les controls (WASD, Gamepad stick, etc.)
5. Remplacer les appels `Input.*` par des `InputAction` references
6. Enable/Disable les actions dans `OnEnable`/`OnDisable`

#### Mapping des appels courants

| Old Input | New Input System |
|-----------|------------------|
| `Input.GetKey(KeyCode.Space)` | `Keyboard.current[Key.Space].isPressed` ou action |
| `Input.GetKeyDown(KeyCode.Space)` | `Keyboard.current[Key.Space].wasPressedThisFrame` ou action `performed` |
| `Input.GetAxis("Horizontal")` | `action.ReadValue<Vector2>().x` |
| `Input.GetMouseButton(0)` | `Mouse.current.leftButton.isPressed` |
| `Input.mousePosition` | `Mouse.current.position.ReadValue()` |
| `Input.GetButton("Fire1")` | `action.IsPressed()` |
