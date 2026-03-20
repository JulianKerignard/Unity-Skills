# Save System Templates

Code C# complet pour implementer un systeme de sauvegarde Unity 6+. Tous les templates utilisent Newtonsoft.Json par defaut (recommande). Adapter avec JsonUtility si besoin.

---

## 1. ISaveable Interface

```csharp
/// <summary>
/// Interface implementee par tout composant dont l'etat doit etre sauvegarde.
/// </summary>
public interface ISaveable
{
    /// <summary>Cle unique identifiant ce saveable (ex: "player", "inventory_chest_03").</summary>
    string SaveKey { get; }

    /// <summary>Capture l'etat courant sous forme serialisable (POCO uniquement).</summary>
    object CaptureState();

    /// <summary>Restaure l'etat depuis les donnees deserializees.</summary>
    void RestoreState(object state);
}
```

Exemple d'implementation sur un composant :

```csharp
public class PlayerHealth : MonoBehaviour, ISaveable
{
    [SerializeField] private float maxHealth = 100f;
    private float currentHealth;

    public string SaveKey => "player_health";

    public object CaptureState()
    {
        return new PlayerHealthData
        {
            currentHealth = this.currentHealth,
            maxHealth = this.maxHealth
        };
    }

    public void RestoreState(object state)
    {
        if (state is PlayerHealthData data)
        {
            currentHealth = data.currentHealth;
            maxHealth = data.maxHealth;
        }
    }

    [System.Serializable]
    private class PlayerHealthData
    {
        public float currentHealth;
        public float maxHealth;
    }
}
```

---

## 2. SaveData Container

```csharp
using System;
using System.Collections.Generic;

[Serializable]
public class SaveData
{
    /// <summary>Version du schema. Incrementer a chaque changement de structure.</summary>
    public int version = 1;

    /// <summary>Donnees capturees par chaque ISaveable, indexees par SaveKey.</summary>
    public Dictionary<string, object> data = new();

    /// <summary>Metadata de la sauvegarde.</summary>
    public SaveMetadata metadata = new();
}

[Serializable]
public class SaveMetadata
{
    public string timestamp;
    public float playTimeSeconds;
    public string sceneName;
    public string displayName;

    public static SaveMetadata CreateNow(float playTime, string scene)
    {
        return new SaveMetadata
        {
            timestamp = DateTime.UtcNow.ToString("o"),
            playTimeSeconds = playTime,
            sceneName = scene,
            displayName = $"Save - {DateTime.Now:g}"
        };
    }
}
```

---

## 3. SaveManager

Implementation complete avec ecriture atomique, multi-slots, et Awaitable (Unity 6+).

```csharp
using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using Newtonsoft.Json;
using UnityEngine;
using UnityEngine.SceneManagement;

public class SaveManager : MonoBehaviour
{
    public static SaveManager Instance { get; private set; }

    [SerializeField] private string saveFolder = "saves";
    [SerializeField] private string fileExtension = ".save";

    private readonly Dictionary<string, ISaveable> saveables = new();
    private readonly JsonSerializerSettings jsonSettings = new()
    {
        TypeNameHandling = TypeNameHandling.Auto,
        Formatting = Formatting.Indented,
        ReferenceLoopHandling = ReferenceLoopHandling.Ignore
    };

    private string SaveDirectory =>
        Path.Combine(Application.persistentDataPath, saveFolder);

    private void Awake()
    {
        if (Instance != null && Instance != this)
        {
            Destroy(gameObject);
            return;
        }
        Instance = this;
        DontDestroyOnLoad(gameObject);
        Directory.CreateDirectory(SaveDirectory);
    }

    // --- Registry ---

    public void RegisterSaveable(ISaveable saveable)
    {
        if (!saveables.TryAdd(saveable.SaveKey, saveable))
        {
            Debug.LogWarning($"[SaveManager] SaveKey dupliquee : {saveable.SaveKey}");
        }
    }

    public void UnregisterSaveable(ISaveable saveable)
    {
        saveables.Remove(saveable.SaveKey);
    }

    // --- Save ---

    public async Awaitable SaveAsync(string slotName, float playTime = 0f,
        CancellationToken ct = default)
    {
        var saveData = new SaveData
        {
            version = SaveMigration.CurrentVersion,
            metadata = SaveMetadata.CreateNow(playTime,
                SceneManager.GetActiveScene().name)
        };

        foreach (var (key, saveable) in saveables)
        {
            try
            {
                saveData.data[key] = saveable.CaptureState();
            }
            catch (Exception e)
            {
                Debug.LogError($"[SaveManager] Erreur capture '{key}': {e.Message}");
            }
        }

        string json = JsonConvert.SerializeObject(saveData, jsonSettings);
        await WriteAtomicAsync(slotName, json, ct);
        Debug.Log($"[SaveManager] Sauvegarde '{slotName}' terminee.");
    }

    // --- Load ---

    public async Awaitable<bool> LoadAsync(string slotName,
        CancellationToken ct = default)
    {
        string filePath = GetSavePath(slotName);

        if (!File.Exists(filePath))
        {
            Debug.LogWarning($"[SaveManager] Aucune sauvegarde trouvee : {slotName}");
            return false;
        }

        try
        {
            string json = await File.ReadAllTextAsync(filePath, ct);
            var saveData = JsonConvert.DeserializeObject<SaveData>(json, jsonSettings);

            if (saveData == null)
            {
                Debug.LogError("[SaveManager] Fichier save corrompu.");
                return await TryLoadBackupAsync(slotName, ct);
            }

            // Migration si version anterieure
            saveData = SaveMigration.Migrate(saveData);

            RestoreAll(saveData);
            Debug.Log($"[SaveManager] Chargement '{slotName}' termine (v{saveData.version}).");
            return true;
        }
        catch (Exception e)
        {
            Debug.LogError($"[SaveManager] Erreur chargement : {e.Message}");
            return await TryLoadBackupAsync(slotName, ct);
        }
    }

    private void RestoreAll(SaveData saveData)
    {
        foreach (var (key, saveable) in saveables)
        {
            if (saveData.data.TryGetValue(key, out object state))
            {
                try
                {
                    saveable.RestoreState(state);
                }
                catch (Exception e)
                {
                    Debug.LogError($"[SaveManager] Erreur restore '{key}': {e.Message}");
                }
            }
        }
    }

    // --- Ecriture atomique ---

    private async Awaitable WriteAtomicAsync(string slotName, string content,
        CancellationToken ct)
    {
        string filePath = GetSavePath(slotName);
        string tmpPath = filePath + ".tmp";
        string bakPath = filePath + ".bak";

        // 1. Ecrire dans .tmp
        await File.WriteAllTextAsync(tmpPath, content, ct);

        // 2. Backup de l'existant
        if (File.Exists(filePath))
        {
            File.Copy(filePath, bakPath, overwrite: true);
        }

        // 3. Renommer .tmp -> .save (atomique sur la plupart des OS)
        File.Move(tmpPath, filePath, overwrite: true);
    }

    private async Awaitable<bool> TryLoadBackupAsync(string slotName,
        CancellationToken ct)
    {
        string bakPath = GetSavePath(slotName) + ".bak";
        if (!File.Exists(bakPath))
            return false;

        Debug.LogWarning("[SaveManager] Tentative de restauration depuis .bak");
        try
        {
            string json = await File.ReadAllTextAsync(bakPath, ct);
            var saveData = JsonConvert.DeserializeObject<SaveData>(json, jsonSettings);
            if (saveData == null) return false;

            saveData = SaveMigration.Migrate(saveData);
            RestoreAll(saveData);
            return true;
        }
        catch
        {
            return false;
        }
    }

    // --- Utilitaires ---

    public bool SaveExists(string slotName) =>
        File.Exists(GetSavePath(slotName));

    public void DeleteSave(string slotName)
    {
        string path = GetSavePath(slotName);
        if (File.Exists(path)) File.Delete(path);
        if (File.Exists(path + ".bak")) File.Delete(path + ".bak");
    }

    public string[] GetAllSlots()
    {
        if (!Directory.Exists(SaveDirectory))
            return Array.Empty<string>();

        var files = Directory.GetFiles(SaveDirectory, $"*{fileExtension}");
        var slots = new string[files.Length];
        for (int i = 0; i < files.Length; i++)
            slots[i] = Path.GetFileNameWithoutExtension(files[i]);
        return slots;
    }

    private string GetSavePath(string slotName) =>
        Path.Combine(SaveDirectory, slotName + fileExtension);
}
```

---

## 4. ISaveStorage Abstraction

Pour supporter local et cloud de maniere interchangeable.

```csharp
using System.Threading;

public interface ISaveStorage
{
    Awaitable SaveAsync(string key, byte[] data, CancellationToken ct = default);
    Awaitable<byte[]> LoadAsync(string key, CancellationToken ct = default);
    Awaitable<bool> ExistsAsync(string key, CancellationToken ct = default);
    Awaitable DeleteAsync(string key, CancellationToken ct = default);
}
```

Implementation locale :

```csharp
using System.IO;
using System.Threading;
using UnityEngine;

public class LocalSaveStorage : ISaveStorage
{
    private readonly string basePath;

    public LocalSaveStorage(string subfolder = "saves")
    {
        basePath = Path.Combine(Application.persistentDataPath, subfolder);
        Directory.CreateDirectory(basePath);
    }

    private string GetPath(string key) => Path.Combine(basePath, key);

    public async Awaitable SaveAsync(string key, byte[] data, CancellationToken ct = default)
    {
        string path = GetPath(key);
        string tmpPath = path + ".tmp";

        await File.WriteAllBytesAsync(tmpPath, data, ct);

        if (File.Exists(path))
            File.Copy(path, path + ".bak", overwrite: true);

        File.Move(tmpPath, path, overwrite: true);
    }

    public async Awaitable<byte[]> LoadAsync(string key, CancellationToken ct = default)
    {
        string path = GetPath(key);
        if (!File.Exists(path)) return null;
        return await File.ReadAllBytesAsync(path, ct);
    }

    public Awaitable<bool> ExistsAsync(string key, CancellationToken ct = default)
    {
        return Awaitable.FromResult(File.Exists(GetPath(key)));
    }

    public async Awaitable DeleteAsync(string key, CancellationToken ct = default)
    {
        string path = GetPath(key);
        if (File.Exists(path)) File.Delete(path);
        if (File.Exists(path + ".bak")) File.Delete(path + ".bak");
        await Awaitable.NextFrameAsync(ct);
    }
}
```

---

## 5. Save Data Versioning

Pattern de migration chainee v1 -> v2 -> v3 avec transformations JObject (Newtonsoft).

```csharp
using Newtonsoft.Json.Linq;
using UnityEngine;

public static class SaveMigration
{
    public const int CurrentVersion = 3;

    /// <summary>
    /// Applique les migrations necessaires pour amener saveData a la version courante.
    /// </summary>
    public static SaveData Migrate(SaveData saveData)
    {
        if (saveData.version >= CurrentVersion)
            return saveData;

        Debug.Log($"[SaveMigration] Migration v{saveData.version} -> v{CurrentVersion}");

        while (saveData.version < CurrentVersion)
        {
            switch (saveData.version)
            {
                case 1: MigrateV1ToV2(saveData); break;
                case 2: MigrateV2ToV3(saveData); break;
                default:
                    Debug.LogError($"[SaveMigration] Version inconnue : {saveData.version}");
                    return saveData;
            }
            saveData.version++;
        }
        return saveData;
    }

    private static void MigrateV1ToV2(SaveData saveData)
    {
        // Exemple : renommer une cle, ajouter un champ par defaut
        if (saveData.data.TryGetValue("player", out object playerState))
        {
            var jObj = JObject.FromObject(playerState);
            // v2 ajoute un champ "stamina" qui n'existait pas en v1
            if (!jObj.ContainsKey("stamina"))
                jObj["stamina"] = 100f;
            saveData.data["player"] = jObj;
        }
    }

    private static void MigrateV2ToV3(SaveData saveData)
    {
        // Exemple : restructurer l'inventaire
        if (saveData.data.TryGetValue("inventory", out object invState))
        {
            var jObj = JObject.FromObject(invState);
            // v3 change "items" (List) en "slots" (Dictionary)
            if (jObj.ContainsKey("items") && !jObj.ContainsKey("slots"))
            {
                jObj["slots"] = jObj["items"];
                jObj.Remove("items");
            }
            saveData.data["inventory"] = jObj;
        }
    }
}
```

---

## 6. Auto-Save Manager

Sauvegarde automatique basee sur un dirty flag et un timer.

```csharp
using UnityEngine;
using UnityEngine.SceneManagement;

public class AutoSaveManager : MonoBehaviour
{
    [SerializeField] private float autoSaveIntervalSeconds = 90f;
    [SerializeField] private string autoSaveSlot = "autosave";

    private float timeSinceLastSave;
    private float totalPlayTime;
    private bool isDirty;
    private bool isSaving;

    /// <summary>Appeler depuis n'importe quel systeme quand l'etat change.</summary>
    public void MarkDirty() => isDirty = true;

    private void OnEnable()
    {
        SceneManager.activeSceneChanged += OnSceneChanged;
    }

    private void OnDisable()
    {
        SceneManager.activeSceneChanged -= OnSceneChanged;
    }

    private void Update()
    {
        totalPlayTime += Time.unscaledDeltaTime;
        timeSinceLastSave += Time.unscaledDeltaTime;

        if (isDirty && !isSaving
            && timeSinceLastSave >= autoSaveIntervalSeconds)
        {
            _ = PerformAutoSave();
        }
    }

    private void OnApplicationPause(bool pauseStatus)
    {
        if (pauseStatus && isDirty && !isSaving)
        {
            _ = PerformAutoSave();
        }
    }

    private void OnSceneChanged(Scene from, Scene to)
    {
        if (isDirty && !isSaving)
        {
            _ = PerformAutoSave();
        }
    }

    private async Awaitable PerformAutoSave()
    {
        isSaving = true;
        try
        {
            await SaveManager.Instance.SaveAsync(autoSaveSlot, totalPlayTime);
            isDirty = false;
            timeSinceLastSave = 0f;
        }
        catch (System.Exception e)
        {
            Debug.LogError($"[AutoSave] Echec : {e.Message}");
        }
        finally
        {
            isSaving = false;
        }
    }
}
```

---

## 7. Save Encryption (optionnel)

Chiffrement AES et verification d'integrite SHA256 pour les donnees sensibles.

```csharp
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

public static class SaveEncryption
{
    // En production, deriver la cle d'un secret specifique au device
    private static readonly byte[] DefaultKey = Encoding.UTF8.GetBytes("YourGame-32ByteKeyHere!1234567"); // 32 bytes
    private static readonly byte[] DefaultIV = Encoding.UTF8.GetBytes("YourGame16ByteIV"); // 16 bytes

    public static byte[] Encrypt(string plainText, byte[] key = null, byte[] iv = null)
    {
        key ??= DefaultKey;
        iv ??= DefaultIV;

        using var aes = Aes.Create();
        aes.Key = key;
        aes.IV = iv;

        using var ms = new MemoryStream();
        using (var cs = new CryptoStream(ms, aes.CreateEncryptor(), CryptoStreamMode.Write))
        using (var writer = new StreamWriter(cs))
        {
            writer.Write(plainText);
        }
        return ms.ToArray();
    }

    public static string Decrypt(byte[] cipherBytes, byte[] key = null, byte[] iv = null)
    {
        key ??= DefaultKey;
        iv ??= DefaultIV;

        using var aes = Aes.Create();
        aes.Key = key;
        aes.IV = iv;

        using var ms = new MemoryStream(cipherBytes);
        using var cs = new CryptoStream(ms, aes.CreateDecryptor(), CryptoStreamMode.Read);
        using var reader = new StreamReader(cs);
        return reader.ReadToEnd();
    }

    /// <summary>Hash SHA256 pour verifier l'integrite du fichier save.</summary>
    public static string ComputeHash(string content)
    {
        byte[] bytes = SHA256.HashData(Encoding.UTF8.GetBytes(content));
        return Convert.ToBase64String(bytes);
    }

    /// <summary>Verifie que le contenu correspond au hash attendu.</summary>
    public static bool VerifyHash(string content, string expectedHash)
    {
        return ComputeHash(content) == expectedHash;
    }
}
```

---

## 8. Notes par plateforme

| Plateforme | `persistentDataPath` | Notes |
|-----------|----------------------|-------|
| Windows | `%userprofile%/AppData/LocalLow/Company/Product` | Fiable, pas de restrictions |
| macOS | `~/Library/Application Support/Company/Product` | Fiable, backupe par Time Machine |
| Linux | `~/.config/unity3d/Company/Product` | Fiable |
| Android | `/storage/emulated/0/Android/data/bundle/files` | Efface par "Clear Data" dans les parametres |
| iOS | `Application/Documents` | Backupe automatiquement par iCloud |
| WebGL | IndexedDB (via Emscripten) | Pas de vrai file system — `File.WriteAllText` fonctionne mais passe par IndexedDB. Taille limitee (~50 MB). Utiliser `PlayerPrefs` pour les petites donnees |

### Conseils specifiques

- **Mobile** : toujours sauvegarder dans `OnApplicationPause(true)` — le systeme peut tuer l'app sans appeler `OnApplicationQuit`
- **WebGL** : les operations fichier sont synchrones et bloquantes. Privilegier des saves petites (<1 MB)
- **Console** : chaque plateforme a son propre systeme de save (PS5 Save Data, Xbox Connected Storage). Utiliser `ISaveStorage` pour abstraire
- **Cloud** : UGS Cloud Save gere la synchronisation mais ajouter un fallback local en cas de perte reseau
