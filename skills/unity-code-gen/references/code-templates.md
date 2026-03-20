# Unity Code Gen — Templates de reference

Templates production-ready pour chaque pattern supporte par la skill `/unity-code-gen`.
Chaque template inclut les conventions Unity (attributs, structure, nommage) et des placeholders a personnaliser.

---

## 1. MonoBehaviour Component

Composant standard attache a un GameObject. Utiliser pour tout comportement runtime dans la scene.

```csharp
using UnityEngine;

namespace Game.Module
{
    [RequireComponent(typeof(Rigidbody))]
    public class ComponentName : MonoBehaviour
    {
        [Header("Configuration")]
        [SerializeField, Tooltip("Description du champ")]
        private float _speed = 5f;

        [Header("References")]
        [SerializeField] private Transform _target;

        public event System.Action<float> OnValueChanged;

        public float Speed => _speed;

        private Rigidbody _rb;

        private void Awake()
        {
            _rb = GetComponent<Rigidbody>();
        }

        private void OnDestroy()
        {
            // Cleanup
        }
    }
}
```

---

## 2. ScriptableObject Data Container

Container de donnees configurables via l'Inspector. Utiliser pour les stats, settings, items, et toute donnee partagee entre scenes.

```csharp
using UnityEngine;

namespace Game.Data
{
    [CreateAssetMenu(fileName = "New ItemData", menuName = "Game/Item Data")]
    public class ItemDataSO : ScriptableObject
    {
        [Header("Identity")]
        [SerializeField] private string _itemName;
        [SerializeField, TextArea(2, 5)] private string _description;

        [Header("Stats")]
        [SerializeField, Range(1, 999)] private int _value = 1;
        [SerializeField] private Sprite _icon;

        public string ItemName => _itemName;
        public string Description => _description;
        public int Value => _value;
        public Sprite Icon => _icon;
    }
}
```

---

## 3. ScriptableObject Event Channel (pub/sub)

Canal de communication decouple entre systemes. Utiliser pour les events cross-systemes sans references directes.

```csharp
using System;
using UnityEngine;

namespace Game.Events
{
    [CreateAssetMenu(fileName = "New Event", menuName = "Game/Events/Void Event")]
    public class VoidEventChannelSO : ScriptableObject
    {
        private Action _onRaised;

        public void Raise() => _onRaised?.Invoke();
        public void Subscribe(Action listener) => _onRaised += listener;
        public void Unsubscribe(Action listener) => _onRaised -= listener;
    }

    // Variante typee
    [CreateAssetMenu(fileName = "New Int Event", menuName = "Game/Events/Int Event")]
    public class IntEventChannelSO : ScriptableObject
    {
        private Action<int> _onRaised;

        public void Raise(int value) => _onRaised?.Invoke(value);
        public void Subscribe(Action<int> listener) => _onRaised += listener;
        public void Unsubscribe(Action<int> listener) => _onRaised -= listener;
    }
}
```

---

## 4. Interface + Implementation

Contrat pour du polymorphisme propre. Utiliser quand plusieurs classes doivent respecter le meme contrat (dommages, interactions, sauvegardes).

```csharp
namespace Game.Core
{
    public interface IDamageable
    {
        int CurrentHealth { get; }
        int MaxHealth { get; }
        bool IsAlive { get; }
        void TakeDamage(int amount, DamageInfo info);
    }

    public readonly struct DamageInfo
    {
        public readonly Vector3 Origin;
        public readonly DamageType Type;

        public DamageInfo(Vector3 origin, DamageType type)
        {
            Origin = origin;
            Type = type;
        }
    }
}
```

---

## 5. State Machine (enum + switch)

Machine a etats simple basee sur un enum. Utiliser pour les etats d'IA, du joueur, ou du game flow quand le nombre d'etats est limite (< 8).

```csharp
using UnityEngine;

namespace Game.AI
{
    public class EnemyStateMachine : MonoBehaviour
    {
        public enum State { Idle, Patrol, Chase, Attack, Dead }

        [SerializeField] private State _initialState = State.Idle;

        private State _currentState;

        public State CurrentState => _currentState;

        private void Awake() => TransitionTo(_initialState);

        private void Update() => UpdateState();

        public void TransitionTo(State newState)
        {
            ExitState(_currentState);
            _currentState = newState;
            EnterState(newState);
        }

        private void EnterState(State state)
        {
            switch (state)
            {
                case State.Idle: /* init idle */ break;
                case State.Patrol: /* init patrol */ break;
                case State.Chase: /* init chase */ break;
                case State.Attack: /* init attack */ break;
                case State.Dead: /* init dead */ break;
            }
        }

        private void UpdateState()
        {
            switch (_currentState)
            {
                case State.Idle: UpdateIdle(); break;
                case State.Patrol: UpdatePatrol(); break;
                case State.Chase: UpdateChase(); break;
                case State.Attack: UpdateAttack(); break;
            }
        }

        private void ExitState(State state) { /* cleanup par etat */ }

        private void UpdateIdle() { }
        private void UpdatePatrol() { }
        private void UpdateChase() { }
        private void UpdateAttack() { }
    }
}
```

---

## 6. Command Pattern (Input)

Pattern commande pour les inputs avec support undo/replay. Utiliser pour les actions joueur reversibles (editeurs, jeux de strategie, puzzles).

```csharp
namespace Game.Input
{
    public interface ICommand
    {
        void Execute();
        void Undo();
    }

    public class MoveCommand : ICommand
    {
        private readonly Transform _target;
        private readonly Vector3 _direction;
        private Vector3 _previousPosition;

        public MoveCommand(Transform target, Vector3 direction)
        {
            _target = target;
            _direction = direction;
        }

        public void Execute()
        {
            _previousPosition = _target.position;
            _target.position += _direction;
        }

        public void Undo() => _target.position = _previousPosition;
    }
}
```

---

## 7. Object Pool

Pool d'objets pour eviter les allocations repetees. Utiliser pour les projectiles, VFX, ennemis, et tout objet instancie/detruit frequemment.

```csharp
using UnityEngine;
using UnityEngine.Pool;

namespace Game.Core
{
    public class ProjectilePool : MonoBehaviour
    {
        [SerializeField] private Projectile _prefab;
        [SerializeField] private int _defaultCapacity = 20;
        [SerializeField] private int _maxSize = 100;

        private ObjectPool<Projectile> _pool;

        private void Awake()
        {
            _pool = new ObjectPool<Projectile>(
                createFunc: () => Instantiate(_prefab),
                actionOnGet: p => p.gameObject.SetActive(true),
                actionOnRelease: p => p.gameObject.SetActive(false),
                actionOnDestroy: p => Destroy(p.gameObject),
                defaultCapacity: _defaultCapacity,
                maxSize: _maxSize
            );
        }

        public Projectile Get() => _pool.Get();
        public void Release(Projectile p) => _pool.Release(p);
    }
}
```

---

## 8. Async Awaitable Component (Unity 6+)

Composant asynchrone utilisant l'API Awaitable de Unity 6. Utiliser pour le chargement de donnees, les timers, les sequences, et toute logique asynchrone qui doit respecter le cycle de vie du GameObject.

Points cles :
- `Awaitable.BackgroundThreadAsync()` pour le travail lourd hors main thread
- `Awaitable.MainThreadAsync()` pour revenir au main thread (appels Unity API)
- `destroyCancellationToken` pour annuler automatiquement quand le GameObject est detruit
- `Awaitable.WaitForSecondsAsync()` remplace les coroutines de type timer

```csharp
using UnityEngine;

/// <summary>
/// [Description] — Async component using Unity 6 Awaitable API.
/// </summary>
public class AsyncDataLoader : MonoBehaviour
{
    [Header("Configuration")]
    [SerializeField] private string dataUrl;
    [SerializeField] private float retryDelay = 2f;
    [SerializeField] private int maxRetries = 3;

    private bool isLoading;

    private async void Start()
    {
        await LoadDataAsync();
    }

    public async Awaitable LoadDataAsync()
    {
        if (isLoading) return;
        isLoading = true;

        try
        {
            // Switch to background thread for heavy processing
            await Awaitable.BackgroundThreadAsync();
            var data = ProcessHeavyData();

            // Switch back to main thread for Unity API calls
            await Awaitable.MainThreadAsync();
            ApplyData(data);
        }
        catch (OperationCanceledException)
        {
            // Object was destroyed, exit gracefully
        }
        finally
        {
            isLoading = false;
        }
    }

    public async Awaitable WaitAndExecuteAsync(float delay)
    {
        // Always use destroyCancellationToken to auto-cancel on destroy
        await Awaitable.WaitForSecondsAsync(delay, destroyCancellationToken);
        Execute();
    }

    private object ProcessHeavyData() { /* ... */ return null; }
    private void ApplyData(object data) { /* ... */ }
    private void Execute() { /* ... */ }

    private void OnDestroy()
    {
        // destroyCancellationToken automatically cancels all pending Awaitables
    }
}
```

---

## 9. InstantiateAsync Pattern (Unity 6)

Instanciation asynchrone de prefabs en batch. Utiliser pour spawner des groupes d'objets sans freeze (spawners, generation procedurale, chargement de niveaux).

Points cles :
- `Object.InstantiateAsync()` retourne un `AsyncInstantiateOperation<T>` awaitable
- Lancer plusieurs instanciations en parallele, puis await les resultats
- Combine bien avec le pattern Object Pool pour le pre-remplissage asynchrone

```csharp
using UnityEngine;

/// <summary>
/// Spawns groups of objects asynchronously using Unity 6 InstantiateAsync.
/// </summary>
public class AsyncSpawner : MonoBehaviour
{
    [SerializeField] private GameObject prefab;
    [SerializeField] private int spawnCount = 10;

    public async Awaitable SpawnGroupAsync(Vector3 center, float radius)
    {
        var results = new AsyncInstantiateOperation<GameObject>[spawnCount];

        for (int i = 0; i < spawnCount; i++)
        {
            var pos = center + Random.insideUnitSphere * radius;
            var rot = Quaternion.identity;
            results[i] = Object.InstantiateAsync(prefab, pos, rot);
        }

        // Wait for all to complete
        foreach (var op in results)
        {
            await op;
            // op.Result[0] is the instantiated object
        }
    }
}
```
