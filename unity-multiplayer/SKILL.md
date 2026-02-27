---
name: "Unity Multiplayer"
description: "Developpement multijoueur avec Netcode for GameObjects. Setup reseau, NetworkBehaviour, synchronisation d'etat, RPCs, lobby et relay. Triggers: /netcode, /multiplayer, 'NetworkBehaviour', 'NetworkVariable', 'ServerRpc', 'ClientRpc', 'lobby', 'multijoueur', 'Netcode for GameObjects', 'mode host', 'dedicated server'."
---

# Unity Multiplayer — Netcode for GameObjects (NGO)

## Ce que fait cette skill

Guider le developpement multijoueur avec **Netcode for GameObjects** (NGO).
Couvre le setup reseau, la creation de NetworkBehaviours, la synchronisation
d'etat via NetworkVariables, la communication par RPCs (ServerRpc / ClientRpc),
et l'integration Unity Gaming Services (Lobby + Relay).

Scope: NGO uniquement. Pas DOTS Netcode, pas Mirror, pas Photon.

## Prerequis

- Package `com.unity.netcode.gameobjects` (>= 1.5.0)
- Un GameObject `NetworkManager` dans la scene
- Unity Transport (`com.unity.transport`) comme couche transport
- (Optionnel) Compte Unity Gaming Services pour Lobby / Relay

## Demarrage rapide

1. **Installer le package** — Window > Package Manager > `Netcode for GameObjects`
2. **Ajouter NetworkManager** — GameObject vide avec composant `NetworkManager`
3. **Configurer le transport** — Ajouter `UnityTransport` sur le meme GameObject, l'assigner dans NetworkManager
4. **Creer le player prefab** — Prefab avec `NetworkObject` + votre `NetworkBehaviour`
5. **Assigner le prefab** dans NetworkManager > Player Prefab
6. **Tester en mode host** — `NetworkManager.Singleton.StartHost()`

## Arbre de decision

```
Architecture reseau...
+-- Prototype / local coop ?
|   +-- -> Host mode (client + server sur meme machine)
+-- Jeu en ligne casual (2-8 joueurs) ?
|   +-- -> Host mode + Unity Relay (pas besoin de serveur dedie)
+-- Jeu competitif / anti-cheat important ?
|   +-- -> Dedicated server (autoritative)
+-- Besoin de matchmaking ?
    +-- -> Unity Lobby + Relay
```

## Guide etape par etape

### Step 1 — Setup NetworkManager

```csharp
// Scene setup:
// 1. GameObject "NetworkManager" avec composant NetworkManager
// 2. Ajouter UnityTransport comme NetworkTransport
// 3. Assigner le Player Prefab (doit avoir NetworkObject)

// Demarrer une session depuis votre UI:
public void StartAsHost()  => NetworkManager.Singleton.StartHost();
public void StartAsServer()=> NetworkManager.Singleton.StartServer();
public void StartAsClient()=> NetworkManager.Singleton.StartClient();
```

### Step 2 — Creer un NetworkBehaviour

```csharp
using Unity.Netcode;
using UnityEngine;

public class PlayerController : NetworkBehaviour
{
    [SerializeField] private float speed = 5f;

    // NetworkVariable — synchronise automatiquement server -> clients
    private NetworkVariable<int> score = new(0,
        NetworkVariableReadPermission.Everyone,
        NetworkVariableWritePermission.Server);

    public override void OnNetworkSpawn()
    {
        if (IsOwner)
        {
            // Setup specifique au joueur local
        }
        score.OnValueChanged += OnScoreChanged;
    }

    public override void OnNetworkDespawn()
    {
        score.OnValueChanged -= OnScoreChanged;
    }

    private void Update()
    {
        if (!IsOwner) return; // Seul le owner controle son personnage

        var input = new Vector3(Input.GetAxis("Horizontal"), 0, Input.GetAxis("Vertical"));
        transform.position += input * (speed * Time.deltaTime);
    }

    // Server RPC — appele par le client, execute sur le server
    [ServerRpc]
    public void AddScoreServerRpc(int points)
    {
        score.Value += points;
    }

    private void OnScoreChanged(int oldValue, int newValue)
    {
        Debug.Log($"Score: {oldValue} -> {newValue}");
    }
}
```

### Step 3 — Setup Lobby + Relay (optionnel, pour jeu en ligne)

```csharp
using System.Collections.Generic;
using System.Threading.Tasks;
using Unity.Netcode;
using Unity.Netcode.Transports.UTP;
using Unity.Services.Authentication;
using Unity.Services.Core;
using Unity.Services.Lobbies;
using Unity.Services.Lobbies.Models;
using Unity.Services.Relay;
using UnityEngine;

public class LobbyManager : MonoBehaviour
{
    private async void Start()
    {
        await UnityServices.InitializeAsync();
        await AuthenticationService.Instance.SignInAnonymouslyAsync();
    }

    public async Task<string> CreateLobby(string name, int maxPlayers)
    {
        var allocation = await RelayService.Instance.CreateAllocationAsync(maxPlayers - 1);
        var joinCode = await RelayService.Instance.GetJoinCodeAsync(allocation.AllocationId);

        var options = new CreateLobbyOptions
        {
            Data = new Dictionary<string, DataObject>
            {
                { "joinCode", new DataObject(DataObject.VisibilityOptions.Public, joinCode) }
            }
        };

        var lobby = await LobbyService.Instance.CreateLobbyAsync(name, maxPlayers, options);

        // Setup Relay transport
        var transport = NetworkManager.Singleton.GetComponent<UnityTransport>();
        transport.SetRelayServerData(allocation);
        NetworkManager.Singleton.StartHost();

        return lobby.Id;
    }

    public async Task JoinLobby(string lobbyId)
    {
        var lobby = await LobbyService.Instance.JoinLobbyByIdAsync(lobbyId);
        var joinCode = lobby.Data["joinCode"].Value;

        var allocation = await RelayService.Instance.JoinAllocationAsync(joinCode);

        var transport = NetworkManager.Singleton.GetComponent<UnityTransport>();
        transport.SetRelayServerData(allocation);
        NetworkManager.Singleton.StartClient();
    }
}
```

## Regles strictes

**TOUJOURS:**
- Verifier `IsOwner` avant de traiter l'input joueur
- Verifier `IsServer` avant de modifier l'etat autoritatif
- Utiliser `NetworkVariable` pour l'etat synchronise (pas de champs classiques)
- Suffixer les RPCs : methodes en `ServerRpc` et `ClientRpc`
- Implementer `OnNetworkSpawn` / `OnNetworkDespawn` (pas Start/OnDestroy pour la logique reseau)
- Desabonner les callbacks `OnValueChanged` dans `OnNetworkDespawn`

**JAMAIS:**
- D'`Instantiate` direct en multi — utiliser `NetworkObject.Spawn()` (server only)
- De logique client qui modifie l'etat server directement
- De `NetworkVariable<string>` ou types reference sans custom serialization
- De `Update()` couteux sur des objets non-owner sans raison

**PREFERER:**
- `NetworkVariable` pour l'etat continu (position, health, score)
- `ServerRpc` pour les actions ponctuelles (tirer, acheter, interagir)
- `ClientRpc` pour les feedbacks visuels/audio (explosions, sons)

## Skills connexes

- `/unity-code-gen` — generer des NetworkBehaviour types
- `/unity-build-config` — configuration de build pour dedicated server
- `/unity-test` — tester avec plusieurs instances en parallele

## Troubleshooting

| Probleme | Solution |
|----------|----------|
| "NetworkObject is not spawned" | Verifier que le prefab a un composant NetworkObject et est spawne via NetworkManager |
| ServerRpc pas appele | Verifier le suffixe `ServerRpc` dans le nom de methode et que l'appelant est le owner (ou `RequireOwnership = false`) |
| Desync d'etat | Utiliser NetworkVariable au lieu de variables locales. Verifier les read/write permissions |
| Latence visible | Implementer client-side prediction (voir references/netcode-patterns.md) |
| "Object already spawned" | Ne pas appeler Spawn() sur un objet deja spawne. Verifier le flow de spawn |
| Client ne se connecte pas | Verifier l'adresse/port dans UnityTransport. En Relay, verifier le join code |
| NetworkVariable pas mise a jour | Seul le server (ou owner selon WritePermission) peut ecrire. Verifier les permissions |
