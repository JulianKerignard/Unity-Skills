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

Voir `netcode-advanced.md` pour l'implementation complete du pool reseau
(`NetworkObjectPool` avec `Despawn(false)` et reactivation).

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
