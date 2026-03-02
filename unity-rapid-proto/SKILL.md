---
name: "Unity Rapid Proto"
description: "Prototypage instantane de gameplay Unity. Triggers: /proto, /prototype, 'prototyper', 'idee de jeu', 'tester une mechanique', 'rapid proto'. Transforme une idee de gameplay en scene jouable avec le minimum de code. Produit 1-3 scripts MonoBehaviour, les instructions de setup scene, et une checklist de test. Aucune architecture, aucun planning -- juste du code jouable."
---

# Unity Rapid Proto

## Ce que fait cette skill

Transforme une idee de gameplay brute en prototype jouable Unity. Pas de GDD, pas de planning, pas d'architecture. On va droit au code minimum pour tester la mechanique.

Produit :
- 1 a 3 scripts C# (MonoBehaviour uniquement)
- Les instructions de setup scene (hierarchy, components, valeurs)
- Une checklist "press Play" pour verifier que ca marche

## Prerequis

- Projet Unity existant
- Un dossier `Assets/Prototypes/` (sera cree si absent)
- Connaissance du concept a prototyper en 1-2 phrases

## Arbre de decision

```
Type de prototype ?
|
+-- 3D gameplay ?
|   +-- Deplacement + exploration --> Template 3D Platformer
|   +-- Tir / combat --> Template FPS
|   +-- Placement strategique --> Template Tower Defense
|   +-- Course automatique --> Template Runner / Endless
|
+-- 2D gameplay ?
|   +-- Deplacement top-down --> Template Top-Down 2D
|   +-- Puzzle / grille --> Template Puzzle (grid-based)
|   +-- Platformer 2D --> Adapter Template 3D Platformer en 2D
|
+-- Pas sur ?
    +-- Commencer en 3D (plus visuel, plus facile a debloquer)
```

## Demarrage rapide

1. L'utilisateur decrit son idee en 1-2 phrases
2. Identifier LA mechanique centrale
3. Generer les scripts (max 3, max 100 lignes chacun)
4. Ecrire les instructions de setup scene
5. Fournir la checklist de test

## Guide etape par etape

### Etape 1 : Comprendre l'idee

Demander a l'utilisateur de decrire son idee en 1-2 phrases maximum. Ne PAS demander de details supplementaires. Ne PAS produire de document de design.

Extraire :
- Le verbe principal (sauter, tirer, placer, esquiver, collecter)
- Le contexte spatial (2D/3D, vue camera)
- La condition de fin (score, timer, survie, puzzle resolu)

### Etape 2 : Identifier la mechanique core

Choisir UNE seule mechanique a prototyper. Si l'idee contient plusieurs mecaniques, prendre celle qui definit le gameplay loop principal.

Exemples de reduction :
- "Un jeu ou on construit des tours pour defendre une base contre des vagues d'ennemis" -> Mechanique core : placement de tourelles + path following
- "Un platformer avec des pouvoirs magiques et du crafting" -> Mechanique core : mouvement + saut (le reste viendra apres)
- "Un FPS multijoueur avec des classes" -> Mechanique core : deplacement + tir raycast

### Etape 3 : Generer le code minimal

Structure type :
- `PlayerController.cs` : mouvement + action principale (max 80 lignes)
- 1-2 scripts gameplay selon le besoin (max 60 lignes chacun)

Regles de code :
```
- MonoBehaviour uniquement, pas de ScriptableObject
- Input.GetKey / Input.GetAxis (ancien systeme, plus simple)
- Valeurs hardcodees (pas de SerializeField sauf si vraiment utile)
- Visuels = primitives Unity (Cube, Sphere, Capsule, Plane)
- Pas de namespace, pas de pattern, pas d'event system
- Un seul fichier = une seule responsabilite evidente
- 1 commentaire par bloc non-evident, pas plus
```

> **Note Input System (Unity 6+)** : Si le projet utilise le New Input System (defaut dans Unity 6), remplacer les appels `Input.*` :
> - `Input.GetKey(KeyCode.Space)` → `Keyboard.current[Key.Space].isPressed`
> - `Input.GetKeyDown(KeyCode.Space)` → `Keyboard.current[Key.Space].wasPressedThisFrame`
> - `Input.GetAxis("Horizontal")` → `Gamepad.current.leftStick.x.ReadValue()` ou InputAction
> - `Input.GetMouseButton(0)` → `Mouse.current.leftButton.isPressed`
>
> Pour un prototype rapide, le old Input Manager reste plus simple. Verifier `Edit > Project Settings > Player > Active Input Handling`.

### Etape 4 : Ecrire les instructions de setup

Fournir dans cet ordre exact :
1. Scene : creer une nouvelle scene ou utiliser SampleScene
2. Objets a creer (avec nom, primitive, position, scale)
3. Components a ajouter sur chaque objet
4. Hierarchy parent/enfant si necessaire
5. Tags et Layers necessaires
6. Camera setup (position, rotation)

Format :
```
## Setup Scene

1. Creer un objet **Player** : Capsule a position (0, 1, 0)
   - Ajouter `PlayerController.cs`
   - Ajouter Rigidbody (Use Gravity: true, Freeze Rotation X/Z)

2. Creer un objet **Ground** : Plane a position (0, 0, 0), scale (5, 1, 5)
   - Tag: "Ground"
```

### Etape 5 : Checklist "press Play"

Lister exactement ce qui doit se passer quand on appuie sur Play :
```
## Test checklist

- [ ] Le joueur se deplace avec WASD/fleches
- [ ] Le joueur saute avec Space et retombe
- [ ] Les ennemis apparaissent toutes les 3 secondes
- [ ] Le score augmente quand on touche un ennemi
- [ ] Game Over s'affiche quand la vie atteint 0
```

## Templates par genre

### 3D Platformer

Scripts necessaires :
- `PlayerController.cs` : CharacterController, mouvement WASD, saut avec ground check (`Physics.Raycast` vers le bas), gravite manuelle
- `MovingPlatform.cs` : `Transform.Translate` avec `Mathf.PingPong`, le joueur suit via `OnTriggerStay` et parenting temporaire

Objets scene :
- Player (Capsule + CharacterController)
- Ground (Plane scale 10)
- Platforms (Cubes scale (3,0.5,3) en hauteur)
- MovingPlatform (Cube + MovingPlatform.cs + BoxCollider trigger enfant)
- Goal (Sphere jaune en hauteur, trigger, affiche "WIN" on contact)

### FPS

Scripts necessaires :
- `FPSController.cs` : CharacterController + mouvement, `Camera.main.transform` pour mouse look, raycast sur clic gauche avec `Debug.DrawRay`
- `EnemyHealth.cs` : variable `hp`, methode `TakeDamage(int)`, `Destroy(gameObject)` quand hp <= 0, feedback = changer couleur en rouge avant destruction
- Optionnel `Spawner.cs` : `InvokeRepeating` pour spawn d'ennemis a intervalles

Objets scene :
- Player (Capsule + FPSController + Camera enfant a (0, 0.5, 0))
- Cursor lock dans Start : `Cursor.lockState = CursorLockMode.Locked`
- Enemies (Cubes rouges + EnemyHealth + Collider)
- Ground (Plane)

### Top-Down 2D

Scripts necessaires :
- `PlayerMovement2D.cs` : `Rigidbody2D.velocity` avec `Input.GetAxis`, rotation vers la souris avec `Mathf.Atan2`
- `Bullet.cs` : `transform.Translate(Vector3.up * speed * Time.deltaTime)`, `Destroy(gameObject, 3f)`, `OnTriggerEnter2D` pour degats
- `EnemyPatrol2D.cs` : mouvement entre waypoints (2 transforms), `OnTriggerEnter2D` avec le joueur pour degats

Objets scene (tout en 2D) :
- Player (Sprite ou Square + Rigidbody2D + CircleCollider2D)
- Camera orthographique
- BulletPrefab (petit sprite + Bullet.cs + Rigidbody2D kinematic + CircleCollider2D trigger)
- Enemies (Sprites + EnemyPatrol2D + points A et B enfants)

### Puzzle (grid-based)

Scripts necessaires :
- `GridManager.cs` : tableau 2D `int[,]`, detection clic avec `Camera.main.ScreenToWorldPoint`, changement d'etat de la case, verification de condition de victoire (toutes les cases dans le bon etat)
- `Tile.cs` : `SpriteRenderer` ou `MeshRenderer`, methode `Toggle()` qui change couleur/etat, feedback visuel immediat

Objets scene :
- Grid parent vide
- Tiles generees par `GridManager.Start()` via `Instantiate` de Quads
- UI Text pour afficher "VICTOIRE"

### Runner / Endless

Scripts necessaires :
- `RunnerPlayer.cs` : deplacement automatique `transform.Translate(Vector3.forward * speed * Time.deltaTime)`, input gauche/droite pour les lanes (3 positions X fixes), saut
- `ObstacleSpawner.cs` : `InvokeRepeating` avec `Instantiate` de Cubes a des positions aleatoires devant le joueur, `Destroy` apres un temps
- `ScoreManager.cs` : score qui augmente avec `Time.deltaTime`, affichage UI, game over sur collision

Objets scene :
- Player (Capsule + RunnerPlayer)
- Ground (Plane tres long ou qui se regenere)
- Camera enfant du Player (ou qui suit avec offset)
- SpawnPoint vide devant le joueur (+ ObstacleSpawner)
- Canvas + Text pour score

### Tower Defense

Scripts necessaires :
- `Turret.cs` : detecte l'ennemi le plus proche dans un rayon (`Physics.OverlapSphere`), `transform.LookAt`, tir avec `InvokeRepeating` (Instantiate projectile ou raycast)
- `EnemyPath.cs` : suit un tableau de waypoints (`Transform[]`), `transform.MoveTowards`, quand arrive au dernier waypoint = degats a la base, `Destroy`
- `TurretPlacer.cs` : raycast depuis la souris sur clic, `Instantiate` tourelle a la position touchee, cout en monnaie (variable simple)

Objets scene :
- Waypoints (GameObjects vides en chemin)
- SpawnPoint au premier waypoint (spawn avec `InvokeRepeating`)
- Ground (Plane)
- Enemies (Spheres + EnemyPath + reference aux waypoints)
- UI pour monnaie et vies de la base

## Skills connexes

- Le prototype fonctionne et on veut passer en production ? Utiliser `/unity-code-gen` (Unity Code Gen) pour restructurer avec les bons patterns
- Bug dans le prototype ? Utiliser `/unity-debug` (Unity Debug)

## Regles strictes

**TOUJOURS :**
- Utiliser des primitives Unity pour les visuels (Cube, Sphere, Capsule, Plane)
- Inclure une condition de victoire/defaite ou un feedback loop
- Utiliser `Input.GetKey` / `Input.GetAxis` (ancien input system)
- Garder les valeurs hardcodees (vitesse, vie, degats)
- Ecrire le code dans `Assets/Prototypes/<NomPrototype>/`
- Tester mentalement chaque script : est-ce que ca compile ? est-ce que ca fait quelque chose de visible ?

**JAMAIS :**
- Plus de 3 scripts par prototype
- Plus de 100 lignes par script (80 pour le PlayerController)
- D'architecture : pas de SO, pas d'events, pas de managers, pas de singletons
- De documentation ou README
- De commentaires abondants (1 ligne par bloc non-evident maximum)
- De SerializeField sauf si absolument necessaire pour le workflow scene
- De namespace, d'interface, de classe abstraite, de generics
- D'asset externe, de package additionnel, d'Asset Store

## Troubleshooting

| Probleme | Solution |
|----------|----------|
| Le joueur ne bouge pas | Verifier que le script est attache au bon GameObject. Verifier que `CharacterController` ou `Rigidbody` est present. |
| Le joueur tombe a travers le sol | Verifier que le sol a un Collider. Verifier que le joueur a un Collider + Rigidbody (ou CharacterController). |
| Le saut ne fonctionne pas | Verifier le ground check : le raycast doit pointer vers `Vector3.down` avec une distance legerement superieure a la moitie de la hauteur du joueur. |
| Les collisions ne detectent pas | Verifier qu'au moins un des deux objets a un Rigidbody. Si on utilise `OnTriggerEnter`, le Collider doit etre marque "Is Trigger". |
| La camera tremble | Deplacer la logique camera dans `LateUpdate` au lieu de `Update`. |
| Les ennemis n'apparaissent pas | Verifier que le prefab est assigne ou que `Instantiate` utilise le bon reference. Verifier que `InvokeRepeating` est appele dans `Start`. |
| Le score ne s'affiche pas | Verifier la reference au `Text` ou `TextMeshProUGUI`. Verifier que le Canvas a un EventSystem. |
| Le prototype est trop lent | Supprimer les `Debug.Log` dans Update. Verifier qu'on ne fait pas d'Instantiate/Destroy massif (passer a un pool basique si necessaire). |
