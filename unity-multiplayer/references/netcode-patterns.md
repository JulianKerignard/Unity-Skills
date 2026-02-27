# Netcode for GameObjects — Patterns de reference

## 1. NetworkVariable patterns

### Types supportes nativement

Les types suivants fonctionnent directement avec `NetworkVariable<T>` sans
serialization custom:

- **Primitifs**: `bool`, `byte`, `sbyte`, `short`, `ushort`, `int`, `uint`,
  `long`, `ulong`, `float`, `double`
- **Structs Unity**: `Vector2`, `Vector3`, `Vector4`, `Quaternion`, `Color`,
  `Color32`, `Ray`, `Ray2D`
- **Strings fixes**: `FixedString32Bytes`, `FixedString64Bytes`,
  `FixedString128Bytes` (pas `string`)
- **Enums**: tout enum backed par un type primitif

### Declaration et permissions

```csharp
// Lecture: tous | Ecriture: server uniquement (defaut)
private NetworkVariable<int> health = new(100);

// Lecture: tous | Ecriture: owner
private NetworkVariable<Vector3> aimDirection = new(
    Vector3.forward,
    NetworkVariableReadPermission.Everyone,
    NetworkVariableWritePermission.Owner);

// Lecture: owner uniquement | Ecriture: server
private NetworkVariable<int> secretData = new(0,
    NetworkVariableReadPermission.Owner,
    NetworkVariableWritePermission.Server);
```

### Callback de changement

```csharp
public override void OnNetworkSpawn()
{
    health.OnValueChanged += OnHealthChanged;
    // Lire la valeur initiale manuellement (le callback ne fire pas au spawn)
    UpdateHealthUI(health.Value);
}

public override void OnNetworkDespawn()
{
    health.OnValueChanged -= OnHealthChanged;
}

private void OnHealthChanged(int previousValue, int newValue)
{
    UpdateHealthUI(newValue);
    if (newValue <= 0) PlayDeathAnimation();
}
```

### Custom serialization avec INetworkSerializable

Pour synchroniser des structs complexes:

```csharp
public struct PlayerStats : INetworkSerializable
{
    public int Health;
    public int Armor;
    public float Speed;
    public FixedString32Bytes DisplayName;

    public void NetworkSerialize<T>(BufferSerializer<T> serializer) where T : IReaderWriter
    {
        serializer.SerializeValue(ref Health);
        serializer.SerializeValue(ref Armor);
        serializer.SerializeValue(ref Speed);
        serializer.SerializeValue(ref DisplayName);
    }
}

// Utilisation
private NetworkVariable<PlayerStats> stats = new();

[ServerRpc]
private void UpdateStatsServerRpc(PlayerStats newStats)
{
    stats.Value = newStats;
}
```

### NetworkList pour collections dynamiques

```csharp
private NetworkList<int> inventory;

private void Awake()
{
    // NetworkList doit etre initialise dans Awake (pas dans le field initializer)
    inventory = new NetworkList<int>();
}

public override void OnNetworkSpawn()
{
    inventory.OnListChanged += OnInventoryChanged;
}

public override void OnNetworkDespawn()
{
    inventory.OnListChanged -= OnInventoryChanged;
}

private void OnInventoryChanged(NetworkListEvent<int> changeEvent)
{
    switch (changeEvent.Type)
    {
        case NetworkListEvent<int>.EventType.Add:
            Debug.Log($"Item added: {changeEvent.Value}");
            break;
        case NetworkListEvent<int>.EventType.Remove:
            Debug.Log($"Item removed: {changeEvent.Value}");
            break;
        case NetworkListEvent<int>.EventType.Clear:
            Debug.Log("Inventory cleared");
            break;
    }
    RefreshInventoryUI();
}

// Server only
[ServerRpc]
private void AddItemServerRpc(int itemId)
{
    if (inventory.Count < 20) // validation server-side
        inventory.Add(itemId);
}
```

## 2. RPC patterns

### ServerRpc (client -> server)

Pour les actions joueur qui doivent etre validees par le server:

```csharp
[ServerRpc]
private void ShootServerRpc(Vector3 origin, Vector3 direction)
{
    // Le server valide et traite
    if (!CanShoot()) return;

    // Raycast server-side (autoritatif)
    if (Physics.Raycast(origin, direction, out var hit, 100f))
    {
        var target = hit.collider.GetComponent<PlayerController>();
        if (target != null)
        {
            target.TakeDamage(25);
        }
    }

    // Notifier tous les clients pour les effets visuels
    ShootEffectClientRpc(origin, direction);
}
```

### ClientRpc (server -> clients)

Pour les notifications visuelles / audio envoyees a tous:

```csharp
[ClientRpc]
private void ShootEffectClientRpc(Vector3 origin, Vector3 direction)
{
    SpawnMuzzleFlash(origin);
    PlayShootSound();
    SpawnTracer(origin, direction);
}

// ClientRpc cible — envoyer a des clients specifiques
[ClientRpc]
private void ShowMessageClientRpc(FixedString64Bytes message,
    ClientRpcParams rpcParams = default)
{
    ShowNotification(message.ToString());
}

// Appel cible (server-side)
private void NotifyPlayer(ulong clientId, string message)
{
    var rpcParams = new ClientRpcParams
    {
        Send = new ClientRpcSendParams
        {
            TargetClientIds = new[] { clientId }
        }
    };
    ShowMessageClientRpc(message, rpcParams);
}
```

### RequireOwnership = false

Par defaut, seul le owner peut appeler un ServerRpc. Pour permettre
a n'importe quel client d'appeler:

```csharp
// Exemple: interagir avec un objet du monde (pas un joueur)
[ServerRpc(RequireOwnership = false)]
private void InteractServerRpc(ServerRpcParams rpcParams = default)
{
    ulong senderId = rpcParams.Receive.SenderClientId;
    Debug.Log($"Client {senderId} interacted with {gameObject.name}");
    ProcessInteraction(senderId);
}
```

### Pattern complet: action avec validation

```csharp
// Client: demande une action
[ServerRpc]
private void PurchaseItemServerRpc(int itemId, ServerRpcParams rpcParams = default)
{
    ulong clientId = rpcParams.Receive.SenderClientId;

    // Validation server-side
    if (!shopInventory.Contains(itemId))
    {
        PurchaseResultClientRpc(false, "Item not available", GetTargetParams(clientId));
        return;
    }

    int price = GetItemPrice(itemId);
    if (playerGold.Value < price)
    {
        PurchaseResultClientRpc(false, "Not enough gold", GetTargetParams(clientId));
        return;
    }

    // Appliquer la transaction
    playerGold.Value -= price;
    AddItemToInventory(clientId, itemId);
    PurchaseResultClientRpc(true, "Purchase successful", GetTargetParams(clientId));
}

// Server -> client specifique: resultat
[ClientRpc]
private void PurchaseResultClientRpc(bool success, FixedString64Bytes message,
    ClientRpcParams rpcParams = default)
{
    if (success) PlayPurchaseSound();
    ShowNotification(message.ToString());
}

private ClientRpcParams GetTargetParams(ulong clientId)
{
    return new ClientRpcParams
    {
        Send = new ClientRpcSendParams
        {
            TargetClientIds = new[] { clientId }
        }
    };
}
```

## 3. Spawn reseau

### Player prefab (auto-spawne)

Le player prefab assigne dans NetworkManager est spawne automatiquement
pour chaque client qui se connecte. Pas besoin de code.

### Dynamic spawning (server only)

```csharp
[SerializeField] private GameObject projectilePrefab; // Doit etre dans NetworkPrefabs list

[ServerRpc]
private void SpawnProjectileServerRpc(Vector3 position, Vector3 direction)
{
    var go = Instantiate(projectilePrefab, position, Quaternion.LookRotation(direction));
    var netObj = go.GetComponent<NetworkObject>();
    netObj.Spawn(); // Spawne sur tous les clients

    // Optionnel: donner ownership au tireur
    // netObj.ChangeOwnership(OwnerClientId);
}
```

### Despawn propre

```csharp
// Server only — despawne l'objet reseau sur tous les clients
[ServerRpc]
private void DespawnObjectServerRpc()
{
    GetComponent<NetworkObject>().Despawn();
    // Despawn(false) pour ne pas detruire le GameObject (pooling)
}
```

### Object pooling reseau

```csharp
using Unity.Netcode;
using UnityEngine;
using System.Collections.Generic;

public class NetworkObjectPool : MonoBehaviour
{
    public static NetworkObjectPool Instance { get; private set; }

    [SerializeField] private GameObject prefab;
    [SerializeField] private int initialSize = 10;

    private Queue<NetworkObject> pool = new();

    private void Awake()
    {
        Instance = this;
    }

    public void InitializePool()
    {
        for (int i = 0; i < initialSize; i++)
        {
            var go = Instantiate(prefab);
            go.SetActive(false);
            pool.Enqueue(go.GetComponent<NetworkObject>());
        }
    }

    public NetworkObject Get(Vector3 position, Quaternion rotation)
    {
        NetworkObject netObj;
        if (pool.Count > 0)
        {
            netObj = pool.Dequeue();
            netObj.transform.SetPositionAndRotation(position, rotation);
            netObj.gameObject.SetActive(true);
        }
        else
        {
            var go = Instantiate(prefab, position, rotation);
            netObj = go.GetComponent<NetworkObject>();
        }
        return netObj;
    }

    public void Return(NetworkObject netObj)
    {
        netObj.Despawn(false); // Ne pas detruire
        netObj.gameObject.SetActive(false);
        pool.Enqueue(netObj);
    }
}
```

## 4. Ownership et permissions

### Verifier l'ownership

```csharp
// Dans un NetworkBehaviour:
if (IsOwner)    { /* Ce client possede cet objet */ }
if (IsServer)   { /* Ce code tourne sur le server */ }
if (IsHost)     { /* Ce code tourne sur le host (server + client) */ }
if (IsClient)   { /* Ce code tourne sur un client */ }
if (IsLocalPlayer) { /* Equivalent a IsOwner pour les player objects */ }
```

### Transfert d'ownership

```csharp
// Server only — transferer l'ownership a un autre client
[ServerRpc(RequireOwnership = false)]
private void RequestOwnershipServerRpc(ServerRpcParams rpcParams = default)
{
    ulong requesterId = rpcParams.Receive.SenderClientId;

    // Validation: l'objet est-il disponible?
    if (!isLocked)
    {
        GetComponent<NetworkObject>().ChangeOwnership(requesterId);
        isLocked = true;
    }
}
```

### Pattern: objet ramassable

```csharp
public class PickupItem : NetworkBehaviour
{
    private NetworkVariable<bool> isPickedUp = new(false,
        NetworkVariableReadPermission.Everyone,
        NetworkVariableWritePermission.Server);

    [ServerRpc(RequireOwnership = false)]
    public void PickUpServerRpc(ServerRpcParams rpcParams = default)
    {
        if (isPickedUp.Value) return;

        ulong clientId = rpcParams.Receive.SenderClientId;
        isPickedUp.Value = true;
        GetComponent<NetworkObject>().ChangeOwnership(clientId);

        // Desactiver le visuel pour tous
        SetVisibleClientRpc(false);
    }

    [ClientRpc]
    private void SetVisibleClientRpc(bool visible)
    {
        GetComponent<Renderer>().enabled = visible;
        GetComponent<Collider>().enabled = visible;
    }
}
```

## 5. Client-side prediction basique

### Pattern simple: move + reconcile

```csharp
public class PredictedMovement : NetworkBehaviour
{
    [SerializeField] private float moveSpeed = 7f;

    // Position autoritative du server
    private NetworkVariable<Vector3> serverPosition = new(
        default, NetworkVariableReadPermission.Everyone,
        NetworkVariableWritePermission.Server);

    public override void OnNetworkSpawn()
    {
        serverPosition.OnValueChanged += OnServerPositionChanged;
    }

    public override void OnNetworkDespawn()
    {
        serverPosition.OnValueChanged -= OnServerPositionChanged;
    }

    private void Update()
    {
        if (!IsOwner) return;

        var input = new Vector3(Input.GetAxis("Horizontal"), 0, Input.GetAxis("Vertical"));
        if (input.sqrMagnitude < 0.01f) return;

        input = input.normalized;

        // Prediction locale (le joueur voit le mouvement immediatement)
        transform.position += input * (moveSpeed * Time.deltaTime);

        // Envoyer l'input au server pour validation
        MoveServerRpc(input, Time.deltaTime);
    }

    [ServerRpc]
    private void MoveServerRpc(Vector3 input, float deltaTime)
    {
        // Le server applique le meme mouvement (autoritatif)
        var newPos = transform.position + input * (moveSpeed * deltaTime);
        transform.position = newPos;
        serverPosition.Value = newPos;
    }

    private void OnServerPositionChanged(Vector3 oldPos, Vector3 newPos)
    {
        if (IsOwner)
        {
            // Reconciliation: si trop d'ecart, corriger
            float drift = Vector3.Distance(transform.position, newPos);
            if (drift > 0.5f)
            {
                // Snap ou lerp vers la position server
                transform.position = Vector3.Lerp(transform.position, newPos, 0.5f);
            }
        }
        else
        {
            // Les autres clients interpolent vers la position server
            transform.position = newPos;
        }
    }
}
```

### Pattern: interpolation pour les non-owners

```csharp
public class NetworkTransformInterpolation : NetworkBehaviour
{
    private NetworkVariable<Vector3> netPosition = new(
        default, NetworkVariableReadPermission.Everyone,
        NetworkVariableWritePermission.Server);

    private NetworkVariable<Quaternion> netRotation = new(
        default, NetworkVariableReadPermission.Everyone,
        NetworkVariableWritePermission.Server);

    [SerializeField] private float interpolationSpeed = 12f;

    private void Update()
    {
        if (IsOwner) return;

        // Interpoler vers la position reseau
        transform.position = Vector3.Lerp(
            transform.position, netPosition.Value,
            interpolationSpeed * Time.deltaTime);
        transform.rotation = Quaternion.Slerp(
            transform.rotation, netRotation.Value,
            interpolationSpeed * Time.deltaTime);
    }
}
```

Note: pour la plupart des cas, le composant `NetworkTransform` de NGO
gere deja l'interpolation. La version custom est utile si vous avez
besoin de plus de controle.

## 6. Bandwidth optimization

### Tick rate

```csharp
// Dans le NetworkManager ou via code:
NetworkManager.Singleton.NetworkConfig.TickRate = 30; // 30 updates/sec (defaut)
// Reduire a 20 pour les jeux lents, augmenter a 60 pour les FPS competitifs
```

### Batching des inputs

```csharp
// Au lieu d'envoyer un RPC chaque frame...
// Accumuler et envoyer a intervalle fixe

private float sendInterval = 0.05f; // 20 fois par seconde
private float sendTimer;
private Vector3 accumulatedInput;

private void Update()
{
    if (!IsOwner) return;

    accumulatedInput += new Vector3(Input.GetAxis("Horizontal"), 0, Input.GetAxis("Vertical"));
    sendTimer += Time.deltaTime;

    if (sendTimer >= sendInterval)
    {
        SendInputServerRpc(accumulatedInput.normalized);
        accumulatedInput = Vector3.zero;
        sendTimer = 0f;
    }
}

[ServerRpc]
private void SendInputServerRpc(Vector3 input)
{
    ApplyMovement(input);
}
```

### Compression de donnees

```csharp
// Utiliser des types plus petits quand possible
private NetworkVariable<byte> healthByte = new(); // 0-255 au lieu de int
private NetworkVariable<short> posX = new();      // Position en centimetres

// Compresser les quaternions en euler half-precision
public struct CompressedRotation : INetworkSerializable
{
    public short Yaw;   // -180 to 180 mapped to short
    public short Pitch;

    public void NetworkSerialize<T>(BufferSerializer<T> serializer) where T : IReaderWriter
    {
        serializer.SerializeValue(ref Yaw);
        serializer.SerializeValue(ref Pitch);
    }

    public static CompressedRotation FromQuaternion(Quaternion q)
    {
        var euler = q.eulerAngles;
        return new CompressedRotation
        {
            Yaw = (short)(euler.y > 180 ? euler.y - 360 : euler.y),
            Pitch = (short)(euler.x > 180 ? euler.x - 360 : euler.x)
        };
    }

    public Quaternion ToQuaternion()
    {
        return Quaternion.Euler(Pitch, Yaw, 0);
    }
}
```

### Eviter les RPCs inutiles

```csharp
// Mauvais: RPC chaque frame
private void Update()
{
    if (IsOwner) UpdatePositionServerRpc(transform.position); // 60 RPCs/sec
}

// Bon: utiliser NetworkTransform ou NetworkVariable avec seuil
private Vector3 lastSentPosition;
private void Update()
{
    if (!IsOwner) return;
    if (Vector3.Distance(transform.position, lastSentPosition) > 0.01f)
    {
        UpdatePositionServerRpc(transform.position);
        lastSentPosition = transform.position;
    }
}
```

## 7. Test local (2 instances)

### Option A: Multiplayer Play Mode (recommande)

Package officiel Unity pour tester en multi directement dans l'Editor.

```
// Installer via Package Manager:
// com.unity.multiplayer.playmode
// Permet de lancer des "Virtual Players" dans l'Editor
```

### Option B: ParrelSync

Clone le projet pour ouvrir 2 instances d'Editor.

```
// Installer via git URL dans Package Manager:
// https://github.com/VeriorPies/ParRelSync.git
// Menu: ParrelSync > Clones Manager > Create new clone
```

### Option C: Build + Editor

```
// 1. Build un standalone (File > Build Settings > Build)
// 2. Lancer le build comme client
// 3. Lancer l'Editor comme host
// 4. Tester la connexion
```

### Debugging avec Multiplayer Tools

```
// Package: com.unity.multiplayer.tools
// Fournit:
// - Network Profiler (bandwidth, RPCs, packets)
// - Network Simulator (latence, packet loss)
// - Runtime Net Stats Monitor (overlay en jeu)
```

Configuration du Network Simulator pour tester la latence:

```csharp
// Via code (ou via le composant dans l'Inspector)
using Unity.Netcode.Transports.UTP;

var transport = NetworkManager.Singleton.GetComponent<UnityTransport>();
// Simuler 100ms de latence et 5% de packet loss
transport.SetDebugSimulatorParameters(
    packetDelayMS: 100,
    packetJitterMS: 25,
    dropRate: 5
);
```
