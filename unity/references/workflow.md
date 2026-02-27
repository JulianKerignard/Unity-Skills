# Unity Workflow: Git, Testing, CI/CD & Builds

Practical setup and processes for a professional Unity development workflow.

## Table of Contents

1. [Version Control (Git)](#1-version-control-git)
2. [Testing](#2-testing)
3. [CI/CD](#3-cicd)
4. [Build & Deployment](#4-build--deployment)

---

## 1. Version Control (Git)

### .gitignore

Unity generates a lot of derived files that should never be committed. Use this as your baseline:

```gitignore
# Unity generated
/[Ll]ibrary/
/[Tt]emp/
/[Oo]bj/
/[Bb]uild/
/[Bb]uilds/
/[Ll]ogs/
/[Uu]ser[Ss]ettings/
/[Mm]emoryCaptures/
/[Rr]ecordings/

# IDE
*.csproj
*.unityproj
*.sln
*.suo
*.user
*.userprefs
*.pidb
*.booproj

# OS
.DS_Store
Thumbs.db

# Other
*.pdb
*.mdb
*.opendb
*.VC.db
crashlytics-buildid.txt
```

### Git LFS

Binary files (textures, models, audio) bloat Git repositories. Git LFS stores them externally while keeping the repo fast:

```bash
git lfs install
git lfs track "*.psd"
git lfs track "*.png"
git lfs track "*.jpg"
git lfs track "*.tga"
git lfs track "*.fbx"
git lfs track "*.obj"
git lfs track "*.wav"
git lfs track "*.mp3"
git lfs track "*.ogg"
git lfs track "*.unitypackage"
git lfs track "*.asset"   # large serialized assets
```

Add these to `.gitattributes` (Git LFS does this automatically).

### Unity Settings for Git

These two settings are required for Git to work well with Unity:

- **Edit > Project Settings > Editor > Asset Serialization Mode**: **Force Text** — makes `.unity` scene files and `.prefab` files diffable and mergeable
- **Edit > Project Settings > Editor > Version Control Mode**: **Visible Meta Files** — every asset gets a `.meta` file that must be committed

### Merge Conflicts

Scene files (`.unity`) and prefabs (`.prefab`) are YAML but hard to merge manually. Strategies:
- Use Unity's **Smart Merge** tool (UnityYAMLMerge) — configure it as your merge tool in `.gitconfig`
- Avoid two people editing the same scene simultaneously — split work across scenes
- Use prefab variants to isolate changes

### Branching Strategy

| Strategy | Best For | Flow |
|---|---|---|
| **Trunk-based** | Small team (1-3), fast iteration | Everyone commits to `main`, use short-lived feature branches (<1 day) |
| **Git Flow** | Larger team, release cycles | `main` (releases) ← `develop` ← `feature/*` branches, `hotfix/*` for urgent fixes |
| **GitHub Flow** | Medium team, continuous delivery | `main` + feature branches, merge via PR |

**Recommended for most Unity projects:** GitHub Flow with these conventions:
- `main` — always buildable, protected branch
- `feature/player-combat` — descriptive feature branches
- `fix/camera-clipping` — bug fix branches
- `art/goblin-redesign` — art branches (warn: binary conflicts are hard to merge)

### Git LFS Locks

Binary files (scenes, prefabs, textures) can't be merged. Use LFS file locking to prevent conflicts:

```bash
# Lock a file before editing (prevents others from pushing changes)
git lfs lock "Assets/_Project/Scenes/Level_01.unity"

# See all locks
git lfs locks

# Unlock when done
git lfs unlock "Assets/_Project/Scenes/Level_01.unity"

# Force unlock (admin, if someone forgot)
git lfs unlock --force "Assets/_Project/Scenes/Level_01.unity"
```

Configure `.gitattributes` to make locking the default for binary assets:
```
*.unity lockable
*.prefab lockable
*.asset lockable
*.fbx lockable
*.psd lockable
```

### Pre-Commit Hooks

Catch common mistakes before they enter the repo:

```bash
#!/bin/sh
# .git/hooks/pre-commit — or use Husky / pre-commit framework

# Prevent committing .meta files without their asset (orphaned metas)
ORPHANED=$(git diff --cached --name-only --diff-filter=A | grep '\.meta$' | while read meta; do
    asset="${meta%.meta}"
    if ! git diff --cached --name-only | grep -qF "$asset"; then
        echo "$meta"
    fi
done)

if [ -n "$ORPHANED" ]; then
    echo "ERROR: Orphaned .meta files detected (asset missing):"
    echo "$ORPHANED"
    exit 1
fi

# Prevent committing files with spaces in names
SPACES=$(git diff --cached --name-only | grep ' ')
if [ -n "$SPACES" ]; then
    echo "ERROR: File names with spaces detected:"
    echo "$SPACES"
    exit 1
fi

echo "Pre-commit checks passed."
```

---

## 2. Testing

### Test Architecture: Separate Logic from MonoBehaviours

The key to testable Unity code is keeping business logic in plain C# classes that don't depend on MonoBehaviour. MonoBehaviours become thin wrappers that delegate to the logic classes.

```csharp
// Testable logic — no Unity dependency
public class HealthLogic
{
    public int Current { get; private set; }
    public int Max { get; }
    public bool IsDead => Current <= 0;

    public HealthLogic(int max) { Max = max; Current = max; }

    public int TakeDamage(int dmg)
    {
        Current = Math.Max(0, Current - dmg);
        return Current;
    }

    public int Heal(int amount)
    {
        Current = Math.Min(Max, Current + amount);
        return Current;
    }
}

// Thin MonoBehaviour wrapper
public class PlayerHealth : MonoBehaviour
{
    [SerializeField] private int _maxHealth = 100;
    private HealthLogic _logic;

    private void Awake() => _logic = new HealthLogic(_maxHealth);
    public void TakeDamage(int d) => _logic.TakeDamage(d);
}
```

### Edit Mode Tests (Unit Tests)

Fast, don't need Unity runtime, test pure logic:

```csharp
using NUnit.Framework;

[TestFixture]
public class HealthLogicTests
{
    [Test]
    public void TakeDamage_ReducesHealth()
    {
        var h = new HealthLogic(100);
        h.TakeDamage(30);
        Assert.AreEqual(70, h.Current);
    }

    [Test]
    public void TakeDamage_ClampsToZero()
    {
        var h = new HealthLogic(50);
        h.TakeDamage(999);
        Assert.AreEqual(0, h.Current);
        Assert.IsTrue(h.IsDead);
    }

    [Test]
    public void Heal_ClampsToMax()
    {
        var h = new HealthLogic(100);
        h.TakeDamage(60);
        h.Heal(999);
        Assert.AreEqual(100, h.Current);
    }
}
```

### Play Mode Tests (Integration Tests)

Require Unity runtime, slower, but test real component interaction:

```csharp
using NUnit.Framework;
using UnityEngine.TestTools;
using System.Collections;
using UnityEngine;

public class PlayerIntegrationTests
{
    [UnityTest]
    public IEnumerator Player_TakesDamage_HealthBarUpdates()
    {
        var go = new GameObject("Player");
        var health = go.AddComponent<PlayerHealth>();

        // Wait a frame for Start()
        yield return null;

        health.TakeDamage(30);
        yield return null;

        // Assert health bar value etc.
    }
}
```

### When to Write Which

| Test Type | Speed | Use For |
|---|---|---|
| Edit Mode | Fast (ms) | Algorithms, data transforms, state machines, calculations |
| Play Mode | Slow (frames) | Component interaction, physics, coroutines, UI flows |

Aim for: most logic testable in Edit Mode, only integration points in Play Mode.

### Testing Async Code (Unity 6+)

Les tests de code asynchrone utilisant `Awaitable` necessitent une approche specifique :

**EditMode — logique async pure (sans Unity lifecycle) :**
```csharp
[Test]
public async Task AsyncCalculation_ReturnsCorrectResult()
{
    var service = new DataService();
    var result = await service.ProcessAsync();
    Assert.AreEqual(42, result);
}
```

**PlayMode — avec Unity lifecycle :**
```csharp
[UnityTest]
public IEnumerator AsyncSpawn_CreatesObject() => AsyncTestRunner.Run(async () =>
{
    var spawner = new GameObject().AddComponent<AsyncSpawner>();
    await spawner.SpawnAsync();
    Assert.IsNotNull(GameObject.Find("SpawnedObject"));
});

// Helper pour wrapper async dans IEnumerator
public static class AsyncTestRunner
{
    public static IEnumerator Run(Func<Task> asyncTest)
    {
        var task = asyncTest();
        while (!task.IsCompleted) yield return null;
        if (task.IsFaulted) throw task.Exception.InnerException;
    }
}
```

**Points cles :**
- `destroyCancellationToken` n'existe pas dans les tests (pas de MonoBehaviour detruit) — utiliser un `CancellationTokenSource` explicite si necessaire
- Les `[UnityTest]` retournent `IEnumerator`, wrapper les appels async
- Timeout : ajouter `[Timeout(5000)]` pour eviter les tests qui pendent

---

## 3. CI/CD

### Unity Cloud Build

Unity's built-in CI/CD solution. Supports all target platforms, automatic builds on push/PR, build history and logs.

### Self-Hosted (GitHub Actions / GitLab CI)

Use **GameCI** Docker images for Unity builds in any CI:

```yaml
# .github/workflows/build.yml (simplified)
name: Unity Build
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          lfs: true
      - uses: game-ci/unity-builder@v4
        with:
          targetPlatform: StandaloneWindows64
          unityVersion: 6000.0.23f1
```

### game-ci v4+ (2024-2025)

game-ci a ete mis a jour avec le support Unity 6 :

```yaml
# .github/workflows/unity-test.yml (game-ci v4+)
name: Unity Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          lfs: true

      - uses: game-ci/unity-test-runner@v4
        env:
          UNITY_LICENSE: ${{ secrets.UNITY_LICENSE }}
        with:
          unityVersion: 6000.0.23f1  # Unity 6 version format
          testMode: all
          artifactsPath: test-results
          coverageOptions: 'generateAdditionalMetrics;generateHtmlReport'

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: test-results
```

**Changements cles v4 :**
- Support Unity 6 (format version `6000.x.y`)
- Actions GitHub v4 (`actions/checkout@v4`, `actions/upload-artifact@v4`)
- Meilleur support des tests async
- Coverage HTML report integre

### What to Automate

- **Build** on every push to `main` or `develop`
- **Edit Mode tests** on every PR
- **Play Mode tests** on nightly builds (slower)
- **Build size tracking** to catch regressions
- **Code analysis** (Roslyn analyzers, .editorconfig enforcement)

### Build Profiles dans CI/CD (Unity 6+)

Les Build Profiles modifient les commandes CLI pour le CI :

```bash
# Avant (Build Settings)
unity-editor -batchmode -buildTarget Android -executeMethod BuildScript.Build

# Apres (Build Profiles)
unity-editor -batchmode \
  -activeBuildProfile "Assets/Settings/BuildProfiles/Android_Release.buildprofile" \
  -executeMethod BuildScript.Build
```

**Dans GitHub Actions :**
```yaml
- uses: game-ci/unity-builder@v4
  with:
    unityVersion: 6000.0.23f1
    buildMethod: BuildScript.Build
    customParameters: '-activeBuildProfile Assets/Settings/BuildProfiles/${{ matrix.profile }}.buildprofile'
```

**Matrice de builds multi-profil :**
```yaml
strategy:
  matrix:
    profile: [Android_Release, iOS_Release, WebGL_Demo]
```

---

## 4. Build & Deployment

### Pre-Ship Checklist

- [ ] Profile on **target hardware** (not Editor)
- [ ] Enable **IL2CPP** backend (better perf, code protection)
- [ ] Strip unused code (Managed Stripping Level: High + `link.xml` for preserved types)
- [ ] Strip unused shader variants (Graphics settings)
- [ ] Set platform-appropriate compression (LZ4 for fast load, LZMA for smaller download)
- [ ] Replace all `Debug.Log` with conditional logging (see performance reference)
- [ ] Verify Addressable groups are configured and built
- [ ] Check memory with Memory Profiler — look for unexpected large allocations
- [ ] Set up crash reporting (Sentry, Firebase Crashlytics, or Unity Cloud Diagnostics)
- [ ] Test on minimum-spec devices for each target platform
- [ ] Validate input on all target devices (keyboard, gamepad, touch)
- [ ] Run full test suite (Edit Mode + Play Mode)

### IL2CPP Notes

IL2CPP converts C# to C++ for the final build. Benefits: better runtime performance, smaller binary, harder to reverse-engineer. The main gotcha: reflection and generic types need entries in `link.xml` to survive stripping.

```xml
<!-- link.xml — preserve types that are only used via reflection -->
<linker>
    <assembly fullname="Assembly-CSharp">
        <type fullname="MyNamespace.SaveData" preserve="all"/>
    </assembly>
</linker>
```

### Platform-Specific Tips

| Platform | Key Consideration |
|---|---|
| **Mobile (iOS/Android)** | Battery, thermal throttling, ASTC textures, App Store guidelines |
| **PC (Steam)** | Wide hardware range, quality settings tiers, Steam Input API |
| **Console (PS5/Xbox/Switch)** | Certification requirements, memory limits (Switch especially), TRC/XR/Lotcheck |
| **WebGL** | No threading, limited memory, async loading, compression crucial |
| **VR** | 90fps minimum, motion sickness prevention, single-pass instanced rendering |
