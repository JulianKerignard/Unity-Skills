# 2D Rendering, Sprites & Lighting

Guide complet pour le rendu 2D dans Unity 6+ avec URP : Sprite Atlas, Light2D, Shadow Caster, Sorting Layers, Sprite Swap et optimisation Tilemap.

---

## 1. Sprite Atlas Workflow

Le Sprite Atlas regroupe plusieurs sprites dans une seule texture pour reduire les draw calls via le batching.

### Creation

1. Create > 2D > Sprite Atlas
2. Glisser les sprites ou dossiers dans la liste **Objects for Packing**
3. Configurer les settings selon la plateforme cible

### Settings recommandes

| Setting | Mobile | PC/Console |
|---------|--------|------------|
| Max Texture Size | 2048 | 4096 |
| Allow Rotation | false | false |
| Tight Packing | true | true |
| Padding | 4 px | 2 px |
| Filter Mode | Point (pixel art) / Bilinear | Bilinear |
| Compression | ASTC 6x6 (mobile) | DXT5 / BC7 |

### Variant Atlas (qualite reduite)

Pour les appareils bas de gamme, creer un **Variant Atlas** :
1. Creer un deuxieme Sprite Atlas
2. Assigner le Master Atlas dans le champ **Master**
3. Regler le **Scale** a 0.5 (moitie de la resolution)
4. Unity choisit automatiquement selon la plateforme de build

### Bonnes pratiques

- **1 atlas par ecran/zone** (menu, gameplay, HUD) pour eviter de charger tout en memoire
- **Ne pas mixer** des sprites de tailles tres differentes dans le meme atlas
- **Sprite Atlas Analyser** (Unity 6.3+) : Window > 2D > Sprite Atlas Analyser pour visualiser le remplissage et detecter le gaspillage
- Verifier le batching avec le **Frame Debugger** (Window > Analysis > Frame Debugger)

---

## 2. Light2D Setup

Le systeme d'eclairage 2D de URP utilise le composant **Light 2D** avec 5 types.

### Types de Light2D

| Type | Usage | Proprietes cles |
|------|-------|-----------------|
| **Global** | Lumiere ambiante de la scene | Intensity, Color |
| **Freeform** | Zone de lumiere personnalisee (polygone editable) | Falloff, Intensity, Color |
| **Sprite** | Lumiere basee sur une texture (cookie) | Sprite, Intensity |
| **Spot** | Cone de lumiere directionnel | Inner/Outer Angle, Falloff |
| **Point** | Lumiere radiale omnidirectionnelle | Inner/Outer Radius, Falloff |

### Configuration

1. **2D Renderer Data** : dans le Renderer, verifier que **Light Blending** est active (Blend Styles)
2. **Blend Styles** : par defaut 2 styles disponibles (Multiply, Additive). Configurer dans le 2D Renderer Data.
3. **Target Sorting Layers** : chaque Light2D peut cibler des Sorting Layers specifiques. Utiliser cela pour eclairer uniquement les personnages et pas le fond, ou inversement.

### Exemple de setup d'eclairage

```
Scene eclairee :
- Global Light : Intensity 0.15, Color bleu sombre (nuit)
- Point Light sur le joueur : Intensity 1.0, Outer Radius 5, Color jaune chaud
- Freeform Light sur les fenetres : Intensity 0.8, Color orange
- Sprite Light sur les torches : texture flamme, Intensity 1.2
```

### Performance

- Limiter le nombre de lights actives simultanement (< 10 sur mobile)
- Utiliser `Light2D.enabled = false` pour les lumieres hors ecran
- Preferer **Point Light** a **Freeform** quand possible (moins couteux)

---

## 3. Shadow Caster 2D

Les ombres 2D necessitent le composant **ShadowCaster2D** sur les objets qui projettent des ombres.

### Setup

1. Ajouter **ShadowCaster2D** sur le GameObject
2. Cocher **Use Renderer Silhouette** pour generer la forme depuis le SpriteRenderer
3. Cocher **Self Shadow** si l'objet doit recevoir sa propre ombre

### Composite Shadow Caster

Pour un Tilemap ou un groupe d'objets enfants :
1. Ajouter **CompositeShadowCaster2D** sur le parent
2. Ajouter **ShadowCaster2D** sur chaque enfant (ou sur le Tilemap)
3. Le composite fusionne toutes les ombres en une seule forme optimisee

### Parametres des ombres dans le 2D Renderer

Dans le **2D Renderer Data** :
- **Shadow Intensity** : 0.0 (pas d'ombre) a 1.0 (ombre opaque)
- **Shadow Volume Intensity** : intensite du volume de l'ombre
- **Shadow Softness** : adoucissement des bords (plus couteux)

---

## 4. Sorting Layers Strategy

L'ordre de rendu en 2D est crucial. Utiliser les **Sorting Layers** et **Order in Layer** pour controler l'affichage.

### Ordre recommande

```
Sorting Layers (du plus eloigne au plus proche) :
  0. Background        -- ciels, arriere-plans parallaxe
  1. Tilemap           -- sol, murs, decors
  2. Props             -- objets interactifs, decorations
  3. Characters        -- joueur, ennemis, NPC
  4. Foreground        -- elements devant les personnages (feuillage, brume)
  5. VFX               -- particules, effets visuels
  6. UI                -- elements d'interface in-world
```

### Order in Layer

Au sein d'un meme Sorting Layer, l'**Order in Layer** (entier) determine l'ordre. Valeurs negatives = derriere, positives = devant.

### Sorting Group

Pour un objet compose de plusieurs SpriteRenderers (personnage avec arme, chapeau) :
1. Ajouter un **SortingGroup** sur le parent
2. Tous les enfants sont tries entre eux mais le groupe entier est traite comme une unite dans le Sorting Layer
3. Cela evite les problemes d'entrelacement avec d'autres objets

### Tri dynamique (Y-sorting)

Pour un top-down ou les objets se chevauchent selon leur position Y :
- Aller dans Edit > Project Settings > Graphics > Camera Settings
- **Transparency Sort Mode** = Custom Axis
- **Transparency Sort Axis** = (0, 1, 0) pour trier par Y
- Alternative : script qui met a jour `SpriteRenderer.sortingOrder` selon `transform.position.y`

---

## 5. Sprite Library + Sprite Swap

Le systeme **Sprite Library** (package 2D Animation) permet de changer les sprites au runtime sans modifier les animations.

### Setup

1. Creer un **Sprite Library Asset** (Create > 2D > Sprite Library Asset)
2. Definir des **Categories** (ex: `Head`, `Body`, `Weapon`)
3. Dans chaque categorie, ajouter des **Labels** (ex: Head > `default`, `angry`, `happy`)
4. Assigner un sprite a chaque label

### Utilisation

1. Ajouter **SpriteLibrary** sur le GameObject racine du personnage
2. Assigner le Sprite Library Asset
3. Sur chaque partie du corps : ajouter **SpriteResolver**
4. Le SpriteResolver choisit la categorie + label a afficher

### Swap au runtime

```csharp
using UnityEngine.U2D.Animation;

public class SkinSwapper : MonoBehaviour
{
    [SerializeField] private SpriteLibraryAsset skinA;
    [SerializeField] private SpriteLibraryAsset skinB;
    private SpriteLibrary library;

    private void Awake() => library = GetComponent<SpriteLibrary>();

    public void SwapSkin(bool useB)
    {
        library.spriteLibraryAsset = useB ? skinB : skinA;
    }
}
```

### Cas d'usage

- Changement d'armure / equipement
- Expressions faciales
- Variantes de couleur d'un personnage
- Skins deblocables

---

## 6. Pixel Art Import Settings

Configuration precise pour que le pixel art soit net dans Unity.

### Settings obligatoires

| Setting | Valeur | Raison |
|---------|--------|--------|
| **Texture Type** | Sprite (2D and UI) | Standard pour les sprites |
| **Sprite Mode** | Single ou Multiple | Multiple pour les spritesheets |
| **Pixels Per Unit** | Taille de la tuile (16, 32) | Coherence avec le Tilemap |
| **Filter Mode** | **Point (no filter)** | Pas de flou entre les pixels |
| **Compression** | **None** | Aucun artefact de compression |
| **Max Size** | Taille reelle de la texture | Pas de downscale |

### Sprite Editor pour les spritesheets

1. Ouvrir le Sprite Editor
2. Slice > **Grid by Cell Size** > entrer la taille d'une frame (ex: 32x32)
3. Verifier que le **Pivot** est coherent (Bottom pour un platformer, Center pour du top-down)
4. Nommer chaque sprite pour les retrouver facilement dans les animations

### Camera Pixel Perfect

- Installer le package **2D Pixel Perfect**
- Ajouter `PixelPerfectCamera` sur la camera
- **Assets PPU** = PPU des sprites
- **Reference Resolution** = resolution logique (ex: 320x180)
- **Upscale Render Texture** = true pour un rendu net a toute resolution

---

## 7. 2D/3D Mixing (Unity 6.3+)

A partir de Unity 6.3, le **2D Renderer** peut afficher des **MeshRenderers** (objets 3D) dans un contexte 2D.

### Configuration

1. Dans le 2D Renderer Data, activer la prise en charge des MeshRenderers
2. Les objets 3D participent au systeme de Sorting Layers 2D
3. Utiliser un **SortingGroup** sur l'objet 3D pour le placer dans l'ordre de tri 2D

### Sort 3D As 2D

Le parametre **Sort 3D As 2D** dans le SortingGroup permet aux MeshRenderers d'etre tries exactement comme des SpriteRenderers :
- Meme systeme de Sorting Layer + Order in Layer
- Compatible avec le Y-sorting

### Cas d'usage

- Decors 3D dans un jeu 2D (parallaxe avec profondeur reelle)
- Personnages 3D dans un monde 2D (style Octopath Traveler)
- Effets de particules 3D dans un contexte 2D
- Props 3D avec eclairage 2D

---

## 8. Tilemap Optimization

Les Tilemaps peuvent devenir couteuses si mal configurees. Voici les optimisations cles.

### Chunk Mode

Par defaut, le Tilemap utilise le **Chunk Mode** qui regroupe les tiles en blocs pour le rendu. Verifier dans le TilemapRenderer :
- **Mode** = Chunk (par defaut, optimal)
- **Detect Chunk Culling Bounds** = Auto
- **Chunk Culling** elimine automatiquement les tiles hors ecran

### Composite Collider 2D

Pour les collisions, **toujours** utiliser un Composite Collider 2D :
1. Ajouter **Tilemap Collider 2D** sur le Tilemap
2. Cocher **Used by Composite**
3. Ajouter **Composite Collider 2D** + **Rigidbody2D** (Body Type = Static)
4. Geometry Type = **Polygons** (moins de vertices que Outlines)

Sans composite : chaque tile a son propre collider = performances catastrophiques.

### Separation en layers

Separer les Tilemaps par fonction :
- **Visuel uniquement** (decoration) : pas de collider
- **Collision** : Tilemap Collider 2D + Composite
- **Triggers** (zones de damage, checkpoints) : colliders en trigger

Cela evite de calculer des collisions sur des tiles purement visuelles.

### Tilemap grandes dimensions

Pour des maps tres grandes (> 500x500 tiles) :
- Charger par sections avec Addressables (`/addressables`)
- Utiliser `Tilemap.SetTilesBlock` pour le chargement par batch (plus rapide que `SetTile` en boucle)
- Desactiver les TilemapRenderers des sections hors ecran
- Considerer un systeme de chunks custom pour le streaming
