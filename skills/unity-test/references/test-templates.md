# Unity Test Templates

Reference des templates de tests pour Unity. Copier-coller et adapter.

---

## 1. EditMode — Logique pure

```csharp
using NUnit.Framework;

[TestFixture]
public class HealthCalculatorTests
{
    [Test]
    public void CalculateDamage_NormalHit_ReducesHealth()
    {
        Assert.AreEqual(70, HealthCalculator.CalculateDamage(100, 30));
    }

    [Test]
    public void CalculateDamage_Overkill_ClampsToZero()
    {
        Assert.AreEqual(0, HealthCalculator.CalculateDamage(10, 50));
    }

    [TestCase(100, 0, 100)]
    [TestCase(100, 100, 0)]
    [TestCase(0, 10, 0)]
    public void CalculateDamage_Parametrized(int health, int damage, int expected)
    {
        Assert.AreEqual(expected, HealthCalculator.CalculateDamage(health, damage));
    }
}
```

---

## 2. EditMode — ScriptableObject validation

```csharp
using NUnit.Framework;
using UnityEngine;

[TestFixture]
public class WeaponDataTests
{
    private WeaponData weapon;

    [SetUp]
    public void SetUp() => weapon = ScriptableObject.CreateInstance<WeaponData>();

    [TearDown]
    public void TearDown() => Object.DestroyImmediate(weapon);

    [Test]
    public void Damage_DefaultValue_IsPositive()
    {
        Assert.Greater(weapon.Damage, 0);
    }

    [Test]
    public void FireRate_DefaultValue_IsWithinRange()
    {
        Assert.That(weapon.FireRate, Is.InRange(0.1f, 10f));
    }
}
```

---

## 3. EditMode — State Machine

```csharp
using NUnit.Framework;

[TestFixture]
public class EnemyStateMachineTests
{
    private EnemyStateMachine sm;

    [SetUp]
    public void SetUp() => sm = new EnemyStateMachine();

    [Test]
    public void InitialState_IsIdle()
        => Assert.AreEqual(EnemyState.Idle, sm.CurrentState);

    [Test]
    public void Transition_IdleToPatrol_OnPatrolCommand()
    {
        sm.OnPatrolCommand();
        Assert.AreEqual(EnemyState.Patrol, sm.CurrentState);
    }

    [Test]
    public void Transition_Dead_IgnoresAllCommands()
    {
        sm.OnDeath();
        sm.OnPatrolCommand();
        Assert.AreEqual(EnemyState.Dead, sm.CurrentState);
    }
}
```

---

## 4. PlayMode — MonoBehaviour Lifecycle

```csharp
using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

public class PlayerHealthTests
{
    private GameObject go;
    private PlayerHealth hp;

    [SetUp]
    public void SetUp()
    {
        go = new GameObject("Player");
        hp = go.AddComponent<PlayerHealth>();
    }

    [TearDown]
    public void TearDown() => Object.DestroyImmediate(go);

    [UnityTest]
    public IEnumerator Start_OnInitialize_SetsMaxHealth()
    {
        yield return null; // Attend Start()
        Assert.AreEqual(100, hp.CurrentHealth);
    }

    [UnityTest]
    public IEnumerator TakeDamage_Lethal_TriggersDeathEvent()
    {
        yield return null;
        bool died = false;
        hp.OnDeath += () => died = true;
        hp.TakeDamage(100);
        Assert.IsTrue(died);
    }
}
```

---

## 5. PlayMode — Coroutine / temps reel

```csharp
public class ProjectileTests
{
    private GameObject go;

    [SetUp]
    public void SetUp()
    {
        go = new GameObject("Proj");
        go.AddComponent<Projectile>();
    }

    [TearDown]
    public void TearDown() { if (go != null) Object.DestroyImmediate(go); }

    [UnityTest]
    public IEnumerator Lifetime_AfterDuration_DestroysItself()
    {
        go.GetComponent<Projectile>().SetLifetime(0.1f);
        yield return null;
        yield return new WaitForSeconds(0.2f);
        Assert.IsTrue(go == null); // Detruit par Unity
    }
}
```

---

## 6. Async — Unity 6+

```csharp
// Option A : Wrapping async (toutes versions)
[UnityTest]
public IEnumerator LoadData_ValidInput_ReturnsData()
{
    var task = Task.Run(async () =>
    {
        var result = await new DataService().LoadDataAsync("key");
        Assert.IsNotNull(result);
    });
    while (!task.IsCompleted) yield return null;
    if (task.IsFaulted) throw task.Exception.InnerException;
}

// Option B : Async natif (Unity 6+ / Test Framework 2.0+)
[Test]
public async Task LoadData_ValidKey_ReturnsData()
{
    var result = await new DataService().LoadDataAsync("key");
    Assert.IsNotNull(result);
}
```

---

## 7. Event Channel — ScriptableObject Events

```csharp
[TestFixture]
public class GameEventTests
{
    private GameEvent evt;

    [SetUp]
    public void SetUp() => evt = ScriptableObject.CreateInstance<GameEvent>();
    [TearDown]
    public void TearDown() => Object.DestroyImmediate(evt);

    [Test]
    public void Raise_WithListener_NotifiesListener()
    {
        bool received = false;
        evt.OnRaised += () => received = true;
        evt.Raise();
        Assert.IsTrue(received);
    }

    [Test]
    public void Raise_NoListeners_DoesNotThrow()
        => Assert.DoesNotThrow(() => evt.Raise());
}
```

---

## 8. Mocking Patterns

### Interface + Test Double

```csharp
// Interface de production
public interface IInputProvider { Vector2 GetMovement(); bool GetJump(); }

// Mock pour tests
public class MockInputProvider : IInputProvider
{
    public Vector2 Movement { get; set; }
    public bool Jump { get; set; }
    public Vector2 GetMovement() => Movement;
    public bool GetJump() => Jump;
}

// Utilisation dans un test
[Test]
public void CalculateVelocity_RightInput_MovesRight()
{
    var mock = new MockInputProvider { Movement = Vector2.right };
    var movement = new PlayerMovement();
    movement.SetInputProvider(mock);
    Assert.AreEqual(5f, movement.CalculateVelocity(speed: 5f).x, 0.001f);
}
```

### Spy pattern — enregistre les appels pour verification

```csharp
public class SpyAudioService : IAudioService
{
    public List<string> PlayedSounds { get; } = new();
    public void PlaySound(string clip) => PlayedSounds.Add(clip);
}

[Test]
public void TakeDamage_PlaysHurtSound()
{
    var spy = new SpyAudioService();
    new CombatSystem(spy).TakeDamage(10);
    Assert.Contains("hurt", spy.PlayedSounds);
}
```

---

## 9. Assembly Definition Templates

**EditMode** — `Game.Tests.EditMode.asmdef` :
```json
{ "name": "Game.Tests.EditMode", "references": ["GUID:<runtime-guid>"],
  "includePlatforms": ["Editor"], "overrideReferences": true,
  "precompiledReferences": ["nunit.framework.dll"],
  "defineConstraints": ["UNITY_INCLUDE_TESTS"], "autoReferenced": false }
```

**PlayMode** — `Game.Tests.PlayMode.asmdef` :
```json
{ "name": "Game.Tests.PlayMode",
  "references": ["GUID:<runtime-guid>", "UnityEngine.TestRunner", "UnityEditor.TestRunner"],
  "includePlatforms": [], "overrideReferences": true,
  "precompiledReferences": ["nunit.framework.dll"],
  "defineConstraints": ["UNITY_INCLUDE_TESTS"], "autoReferenced": false }
```

**Runtime** — `Game.Runtime.asmdef` :
```json
{ "name": "Game.Runtime", "references": [], "includePlatforms": [], "autoReferenced": true }
```

---

## 10. Checklist avant soumission

- [ ] Convention de nommage : `MethodName_Condition_ExpectedResult`
- [ ] `[SetUp]` initialise tout, `[TearDown]` detruit tout
- [ ] Pas de dependance entre tests
- [ ] Pas de `Thread.Sleep` — `yield return null` ou `await`
- [ ] Floats avec tolerance : `Assert.AreEqual(expected, actual, 0.001f)`
- [ ] GameObjects detruits avec `Object.DestroyImmediate`
- [ ] Assembly definition correctement configuree
- [ ] Le test passe seul ET avec tous les autres tests
