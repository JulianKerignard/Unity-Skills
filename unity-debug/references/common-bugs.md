# Bugs courants Unity — Reference rapide

Table de reference des bugs frequemment rencontres dans les projets Unity. Utilise par la skill `/unity-debug`.

---

## Bugs classiques

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

## Bugs Unity 6+ / API deprecees

| Bug | Cause | Fix |
|-----|-------|-----|
| `Rigidbody.velocity` deprecated warning | Unity 6 renomme `velocity` en `linearVelocity` | Remplacer par `rb.linearVelocity` |
| `Rigidbody.angularVelocity` deprecated | Unity 6 renomme l'API interne | Remplacer par `rb.angularVelocity` (le nom reste mais l'API interne change) |
| `UxmlFactory`/`UxmlTraits` deprecated | Unity 6 nouveau systeme UI Toolkit | Utiliser `[UxmlElement]` et `[UxmlAttribute]` sur la classe `partial` |
| `Entities.ForEach` deprecated | DOTS Unity 6+ nouvelle API | Migrer vers `SystemAPI.Query` + `IJobEntity` |
| `Object.Instantiate` spike sur gros prefab | Instantiation synchrone bloque le main thread | Utiliser `Object.InstantiateAsync` (Unity 6+) |
