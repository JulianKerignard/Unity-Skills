# Templates de prototypage par genre

## 3D Platformer

Scripts necessaires :
- `PlayerController.cs` : CharacterController, mouvement WASD, saut avec ground check (`Physics.Raycast` vers le bas), gravite manuelle
- `MovingPlatform.cs` : `Transform.Translate` avec `Mathf.PingPong`, le joueur suit via `OnTriggerStay` et parenting temporaire

Objets scene :
- Player (Capsule + CharacterController)
- Ground (Plane scale 10)
- Platforms (Cubes scale (3,0.5,3) en hauteur)
- MovingPlatform (Cube + MovingPlatform.cs + BoxCollider trigger enfant)
- Goal (Sphere jaune en hauteur, trigger, affiche "WIN" on contact)

## FPS

Scripts necessaires :
- `FPSController.cs` : CharacterController + mouvement, `Camera.main.transform` pour mouse look, raycast sur clic gauche avec `Debug.DrawRay`
- `EnemyHealth.cs` : variable `hp`, methode `TakeDamage(int)`, `Destroy(gameObject)` quand hp <= 0, feedback = changer couleur en rouge avant destruction
- Optionnel `Spawner.cs` : `InvokeRepeating` pour spawn d'ennemis a intervalles

Objets scene :
- Player (Capsule + FPSController + Camera enfant a (0, 0.5, 0))
- Cursor lock dans Start : `Cursor.lockState = CursorLockMode.Locked`
- Enemies (Cubes rouges + EnemyHealth + Collider)
- Ground (Plane)

## Top-Down 2D

Scripts necessaires :
- `PlayerMovement2D.cs` : `Rigidbody2D.velocity` avec `Input.GetAxis`, rotation vers la souris avec `Mathf.Atan2`
- `Bullet.cs` : `transform.Translate(Vector3.up * speed * Time.deltaTime)`, `Destroy(gameObject, 3f)`, `OnTriggerEnter2D` pour degats
- `EnemyPatrol2D.cs` : mouvement entre waypoints (2 transforms), `OnTriggerEnter2D` avec le joueur pour degats

Objets scene (tout en 2D) :
- Player (Sprite ou Square + Rigidbody2D + CircleCollider2D)
- Camera orthographique
- BulletPrefab (petit sprite + Bullet.cs + Rigidbody2D kinematic + CircleCollider2D trigger)
- Enemies (Sprites + EnemyPatrol2D + points A et B enfants)

## Puzzle (grid-based)

Scripts necessaires :
- `GridManager.cs` : tableau 2D `int[,]`, detection clic avec `Camera.main.ScreenToWorldPoint`, changement d'etat de la case, verification de condition de victoire (toutes les cases dans le bon etat)
- `Tile.cs` : `SpriteRenderer` ou `MeshRenderer`, methode `Toggle()` qui change couleur/etat, feedback visuel immediat

Objets scene :
- Grid parent vide
- Tiles generees par `GridManager.Start()` via `Instantiate` de Quads
- UI Text pour afficher "VICTOIRE"

## Runner / Endless

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

## Tower Defense

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
