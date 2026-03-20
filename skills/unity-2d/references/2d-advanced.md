# 2D Avance : Generation Procedurale & Camera

Patterns avances pour la generation procedurale de Tilemaps et la configuration
camera 2D avec Cinemachine dans Unity 6+.

---

## 4. Tilemap Procedural Generation

Generation procedurale simple avec Perlin Noise pour creer un terrain 2D (grottes, collines). Utilise `Tilemap.SetTile` pour peindre les tiles par code.

```csharp
using UnityEngine;
using UnityEngine.Tilemaps;

public class ProceduralTilemapGenerator : MonoBehaviour
{
    [Header("Tilemap")]
    [SerializeField] private Tilemap tilemap;
    [SerializeField] private TileBase groundTile;
    [SerializeField] private TileBase surfaceTile;

    [Header("Generation")]
    [SerializeField] private int width = 100;
    [SerializeField] private int height = 50;
    [SerializeField] private float noiseScale = 0.08f;
    [SerializeField] private float heightMultiplier = 15f;
    [SerializeField] private int baseHeight = 10;

    [Header("Caves")]
    [SerializeField] private bool generateCaves = true;
    [SerializeField] private float caveNoiseScale = 0.12f;
    [SerializeField] private float caveThreshold = 0.45f;

    [SerializeField] private int seed;

    public void Generate()
    {
        tilemap.ClearAllTiles();
        if (seed == 0) seed = Random.Range(0, 100000);

        for (int x = 0; x < width; x++)
        {
            // Hauteur du terrain via Perlin Noise
            float noiseValue = Mathf.PerlinNoise(
                (x + seed) * noiseScale, seed * noiseScale);
            int terrainHeight = baseHeight
                + Mathf.RoundToInt(noiseValue * heightMultiplier);

            for (int y = 0; y < Mathf.Min(terrainHeight, height); y++)
            {
                // Grottes : deuxieme couche de bruit
                if (generateCaves && y < terrainHeight - 1)
                {
                    float caveNoise = Mathf.PerlinNoise(
                        (x + seed) * caveNoiseScale,
                        (y + seed) * caveNoiseScale);
                    if (caveNoise < caveThreshold) continue; // Vide = grotte
                }

                Vector3Int tilePos = new Vector3Int(x - width / 2, y, 0);
                TileBase tile = (y == terrainHeight - 1)
                    ? surfaceTile : groundTile;
                tilemap.SetTile(tilePos, tile);
            }
        }

        // Rafraichir les tiles pour les Rule Tiles
        tilemap.RefreshAllTiles();
    }

#if UNITY_EDITOR
    [ContextMenu("Regenerer le terrain")]
    private void RegenerateInEditor()
    {
        seed = 0;
        Generate();
    }
#endif
}
```

**Conseils** :
- Utiliser des **Rule Tiles** pour que les bords se connectent automatiquement
- Ajouter un Tilemap Collider 2D + Composite Collider 2D apres generation
- Pour de grandes maps : generer par chunks et utiliser `Tilemap.SetTilesBlock`

---

## 5. Camera 2D Setup (Cinemachine)

Configuration complete d'une camera 2D avec Cinemachine : suivi du joueur, dead zone, confiner aux limites du niveau, et note Pixel Perfect.

```csharp
using UnityEngine;

/// <summary>
/// Script utilitaire pour definir les limites du niveau.
/// Attacher a un GameObject avec un PolygonCollider2D (Is Trigger = true).
/// Le CinemachineConfiner2D reference ce collider.
/// </summary>
public class CameraBoundsSetup : MonoBehaviour
{
    [Tooltip("Activer pour dessiner les bounds dans la Scene view")]
    [SerializeField] private bool showGizmos = true;

    private void Awake()
    {
        // S'assurer que le collider est en trigger
        var col = GetComponent<Collider2D>();
        if (col != null) col.isTrigger = true;
    }

    private void OnDrawGizmos()
    {
        if (!showGizmos) return;
        var col = GetComponent<PolygonCollider2D>();
        if (col == null) return;

        Gizmos.color = new Color(0f, 1f, 0.5f, 0.3f);
        for (int i = 0; i < col.points.Length; i++)
        {
            Vector2 current = (Vector2)transform.position + col.points[i];
            Vector2 next = (Vector2)transform.position
                + col.points[(i + 1) % col.points.Length];
            Gizmos.DrawLine(current, next);
        }
    }
}
```

### Setup Cinemachine dans l'editeur

1. **CinemachineCamera** sur un GameObject :
   - Follow = Transform du joueur
   - Body = **CinemachinePositionComposer**
     - Dead Zone Width/Height = 0.1 (petite zone sans mouvement)
     - Lookahead Time = 0.2 (anticipe le mouvement)
     - Damping = 0.5 (lissage du suivi)

2. **CinemachineConfiner2D** (extension) :
   - Bounding Shape 2D = PolygonCollider2D du bounds de niveau
   - Damping = 0.3

3. **Pixel Perfect** (optionnel) :
   - Ajouter le package **2D Pixel Perfect**
   - Composant `PixelPerfectCamera` sur la Camera principale
   - Assets PPU = PPU des sprites (ex: 16)
   - Ref Resolution = resolution cible (ex: 320x180 pour du 16:9 pixel art)
   - Crop Frame = Pixel Perfect dans Cinemachine

### Notes multi-camera / zones

Pour un Metroidvania avec des zones de camera differentes :
- Creer un **CinemachineConfiner2D** par zone avec des PolygonCollider2D separes
- Utiliser des **Trigger Zones** pour changer le confiner actif
- Transition douce via le **Damping** du confiner (0.3-0.5s)

```csharp
using Unity.Cinemachine;
using UnityEngine;

public class CameraZoneTrigger : MonoBehaviour
{
    [SerializeField] private Collider2D zoneBounds;
    private CinemachineConfiner2D confiner;

    private void Awake()
    {
        confiner = FindAnyObjectByType<CinemachineConfiner2D>();
    }

    private void OnTriggerEnter2D(Collider2D other)
    {
        if (!other.CompareTag("Player")) return;
        confiner.BoundingShape2D = zoneBounds;
        confiner.InvalidateBoundingShapeCache();
    }
}
```
