---
name: "Unity Debug"
description: "Diagnostic et correction systematique de bugs Unity par analyse de code. Classifie le bug, trace le chemin d'execution, propose un fix avec prevention. Triggers: /unity-debug, /debug, 'bug Unity', 'NullReferenceException', 'crash Unity', 'erreur Unity', 'ne marche pas', 'comportement bizarre', 'MissingComponentException', 'glitch visuel', 'physics bug'. Utiliser quand l'utilisateur rapporte un bug, une erreur, un crash ou un comportement inattendu dans Unity. Produit un diagnostic structure : Symptome, Cause, Fix, Prevention."
---

# Unity Debug

Diagnostic et correction systematique de bugs Unity. Trace le chemin d'execution, identifie la cause racine, propose fix + prevention.

## Ce que fait cette skill

1. Collecte les symptomes (message d'erreur, stack trace, description)
2. Classifie le type de bug
3. Lit le code implique
4. Applique l'arbre diagnostique par categorie
5. Propose un fix avec explication
6. Ajoute du code defensif et des recommendations de prevention

## Prerequis

- Acces aux fichiers sources du projet Unity
- Idealement : le message d'erreur exact ou la stack trace
- Outils Claude Code uniquement (Read, Grep, Glob) — pas de MCP Unity requis

## Demarrage rapide

1. L'utilisateur decrit le bug ou colle l'erreur
2. Classifier le type de bug (voir categories)
3. Lire les fichiers impliques
4. Suivre l'arbre diagnostique
5. Produire le diagnostic au format : `Symptome | Cause | Fix | Prevention`

---

## Guide etape par etape

### Etape 1 — Collecter les symptomes

Informations a obtenir de l'utilisateur :
- **Message d'erreur exact** (copie complete avec stack trace)
- **Quand ca arrive** (au lancement, apres une action, aleatoire)
- **Reproductibilite** (toujours, parfois, seulement en build)
- **Changements recents** (qu'est-ce qui a ete modifie avant que ca casse)

Si une stack trace est disponible, extraire :
- Le fichier et la ligne (`at Namespace.Class.Method () in File.cs:line X`)
- La chaine d'appel (qui appelle qui)

### Etape 2 — Classifier le type de bug

```
Le bug est...
│
├─ Erreur de compilation (code rouge, pas de Play)
│  └─ COMPILE ERROR → verifier syntaxe, references, asmdef
│
├─ Exception a l'execution (message en console, peut crasher)
│  ├─ NullReferenceException → ARBRE NULL REF
│  ├─ MissingComponentException → ARBRE MISSING COMPONENT
│  ├─ MissingReferenceException → ARBRE DESTROYED OBJECT
│  ├─ IndexOutOfRangeException → verifier tailles collections
│  ├─ InvalidOperationException → verifier etat collection pendant iteration
│  └─ StackOverflowException → verifier recursion / boucle d'events
│
├─ Comportement incorrect (pas d'erreur visible)
│  └─ LOGIC BUG → tracer le chemin d'execution
│
├─ Performance (lag, stutter, freeze)
│  ├─ Bug de perf specifique (un cas precis) → PERF ISSUE → chercher allocations, Update lourd, physics
│  └─ Audit systematique de performance → utiliser /perf-audit a la place
│
├─ Probleme visuel (rendu, UI, shader)
│  └─ VISUAL GLITCH → verifier materials, sorting, render pipeline
│
└─ Probleme physique (traverse les murs, jitter)
   └─ PHYSICS BUG → verifier Update vs FixedUpdate, layers, scale
```

### Etape 3 — Lire les fichiers impliques

```
Grep("class NomDuScript", type: "cs")        → trouver le fichier
Read(fichier identifie)                       → lire le code complet
Grep("GetComponent|Find|SendMessage", fichier) → reperer les appels risques
Grep("void Update|void FixedUpdate", fichier)  → reperer les hot paths
```

Pour les stack traces, lire CHAQUE fichier mentionne dans la chaine d'appel, du plus profond au plus haut.

### Etape 4 — Arbres diagnostiques

#### ARBRE NULL REF — NullReferenceException

```
La reference null est...
│
├─ Un [SerializeField] ?
│  ├─ Visible dans l'Inspector mais vide → reference non assignee (drag & drop manquant)
│  └─ Pas visible → champ renomme ? Unity perd la serialisation au renommage
│
├─ Un GetComponent result ?
│  ├─ Le composant est-il sur le meme GameObject ? → verifier le prefab
│  ├─ Appele dans Awake mais depend d'un autre Awake ? → ordre d'execution
│  └─ Utilise GetComponent au lieu de TryGetComponent → pas de gestion d'absence
│
├─ Un Find/FindObjectOfType result ?
│  ├─ L'objet existe-t-il dans la scene ? → verifier nom exact, casse
│  └─ L'objet est-il actif ? → Find ignore les inactifs
│
├─ Un objet detruit (Destroy) ?
│  ├─ Acces apres Destroy dans le meme frame → Destroy est differe a la fin du frame
│  └─ Callback/event qui reference un objet detruit → desubscribe dans OnDestroy
│
├─ Un resultat de coroutine/async ?
│  └─ L'objet a-t-il ete detruit pendant le yield ? → verifier `this != null` apres yield
│
└─ Un acces a un composant UI ?
   └─ L'UI est-elle instanciee ? Le Canvas est-il actif ? → timing d'initialisation
```

#### ARBRE MISSING COMPONENT — MissingComponentException

```
├─ Le composant est-il sur le prefab ? → verifier le prefab original
├─ AddComponent appele avant que le GO existe ? → verifier le timing
├─ [RequireComponent] manquant ? → ajouter l'attribut pour garantir la presence
├─ Composant supprime manuellement dans l'Inspector ? → chercher dans le prefab
└─ Script manquant (fichier supprime/renomme) ? → chercher les "Missing Script" dans la scene
```

#### ARBRE RACE CONDITION / TIMING

```
├─ Awake vs Start → Awake : config interne. Start : references externes
├─ Ordre d'execution entre scripts → Edit > Project Settings > Script Execution Order
├─ OnEnable appele avant Start → OnEnable est appele a chaque activation, meme la premiere
├─ Coroutine timing → yield return null = frame suivante, pas "immediatement"
├─ Event souscrit trop tard → l'event a deja fire avant la subscription
└─ DontDestroyOnLoad → verifier les duplications au rechargement de scene
```

#### ARBRE SERIALISATION

```
├─ Champ non serialise → manque [Serializable] sur le struct/class, ou c'est une interface
├─ Dictionary non serialisable → Unity ne serialise pas Dictionary, utiliser 2 listes ou un SO
├─ Champ abstract/interface → Unity ne serialise pas les interfaces, utiliser [SerializeReference]
├─ ScriptableObject remis a zero → modifications runtime sur SO persistent en Editor mais pas en build
└─ Valeurs perdues apres rename → le rename casse la serialisation, utiliser [FormerlySerializedAs]
```

#### ARBRE PHYSICS

```
├─ Objet traverse les murs → ContinuousDynamic collision detection, ou scale trop petit
├─ Jitter de mouvement → utiliser Rigidbody.MovePosition dans FixedUpdate, pas transform.position
├─ Collision non detectee → verifier Layer Collision Matrix (Project Settings > Physics)
├─ Trigger non appele → au moins un des deux a un Rigidbody ? isTrigger coche ?
├─ Force n'a pas d'effet → Rigidbody isKinematic est-il true ?
└─ Comportement physique bizarre → echelle non-uniforme sur les colliders parents
```

### Etape 5 — Proposer le fix

Format de sortie obligatoire :

```
## Diagnostic

**Symptome** : [description precise de ce qui se passe]
**Cause** : [explication technique de pourquoi ca arrive]
**Fix** : [code corrige avec diff ou snippet]
**Prevention** : [comment eviter ce bug a l'avenir]
```

### Etape 6 — Ajouter du code defensif si pertinent

Exemples de patterns defensifs :

```csharp
// Null check avec log explicite
if (_target == null)
{
    Debug.LogWarning($"[{name}] Target reference is missing.", this);
    return;
}

// TryGetComponent au lieu de GetComponent
if (!TryGetComponent(out Rigidbody rb))
{
    Debug.LogError($"[{name}] Missing Rigidbody.", this);
    return;
}

// Verifier destruction avant callback
private IEnumerator DelayedAction()
{
    yield return new WaitForSeconds(1f);
    if (this == null) yield break;  // objet detruit pendant le wait
    DoAction();
}

// Desubscription propre
private void OnEnable() => _eventChannel.Subscribe(OnEvent);
private void OnDisable() => _eventChannel.Unsubscribe(OnEvent);
```

---

## Patterns de bugs courants Unity (reference rapide)

| Bug | Pourquoi | Fix |
|-----|----------|-----|
| `GetComponent` dans `Update` | Recherche chaque frame, lent | Cacher dans `Awake` dans un champ prive |
| `Find("Name")` / `SendMessage("Method")` | String-based, fragile, lent | Utiliser des references directes ou events |
| Coroutine sur objet disabled/destroyed | `StartCoroutine` echoue silencieusement | Verifier `gameObject.activeInHierarchy` avant |
| `obj == null` vs `obj is null` | Unity override `==` pour les objets detruits, `is null` bypass ce check | Utiliser `== null` pour les objets Unity |
| Event sans desubscription | Memory leak, callbacks sur objets detruits | Toujours `Unsubscribe` dans `OnDisable`/`OnDestroy` |
| `Time.deltaTime` dans `FixedUpdate` | `FixedUpdate` a un pas fixe, `deltaTime` = `fixedDeltaTime` la-dedans | Utiliser `Time.fixedDeltaTime` ou rien (c'est constant) |
| `Quaternion * Vector3` dans le mauvais ordre | `vector * quaternion` ne compile pas, `quaternion * vector` = rotation | Toujours `rotation * direction` |
| LayerMask bit shifting | `1 << layerIndex` vs `layerIndex` | `LayerMask.GetMask("LayerName")` plus sur |
| Modifier un SO a runtime | Persiste en Editor, pas en build | Cloner avec `Instantiate(so)` si modification runtime |
| `Destroy` puis acces meme frame | L'objet existe encore jusqu'a la fin du frame | Utiliser `DestroyImmediate` seulement en Editor, sinon restructurer la logique |
| Animation event appelle methode manquante | Typo dans le nom ou signature incorrecte | Verifier la signature exacte attendue par l'AnimationClip |
| `async void` au lieu de `async Awaitable` | Exceptions non catchees, pas de lifecycle Unity | Utiliser `async Awaitable` (Unity 6+) ou `async UniTaskVoid` |

---

## Regles strictes

**TOUJOURS :**
- Lire le code source reel avant de diagnostiquer
- Tracer le chemin d'execution complet (pas de deduction sans preuve)
- Proposer une prevention en plus du fix
- Commencer par l'explication la plus simple (rasoir d'Occam)
- Verifier les references Inspector (champs `[SerializeField]` non assignes)
- Verifier l'ordre de lifecycle Unity (`Awake` → `OnEnable` → `Start`)
- Fournir le diagnostic au format `Symptome | Cause | Fix | Prevention`

**JAMAIS :**
- Deviner la cause sans lire le code
- Proposer un fix sans comprendre la cause racine
- Ignorer la stack trace (chaque ligne est un indice)
- Proposer `try/catch` comme fix (ca masque le bug, ca ne le resout pas)
- Supposer que le bug est dans Unity Engine (c'est presque toujours le code utilisateur)
- Proposer un fix qui introduit un nouveau probleme (regression)

---

## Skills connexes

- Le bug est un probleme de performance general, pas un cas specifique ? Utiliser `/perf-audit` (Unity Perf Audit)
- Le fix necessite un refactoring important ? Utiliser `/unity-refactor` (Unity Refactor)

## Troubleshooting

| Probleme | Solution |
|----------|----------|
| Pas de stack trace disponible | Demander a l'utilisateur de reproduire avec la console ouverte, ou chercher des `Debug.Log` existants pour tracer |
| Bug non reproductible | Chercher les race conditions, verifier si ca depend de l'ordre de chargement des scenes ou du framerate |
| Erreur dans un package tiers | Lire le code du package (`Library/PackageCache/`), chercher des issues connues, proposer un workaround |
| Bug seulement en build (pas en Editor) | Verifier : stripping de code (IL2CPP), differences de serialisation, `#if UNITY_EDITOR` mal place, SO modifies a runtime |
| Bug intermittent lie au framerate | Chercher du code dependant du frame dans `Update` qui devrait etre dans `FixedUpdate`, ou des comparaisons float sans epsilon |
| Performance degrade progressivement | Chercher des fuites : events non desubscrits, listes qui grandissent sans clear, objets instancies sans pool |
