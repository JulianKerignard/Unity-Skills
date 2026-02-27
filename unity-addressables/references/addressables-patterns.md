# Addressables Patterns & Reference

## Organisation des groupes detaillee

### Default Local Group
Assets toujours presents dans le build : UI de base, prefabs player, tutorial, ScriptableObjects critiques.

### Per-Scene Group
Un groupe par scene/zone (`Level1_Assets`, `BossArena_Assets`). Associer un label identique au nom de la scene pour faciliter le preloading.

### Remote Group
Assets telechargeables post-install (DLC, patches, contenu saisonnier) :
- Remote Build Path : `ServerData/[BuildTarget]`
- Remote Load Path : `https://cdn.example.com/[BuildTarget]`
- Activer `BuildRemoteCatalog` dans Addressables Settings

### Configuration du schema

```
Group Settings:
  Build Path:  LocalBuildPath  |  RemoteBuildPath
  Load Path:   LocalLoadPath   |  RemoteLoadPath
  Bundle Mode: Pack Together   |  Pack Separately  |  Pack Together By Label
```

- **Pack Together** : un seul bundle par groupe (moins de requetes, plus gros)
- **Pack Separately** : un bundle par asset (granulaire, plus de requetes)
- **Pack Together By Label** : un bundle par label dans le groupe (bon compromis)

### Labels
Tags transversaux (`enemies`, `props`, `level1`, `hd`/`sd`). Un asset peut avoir plusieurs labels. Les labels ne changent pas l'organisation en groupes.

## Labels et filtres

```csharp
// Charger tous les assets d'un label
var handle = Addressables.LoadAssetsAsync<GameObject>("enemies",
    obj => Debug.Log($"Loaded: {obj.name}"));
await handle.Task;
foreach (var enemy in handle.Result) Instantiate(enemy);
Addressables.Release(handle);

// Multi-labels : intersection (assets avec TOUS les labels)
var handle = Addressables.LoadAssetsAsync<GameObject>(
    new List<string> { "enemies", "level1" },
    null, Addressables.MergeMode.Intersection);

// Multi-labels : union (assets avec AU MOINS UN label)
var handle = Addressables.LoadAssetsAsync<GameObject>(
    new List<string> { "enemies", "level1" },
    null, Addressables.MergeMode.Union);

// Type-safe dans l'Inspector
[SerializeField] private AssetLabelReference enemyLabel;
var handle = Addressables.LoadAssetsAsync<GameObject>(enemyLabel, null);
```

## Preloading avec progression (loading screen)

```csharp
public class LoadingScreen : MonoBehaviour
{
    [SerializeField] private Slider progressBar;
    [SerializeField] private TextMeshProUGUI statusText;
    [SerializeField] private AssetLabelReference sceneAssets;

    public async Awaitable PreloadAssetsAsync()
    {
        var sizeHandle = Addressables.GetDownloadSizeAsync(sceneAssets);
        await sizeHandle.Task;
        long downloadSize = sizeHandle.Result;
        Addressables.Release(sizeHandle);

        if (downloadSize > 0)
            statusText.text = $"Downloading {downloadSize / (1024 * 1024)} MB...";

        var handle = Addressables.DownloadDependenciesAsync(sceneAssets);
        while (!handle.IsDone)
        {
            progressBar.value = handle.PercentComplete;
            statusText.text = $"Loading... {handle.PercentComplete * 100:F0}%";
            await Awaitable.NextFrameAsync();
        }
        Addressables.Release(handle);
    }
}
```

## Memory management

### Reference counting
Chaque `LoadAssetAsync` incremente le compteur. Chaque `Release` decremente. L'asset est decharge quand le compteur atteint 0.

```
LoadAssetAsync("sword")  → refCount = 1 (charge en memoire)
LoadAssetAsync("sword")  → refCount = 2 (meme instance)
Release(handle1)         → refCount = 1 (toujours en memoire)
Release(handle2)         → refCount = 0 (decharge)
```

### Pattern safe avec try/finally

```csharp
public async Awaitable UseTemporaryAssetAsync(AssetReference assetRef)
{
    var handle = Addressables.LoadAssetAsync<TextAsset>(assetRef);
    try
    {
        await handle.Task;
        if (handle.Status == AsyncOperationStatus.Succeeded)
            ProcessData(handle.Result.text);
    }
    finally
    {
        Addressables.Release(handle);
    }
}
```

### Asset Manager avec tracking

```csharp
public class AddressableAssetManager : MonoBehaviour
{
    private readonly Dictionary<string, AsyncOperationHandle> loadedHandles = new();

    public async Awaitable<T> LoadAsync<T>(string address)
    {
        if (loadedHandles.TryGetValue(address, out var existing))
            return (T)existing.Result;

        var handle = Addressables.LoadAssetAsync<T>(address);
        await handle.Task;

        if (handle.Status == AsyncOperationStatus.Succeeded)
        {
            loadedHandles[address] = handle;
            return handle.Result;
        }
        Addressables.Release(handle);
        return default;
    }

    public void Unload(string address)
    {
        if (loadedHandles.TryGetValue(address, out var handle))
        {
            Addressables.Release(handle);
            loadedHandles.Remove(address);
        }
    }

    public void UnloadAll()
    {
        foreach (var handle in loadedHandles.Values)
            Addressables.Release(handle);
        loadedHandles.Clear();
    }

    private void OnDestroy() => UnloadAll();
}
```

## InstantiateAsync pattern

```csharp
// InstantiateAsync combine load + instantiate
var handle = Addressables.InstantiateAsync(prefabRef, position, rotation);
await handle.Task;
var instance = handle.Result;

// Pour detruire : ReleaseInstance, PAS Destroy
Addressables.ReleaseInstance(instance);
```

### Pool pattern avec Addressables

```csharp
public class AddressablePool : MonoBehaviour
{
    [SerializeField] private AssetReferenceGameObject prefabRef;
    [SerializeField] private int initialSize = 10;
    private readonly Queue<GameObject> pool = new();
    private readonly List<GameObject> active = new();

    public async Awaitable InitializeAsync()
    {
        for (int i = 0; i < initialSize; i++)
        {
            var handle = Addressables.InstantiateAsync(prefabRef);
            await handle.Task;
            handle.Result.SetActive(false);
            pool.Enqueue(handle.Result);
        }
    }

    public GameObject Get(Vector3 pos, Quaternion rot)
    {
        if (pool.Count == 0) return null;
        var inst = pool.Dequeue();
        inst.transform.SetPositionAndRotation(pos, rot);
        inst.SetActive(true);
        active.Add(inst);
        return inst;
    }

    public void Return(GameObject inst)
    {
        inst.SetActive(false);
        active.Remove(inst);
        pool.Enqueue(inst);
    }

    private void OnDestroy()
    {
        foreach (var inst in pool) Addressables.ReleaseInstance(inst);
        foreach (var inst in active) Addressables.ReleaseInstance(inst);
    }
}
```

## Remote content (CDN)

### Configuration
1. Addressables Settings > activer **Build Remote Catalog**
2. Remote Load Path : `https://cdn.example.com/[BuildTarget]`
3. Groupes Remote : `RemoteBuildPath` / `RemoteLoadPath`
4. Build : Addressables > Build > New Build > Default Build Script
5. Uploader `ServerData/` sur le CDN

### Catalog update au runtime

```csharp
public class ContentUpdater : MonoBehaviour
{
    public async Awaitable<bool> CheckAndUpdateAsync()
    {
        var checkHandle = Addressables.CheckForCatalogUpdates(false);
        await checkHandle.Task;
        if (checkHandle.Status != AsyncOperationStatus.Succeeded)
        {
            Addressables.Release(checkHandle);
            return false;
        }

        var catalogs = checkHandle.Result;
        Addressables.Release(checkHandle);
        if (catalogs == null || catalogs.Count == 0) return false;

        var updateHandle = Addressables.UpdateCatalogs(catalogs, false);
        await updateHandle.Task;
        bool success = updateHandle.Status == AsyncOperationStatus.Succeeded;
        Addressables.Release(updateHandle);
        return success;
    }
}
```

### Verifier la taille du download

```csharp
public async Awaitable<long> GetDownloadSizeAsync(string label)
{
    var handle = Addressables.GetDownloadSizeAsync(label);
    await handle.Task;
    long size = handle.Result;
    Addressables.Release(handle);
    return size; // Bytes, 0 si deja en cache
}
```

## Profiling Addressables

- **Event Viewer** (Window > Asset Management > Addressables > Event Viewer) : loads, unloads, reference counts en temps reel. Identifier les leaks (refcount > 0 en fin de scene).
- **Build Report** : taille des bundles, duplication d'assets entre groupes. Si un material est dans 2 groupes, il est duplique. Solution : groupe `Shared_Dependencies`.
- **Memory Profiler** : comparer snapshots avant/apres chargement pour verifier que `Release` decharge effectivement.

### Checklist de profiling
1. Ouvrir Event Viewer avant de lancer le jeu
2. Jouer un cycle complet (load scene, play, quit scene)
3. Verifier que tous les refcounts reviennent a 0
4. Si refcount > 0 : chercher le `Release` manquant
5. Analyser le Build Report pour la duplication
6. Deplacer les assets dupliques dans un groupe shared
