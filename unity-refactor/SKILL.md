---
name: "Unity Refactor"
description: "Refactoring incremental et securise de code C# Unity. Detecte les code smells, propose un plan priorise par risque, et execute les changements un par un avec verification de compilation. Triggers: /unity-refactor, 'refactor', 'code smell', 'clean code', 'dette technique', 'refactoring unity'. Produit du code restructure sans changement de comportement."
---

# Unity Refactor

## Ce que fait cette skill

Cette skill analyse une codebase Unity C# pour detecter les code smells, propose un plan de refactoring priorise par niveau de risque, puis execute les changements un par un avec verification apres chaque modification. L'objectif est d'ameliorer la qualite du code sans jamais changer le comportement existant.

## Prerequis

- Projet Unity avec du code C# existant dans `Assets/Scripts/`
- Pas de dependance MCP Unity : utilise uniquement Read, Write, Edit, Grep, Glob, Bash

## Demarrage rapide

1. Scanner la codebase pour detecter les code smells
2. Classer et prioriser les refactorings par risque
3. Presenter le plan a l'utilisateur
4. Executer UN refactoring a la fois
5. Verifier compilation + references apres chaque changement
6. Repeter jusqu'a completion du plan

## Guide etape par etape

### Etape 1 : Scanner la codebase pour les code smells

Lancer toutes les detections en parallele avec Grep, Glob et Bash :

```
Glob : Assets/Scripts/**/*.cs                                    # Tous les fichiers C#
Bash : find Assets/Scripts -name "*.cs" -exec wc -l {} + | sort -rn | head -20  # Fichiers volumineux
Grep : "static\s+\w+\s+Instance" dans Assets/Scripts/**/*.cs    # Singletons
Grep : "void\s+Update\s*\(\)" dans Assets/Scripts/**/*.cs       # Update polling
Grep : "Find\(\"" dans Assets/Scripts/**/*.cs                    # Magic strings (Find)
Grep : "CompareTag\(\"" dans Assets/Scripts/**/*.cs              # Magic strings (Tags)
Grep : "StartCoroutine" dans Assets/Scripts/**/*.cs              # Coroutine spaghetti
Grep : "public\s+(?!void|static|override|class)" dans *.cs      # Champs publics exposes
Grep : "class\s+\w+\s*:\s*\w+" dans Assets/Scripts/**/*.cs      # Heritage (tracer les chaines)
```

### Etape 2 : Classer et prioriser

Utiliser le catalogue de refactoring ci-dessous pour classer chaque smell detecte.

#### Catalogue de refactoring Unity

| Smell | Pattern de detection (Grep) | Refactoring | Risque |
|-------|----------------------------|-------------|--------|
| God Manager (>500 lignes) | Fichiers .cs avec "Manager" > 500 lignes | Split en services focuses | Eleve |
| Singleton MonoBehaviour | `static.*Instance.*get` dans MonoBehaviour | Remplacer par SO + Service Locator | Eleve |
| Heritage profond (>3 niveaux) | Chaines de `class X : Y` sur >3 niveaux | Aplatir avec composition + interfaces | Eleve |
| Update polling | `Update()` avec checks booleens | Remplacer par events/callbacks | Moyen |
| God Update | `Update()` avec >5 responsabilites | Separer en composants distincts | Moyen |
| Feature envy | Methodes accedant intensivement aux donnees d'une autre classe | Deplacer la methode vers le proprietaire des donnees | Moyen |
| Primitive obsession | Groupes repetes de int/float/string | Extraire en value types/structs | Moyen |
| Magic strings | `"string"` dans Find/CompareTag/Animator | Remplacer par const/enum/SO | Faible |
| Champs publics Inspector | Nombreux champs `public` | `[SerializeField] private` + SO config | Faible |
| Methode geante (>50 lignes) | Methodes longues | Extraire des sous-methodes | Faible |

#### Seuils de detection

| Metrique | Seuil | Verdict |
|----------|-------|---------|
| Lignes par classe | > 500 | God class |
| Lignes par methode | > 50 | Methode trop longue |
| Methodes par classe | > 15 | Trop de responsabilites |
| Parametres par methode | > 5 | Parameter object necessaire |
| Niveaux d'heritage | > 3 | Aplatir la hierarchie |

#### Ordre de priorite

Toujours commencer par les refactorings a **risque faible**, puis monter progressivement :

```
1. Faible  : Magic strings, champs publics, methodes longues
2. Moyen   : Update polling, feature envy, primitive obsession, God Update
3. Eleve   : Singletons, God classes, heritage profond
```

### Etape 3 : Presenter le plan a l'utilisateur

Avant toute modification, presenter un tableau recapitulatif :

```
## Plan de refactoring propose

| # | Fichier | Smell | Refactoring propose | Risque | Fichiers impactes |
|---|---------|-------|---------------------|--------|-------------------|
| 1 | PlayerManager.cs | Magic strings | Extraire constantes | Faible | 1 |
| 2 | EnemyController.cs | Methode geante | Extraire methodes | Faible | 1 |
| 3 | GameManager.cs | God class (800L) | Split en services | Eleve | 12 |

Voulez-vous proceder ? (tout / selection / annuler)
```

Attendre la validation avant de commencer.

### Etape 4 : Executer UN refactoring a la fois

Pour chaque refactoring du plan valide :

```
1. Read : Lire le fichier cible completement
2. Grep : Identifier TOUTES les references au code qui va changer
         Grep : "NomClasse" dans Assets/Scripts/**/*.cs
         Grep : "NomMethode" dans Assets/Scripts/**/*.cs
3. Edit : Effectuer le changement (une seule modification atomique)
4. Edit : Mettre a jour toutes les references trouvees
5. Grep : Verifier qu'aucune reference orpheline ne subsiste
6. Passer au refactoring suivant
```

### Etape 5 : Verifier apres chaque changement

Apres chaque refactoring individuel :

```
1. Grep pour les anciens noms de classes/methodes : doit retourner 0 resultats
2. Grep pour les references cassees : "using.*OldNamespace" absent
3. Verifier coherence : les nouveaux fichiers sont dans le bon dossier
4. Verifier que les [SerializeField] et references Inspector ne sont pas casses
```

Si un probleme est detecte, annuler le changement et notifier l'utilisateur avant de continuer.

### Etape 6 : Repeter jusqu'a completion

Parcourir le plan dans l'ordre de priorite (risque faible en premier). Apres chaque refactoring termine, indiquer la progression :

```
[2/8] Termine : EnemyController.cs - Extraction de methodes
       Fichiers modifies : 1
       References mises a jour : 0
       Status : OK
```

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

Apres (avec UniTask ou Awaitable Unity 2023+) :
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

## Regles strictes

- **JAMAIS** faire 2 refactorings en meme temps sur le meme fichier
- **JAMAIS** changer le comportement observable (refactoring != nouvelle feature)
- **JAMAIS** renommer un champ `[SerializeField]` sans avertir que les references Inspector seront perdues
- **JAMAIS** supprimer du code sans verifier toutes les references (Grep dans tout le projet)
- **JAMAIS** refactorer un fichier sans l'avoir lu completement d'abord
- **TOUJOURS** verifier la compilation apres chaque changement individuel
- **TOUJOURS** verifier les references cassees avec Grep apres un renommage
- **TOUJOURS** presenter le plan complet avant la premiere modification
- **TOUJOURS** commencer par les refactorings a risque faible
- **TOUJOURS** preferer le plus petit changement possible
- **TOUJOURS** utiliser Edit (pas Write) pour les modifications de fichiers existants
- **TOUJOURS** preserver les attributs Unity (`[SerializeField]`, `[Header]`, `[Tooltip]`, etc.)

## Skills connexes

- Generer du nouveau code propre ? Utiliser `/unity-code-gen` (Unity Code Gen)
- Audit de performance (detection sans refactoring) ? Utiliser `/perf-audit` (Unity Perf Audit)
- Tester le code apres refactoring ? Utiliser `/unity-test` (Unity Test)

## Troubleshooting

| Probleme | Solution |
|----------|----------|
| References Inspector cassees apres renommage de champ | Le champ `[SerializeField]` a ete renomme. Utiliser `[FormerlySerializedAs("oldName")]` pour migrer les donnees serialisees |
| Erreur de compilation apres split de classe | Verifier les `using` manquants dans les nouveaux fichiers et les references d'assembly definition |
| Comportement change apres refactoring | Annuler le changement (Edit pour restaurer), analyser la difference, et refaire avec une approche plus conservatrice |
| Prefab override perdu | Le champ a change de nom ou de type. Ajouter `[FormerlySerializedAs]` et re-verifier les prefabs concernes |
| Circular dependency apres split | Extraire une interface dans un assembly partage, ou inverser la dependance avec un event channel SO |
| Tests cassent apres refactoring | Les tests testaient l'implementation (noms de methodes) plutot que le comportement. Mettre a jour les tests pour utiliser les nouveaux noms |
| AnimatorController reference cassee | Les string parameters ont ete remplaces par des hash. Verifier que `Animator.StringToHash` est utilise avec la meme string que dans le controller |
| ScriptableObject reference null | L'asset SO n'a pas ete cree dans le projet. Creer l'asset via le menu `Create` et l'assigner dans l'Inspector |
