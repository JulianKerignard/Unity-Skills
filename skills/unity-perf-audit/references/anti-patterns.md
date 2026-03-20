# Anti-patterns de performance Unity

Reference complete des anti-patterns a detecter lors d'un audit statique.
Utilise par la skill `/perf-audit` (voir `../SKILL.md` pour le workflow complet).

## Anti-patterns CPU

| # | Pattern | Commande Grep | Severite |
|---|---------|---------------|----------|
| C1 | GetComponent dans Update/FixedUpdate | `GetComponent` puis verifier si dans un bloc Update/FixedUpdate/LateUpdate | Critical |
| C2 | Find en runtime | `Find\(\"\|FindObjectOfType\|FindWithTag\|FindObjectsOfType\|FindGameObjectsWithTag` | Critical |
| C3 | Concatenation string dans hot path | `\+ "` et `\.ToString()` dans Update/FixedUpdate | High |
| C4 | Instantiate dans Update | `Instantiate\(` dans Update/FixedUpdate | High |
| C5 | LINQ dans Update | `\.Where(\|\.Select(\|\.Any(\|\.First(\|\.OrderBy(` dans ou appele depuis Update | High |
| C6 | foreach dans hot path | `foreach` dans Update/FixedUpdate/LateUpdate | Medium |
| C7 | Allocation new dans Update | `new List\|new Dictionary\|new \w+\[\]` dans Update | Medium |
| C8 | SendMessage / BroadcastMessage | `SendMessage\(\|BroadcastMessage\(` | Medium |
| C9 | CompareTag manquant | `\.tag\s*==\|\.tag\s*!=` | Low |
| C10 | Camera.main repete | `Camera\.main` dans Update | Medium |
| C11 | Rigidbody.velocity (API obsolete Unity 6) | `\.velocity\b` sur les fichiers qui ont `Rigidbody` | Low |
| C12 | Instantiate synchrone sur gros prefabs | `Instantiate\(` sur les prefabs complexes (recommander `Object.InstantiateAsync` Unity 6) | Medium |

### Notes sur les nouveaux patterns

**C11 - Rigidbody.velocity :**
Unity 6 deprecie `Rigidbody.velocity` au profit de `Rigidbody.linearVelocity`. La performance est identique mais l'ancienne API genere des warnings de deprecation. Signaler pour mise a jour du code.

**C12 - Instantiate synchrone :**
Unity 6 introduit `Object.InstantiateAsync` qui repartit l'instanciation sur plusieurs frames. Pertinent uniquement pour les prefabs complexes (beaucoup de composants, hierarchie profonde). Signaler comme suggestion, pas comme erreur.

### Methode de detection pour les hot paths

Le hot path inclut : `Update()`, `FixedUpdate()`, `LateUpdate()`, `OnGUI()`, `OnTriggerStay`, `OnCollisionStay`.

Pour detecter si un pattern est dans un hot path :
1. Grep le pattern dans tout le projet
2. Pour chaque match, lire le fichier et verifier si la ligne est dans le corps d'une methode hot path
3. Si le pattern est dans une methode appelee depuis un hot path (call chain), le signaler aussi mais en severite reduite

Utiliser Grep avec contexte (`-B` et `-A`) pour voir le nom de la methode englobante :
```
Grep pattern avec -B 20 pour trouver la signature de methode precedente
Chercher "void Update" ou "void FixedUpdate" dans les lignes precedentes
```

## Anti-patterns GPU

| # | Pattern | Methode de detection |
|---|---------|---------------------|
| G1 | Materiaux transparents excessifs | Grep `transparent\|fade\|Transparent` dans les .shader et .mat (Glob `**/*.shader`, `**/*.mat`) |
| G2 | Pas de LOD sur les meshes | Grep `MeshRenderer\|MeshFilter` et verifier l'absence de `LODGroup` dans le meme GameObject ou parent |
| G3 | Lumieres realtime | Grep `LightType\|new Light\|GetComponent<Light>` -- verifier dans les scenes si possible |
| G4 | SetPass calls elevees | Grep `Material\(\|new Material` (creation de materiaux a runtime = batching casse) |

### Note : GPU Resident Drawer (Unity 6)

Unity 6 introduit le GPU Resident Drawer qui reduit automatiquement les draw calls
pour les objets statiques et les LODs. Si le projet l'utilise (Project Settings > Graphics),
les optimisations manuelles de draw call (static batching, manual combining) deviennent
moins critiques. Verifier si le projet active cette feature avant de recommander des
optimisations de batching.

## Anti-patterns Memoire

| # | Pattern | Commande Grep | Severite |
|---|---------|---------------|----------|
| M1 | Resources.Load sans Unload | `Resources\.Load` sans `Resources\.UnloadUnusedAssets` dans le meme fichier | High |
| M2 | Texture creation runtime | `new Texture2D\|new RenderTexture` | High |
| M3 | Event leak (subscribe sans unsubscribe) | `\+=` sur un event/Action/delegate, verifier presence de `-=` correspondant dans OnDisable/OnDestroy | High |
| M4 | Allocation tableau dans Update | `new\s+\w+\[` dans Update | Medium |
| M5 | Coroutine avec allocation | `new WaitForSeconds\|new WaitForEndOfFrame` dans une coroutine appelee frequemment | Medium |
| M6 | Pas de Dispose sur IDisposable | `new\s+(StreamReader\|StreamWriter\|FileStream\|WebClient\|HttpClient)` sans `using` ou `.Dispose()` | Medium |
| M7 | new WaitForSeconds repete dans coroutine | `new WaitForSeconds\(` dans les coroutines appelees frequemment | Low |

### Detail M7 : Cache des WaitForSeconds

`new WaitForSeconds` recree une instance a chaque appel de coroutine. Pour les coroutines appelees frequemment (boucles, spawns), cacher en `static readonly` elimine l'allocation.

```csharp
// AVANT
IEnumerator Spawn()
{
    while (true)
    {
        SpawnEnemy();
        yield return new WaitForSeconds(2f); // allocation chaque iteration
    }
}

// APRES
private static readonly WaitForSeconds SpawnDelay = new(2f);
IEnumerator Spawn()
{
    while (true)
    {
        SpawnEnemy();
        yield return SpawnDelay; // zero allocation
    }
}
```

**Detection :** Grep `new WaitForSeconds\(` et verifier si la coroutine contient une boucle `while` ou est lancee avec `InvokeRepeating` / appelee depuis `Update`. Si la coroutine ne s'execute qu'une fois (ex: sequence de tutoriel), l'allocation est negligeable -- ne pas reporter.

## Budgets performance par plateforme

Reference pour contextualiser les problemes trouves. Ne pas citer si aucun probleme GPU/rendering n'est detecte.

| Plateforme | FPS cible | Draw calls | Triangles | Memoire |
|------------|----------|------------|-----------|---------|
| Mobile | 30-60 | < 200 | < 100K | < 1 GB |
| Console | 30-60 | < 2000 | < 2M | < 4 GB |
| PC | 60-144 | < 5000 | < 10M | < 8 GB |
