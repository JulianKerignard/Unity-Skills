# Save System Avance : Storage, Migration & Encryption

Patterns avances pour les systemes de sauvegarde Unity 6+ : abstraction storage local/cloud, migration de schema versionnee, auto-save, chiffrement AES, et notes par plateforme.

> **Prerequis** : avoir lu `save-templates.md` pour ISaveable, SaveData et SaveManager.

---

## 1. ISaveStorage Abstraction

Pour supporter local et cloud de maniere interchangeable.

```csharp
using System.Threading;

// Interface d'abstraction du stockage — permet de swapper local/cloud/console.
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

## 2. Save Data Versioning & Migration

Pattern de migration chainee v1 -> v2 -> v3 avec transformations JObject (Newtonsoft).

```csharp
using Newtonsoft.Json.Linq;
using UnityEngine;

public static class SaveMigration
{
    public const int CurrentVersion = 3;

    // Applique les migrations necessaires pour amener saveData a la version courante.
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
        // Exemple : v2 ajoute un champ "stamina" qui n'existait pas en v1
        if (saveData.data.TryGetValue("player", out object playerState))
        {
            var jObj = JObject.FromObject(playerState);
            if (!jObj.ContainsKey("stamina"))
                jObj["stamina"] = 100f;
            saveData.data["player"] = jObj;
        }
    }

    private static void MigrateV2ToV3(SaveData saveData)
    {
        // Exemple : v3 change "items" (List) en "slots" (Dictionary)
        if (saveData.data.TryGetValue("inventory", out object invState))
        {
            var jObj = JObject.FromObject(invState);
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

## 3. Auto-Save Manager

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

    // Appeler depuis n'importe quel systeme quand l'etat change.
    public void MarkDirty() => isDirty = true;

    private void OnEnable() =>
        SceneManager.activeSceneChanged += OnSceneChanged;

    private void OnDisable() =>
        SceneManager.activeSceneChanged -= OnSceneChanged;

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
            _ = PerformAutoSave();
    }

    private void OnSceneChanged(Scene from, Scene to)
    {
        if (isDirty && !isSaving)
            _ = PerformAutoSave();
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

## 4. Encryption (optionnel)

Chiffrement AES et verification d'integrite SHA256 pour les donnees sensibles.

```csharp
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

public static class SaveEncryption
{
    // En production, deriver la cle d'un secret specifique au device.
    private static readonly byte[] DefaultKey =
        Encoding.UTF8.GetBytes("YourGame-32ByteKeyHere!1234567"); // 32 bytes
    private static readonly byte[] DefaultIV =
        Encoding.UTF8.GetBytes("YourGame16ByteIV"); // 16 bytes

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
            writer.Write(plainText);
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

    // Hash SHA256 pour verifier l'integrite du fichier save.
    public static string ComputeHash(string content)
    {
        byte[] bytes = SHA256.HashData(Encoding.UTF8.GetBytes(content));
        return Convert.ToBase64String(bytes);
    }

    // Verifie que le contenu correspond au hash attendu.
    public static bool VerifyHash(string content, string expectedHash) =>
        ComputeHash(content) == expectedHash;
}
```

---

## 5. Notes par plateforme

| Plateforme | `persistentDataPath` | Notes |
|-----------|----------------------|-------|
| Windows | `%userprofile%/AppData/LocalLow/Company/Product` | Fiable, pas de restrictions |
| macOS | `~/Library/Application Support/Company/Product` | Fiable, backupe par Time Machine |
| Linux | `~/.config/unity3d/Company/Product` | Fiable |
| Android | `/storage/emulated/0/Android/data/bundle/files` | Efface par "Clear Data" |
| iOS | `Application/Documents` | Backupe automatiquement par iCloud |
| WebGL | IndexedDB (via Emscripten) | Pas de vrai file system — taille limitee (~50 MB) |

### Conseils specifiques

- **Mobile** : toujours sauvegarder dans `OnApplicationPause(true)` — le systeme peut tuer l'app sans appeler `OnApplicationQuit`
- **WebGL** : les operations fichier sont synchrones et bloquantes. Privilegier des saves petites (<1 MB)
- **Console** : chaque plateforme a son propre systeme de save (PS5 Save Data, Xbox Connected Storage). Utiliser `ISaveStorage` pour abstraire
- **Cloud** : UGS Cloud Save gere la synchronisation mais ajouter un fallback local en cas de perte reseau
