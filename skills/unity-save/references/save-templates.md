# Save System Templates

Code C# complet pour implementer un systeme de sauvegarde Unity 6+. Tous les templates utilisent Newtonsoft.Json par defaut (recommande). Adapter avec JsonUtility si besoin.

---

## 1. ISaveable Interface

```csharp
// Interface implementee par tout composant dont l'etat doit etre sauvegarde.
public interface ISaveable
{
    // Cle unique identifiant ce saveable (ex: "player", "inventory_chest_03").
    string SaveKey { get; }

    // Capture l'etat courant sous forme serialisable (POCO uniquement).
    object CaptureState();

    // Restaure l'etat depuis les donnees deserializees.
    void RestoreState(object state);
}
```

Exemple d'implementation :

```csharp
public class PlayerHealth : MonoBehaviour, ISaveable
{
    [SerializeField] private float maxHealth = 100f;
    private float currentHealth;

    public string SaveKey => "player_health";

    public object CaptureState() => new PlayerHealthData
    {
        currentHealth = this.currentHealth,
        maxHealth = this.maxHealth
    };

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
    // Version du schema — incrementer a chaque changement de structure.
    public int version = 1;

    // Donnees capturees par chaque ISaveable, indexees par SaveKey.
    public Dictionary<string, object> data = new();

    // Metadata de la sauvegarde.
    public SaveMetadata metadata = new();
}

[Serializable]
public class SaveMetadata
{
    public string timestamp;
    public float playTimeSeconds;
    public string sceneName;
    public string displayName;

    public static SaveMetadata CreateNow(float playTime, string scene) => new()
    {
        timestamp = DateTime.UtcNow.ToString("o"),
        playTimeSeconds = playTime,
        sceneName = scene,
        displayName = $"Save - {DateTime.Now:g}"
    };
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
            Debug.LogWarning($"[SaveManager] SaveKey dupliquee : {saveable.SaveKey}");
    }

    public void UnregisterSaveable(ISaveable saveable) =>
        saveables.Remove(saveable.SaveKey);

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
            try { saveData.data[key] = saveable.CaptureState(); }
            catch (Exception e)
            { Debug.LogError($"[SaveManager] Erreur capture '{key}': {e.Message}"); }
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
                try { saveable.RestoreState(state); }
                catch (Exception e)
                { Debug.LogError($"[SaveManager] Erreur restore '{key}': {e.Message}"); }
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

        await File.WriteAllTextAsync(tmpPath, content, ct);
        if (File.Exists(filePath))
            File.Copy(filePath, bakPath, overwrite: true);
        File.Move(tmpPath, filePath, overwrite: true);
    }

    private async Awaitable<bool> TryLoadBackupAsync(string slotName,
        CancellationToken ct)
    {
        string bakPath = GetSavePath(slotName) + ".bak";
        if (!File.Exists(bakPath)) return false;

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
        catch { return false; }
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
