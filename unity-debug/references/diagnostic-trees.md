# Arbres diagnostiques Unity Debug

Reference detaillee des arbres de diagnostic par categorie de bug. Utilise par la skill `/unity-debug`.

---

## ARBRE NULL REF — NullReferenceException

```
La reference null est...
|
+-- Un [SerializeField] ?
|   +-- Visible dans l'Inspector mais vide -> reference non assignee (drag & drop manquant)
|   +-- Pas visible -> champ renomme ? Unity perd la serialisation au renommage
|
+-- Un GetComponent result ?
|   +-- Le composant est-il sur le meme GameObject ? -> verifier le prefab
|   +-- Appele dans Awake mais depend d'un autre Awake ? -> ordre d'execution
|   +-- Utilise GetComponent au lieu de TryGetComponent -> pas de gestion d'absence
|
+-- Un Find/FindObjectOfType result ?
|   +-- L'objet existe-t-il dans la scene ? -> verifier nom exact, casse
|   +-- L'objet est-il actif ? -> Find ignore les inactifs
|
+-- Un objet detruit (Destroy) ?
|   +-- Acces apres Destroy dans le meme frame -> Destroy est differe a la fin du frame
|   +-- Callback/event qui reference un objet detruit -> desubscribe dans OnDestroy
|
+-- Un resultat de coroutine/async ?
|   +-- L'objet a-t-il ete detruit pendant le yield ? -> verifier `this != null` apres yield
|
+-- Un acces a un composant UI ?
    +-- L'UI est-elle instanciee ? Le Canvas est-il actif ? -> timing d'initialisation
```

---

## ARBRE MISSING COMPONENT — MissingComponentException

```
+-- Le composant est-il sur le prefab ? -> verifier le prefab original
+-- AddComponent appele avant que le GO existe ? -> verifier le timing
+-- [RequireComponent] manquant ? -> ajouter l'attribut pour garantir la presence
+-- Composant supprime manuellement dans l'Inspector ? -> chercher dans le prefab
+-- Script manquant (fichier supprime/renomme) ? -> chercher les "Missing Script" dans la scene
```

---

## ARBRE RACE CONDITION / TIMING

```
+-- Awake vs Start -> Awake : config interne. Start : references externes
+-- Ordre d'execution entre scripts -> Edit > Project Settings > Script Execution Order
+-- OnEnable appele avant Start -> OnEnable est appele a chaque activation, meme la premiere
+-- Coroutine timing -> yield return null = frame suivante, pas "immediatement"
+-- Event souscrit trop tard -> l'event a deja fire avant la subscription
+-- DontDestroyOnLoad -> verifier les duplications au rechargement de scene
```

---

## ARBRE SERIALISATION

```
+-- Champ non serialise -> manque [Serializable] sur le struct/class, ou c'est une interface
+-- Dictionary non serialisable -> Unity ne serialise pas Dictionary, utiliser 2 listes ou un SO
+-- Champ abstract/interface -> Unity ne serialise pas les interfaces, utiliser [SerializeReference]
+-- ScriptableObject remis a zero -> modifications runtime sur SO persistent en Editor mais pas en build
+-- Valeurs perdues apres rename -> le rename casse la serialisation, utiliser [FormerlySerializedAs]
```

---

## ARBRE PHYSICS

```
+-- Objet traverse les murs -> ContinuousDynamic collision detection, ou scale trop petit
+-- Jitter de mouvement -> utiliser Rigidbody.MovePosition dans FixedUpdate, pas transform.position
+-- Collision non detectee -> verifier Layer Collision Matrix (Project Settings > Physics)
+-- Trigger non appele -> au moins un des deux a un Rigidbody ? isTrigger coche ?
+-- Force n'a pas d'effet -> Rigidbody isKinematic est-il true ?
+-- Comportement physique bizarre -> echelle non-uniforme sur les colliders parents
```

---

## ARBRE ASYNC/AWAITABLE

```
Probleme async / Awaitable ?
|
+-- Exception non capturee ?
|   +-- `async void` utilise ?
|   |   +-- FIX: Changer en `async Awaitable` (pas void sauf event handlers)
|   +-- Pas de try/catch autour de await ?
|       +-- FIX: Encapsuler dans try/catch, log OperationCanceledException separement
|
+-- Awaitable ne se complete jamais ?
|   +-- Objet detruit pendant l'await ?
|   |   +-- FIX: Utiliser `destroyCancellationToken`
|   +-- Deadlock MainThread ?
|   |   +-- FIX: Verifier pas de `.Result` ou `.Wait()` sur main thread
|   +-- Awaitable jamais resolu ?
|       +-- FIX: Verifier AwaitableCompletionSource.SetResult() est appele
|
+-- Awaitable continue apres destruction ?
|   +-- FIX: Toujours passer `destroyCancellationToken`:
|       await Awaitable.WaitForSecondsAsync(1f, destroyCancellationToken);
|
+-- Code execute sur le mauvais thread ?
|   +-- Unity API appelee depuis background thread ?
|   |   +-- FIX: await Awaitable.MainThreadAsync() avant l'appel Unity
|   +-- Calcul lourd bloque le main thread ?
|       +-- FIX: await Awaitable.BackgroundThreadAsync() avant le calcul
|
+-- Multiple awaitables interferent ?
    +-- FIX: Chaque async method doit etre independante avec son propre flow
```

### Pattern defensif destroyCancellationToken

```csharp
// Pattern defensif Awaitable
async Awaitable DoWorkSafelyAsync()
{
    try
    {
        await Awaitable.WaitForSecondsAsync(2f, destroyCancellationToken);
        // Ce code ne s'execute que si l'objet existe encore
        transform.position = Vector3.zero;
    }
    catch (OperationCanceledException)
    {
        // Objet detruit — sortie propre, pas de log necessaire
    }
}

// DANGEREUX — pas de cancellation token
async Awaitable DoWorkUnsafeAsync()
{
    await Awaitable.WaitForSecondsAsync(2f); // Continue meme si objet detruit!
    transform.position = Vector3.zero; // MissingReferenceException!
}
```

### Pattern thread switching

```csharp
async Awaitable LoadAndApplyAsync()
{
    // Calcul lourd sur background thread
    await Awaitable.BackgroundThreadAsync();
    var data = HeavyComputation();

    // Retour sur main thread pour toucher Unity API
    await Awaitable.MainThreadAsync();
    _renderer.material.color = data.color;
}
```

### Pattern AwaitableCompletionSource

```csharp
private AwaitableCompletionSource _completionSource;

void Start()
{
    _completionSource = new AwaitableCompletionSource();
}

async Awaitable WaitForCustomEvent()
{
    await _completionSource.Awaitable;
    // Continue apres SetResult()
}

// Appele quand l'evenement se produit
public void OnCustomEvent()
{
    _completionSource.SetResult();
    _completionSource = new AwaitableCompletionSource(); // Reset pour reutilisation
}
```
