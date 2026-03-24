# Netcode Avance : Prediction, Bandwidth & Test

Patterns avances pour Netcode for GameObjects : client-side prediction,
interpolation, optimisation bande passante, et test/debugging.

---

## 4. Object pooling reseau

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

---

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

---

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

---

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
