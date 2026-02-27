# UI Toolkit — Catalogue des Controls

Reference des controls UI Toolkit (Unity 6+), attributs UXML et usage typique.

## Layout

**VisualElement** — Conteneur de base (equivalent `<div>`).
```xml
<ui:VisualElement name="container" class="row" />
```

**ScrollView** — Conteneur scrollable. Modes: Vertical, Horizontal, VerticalAndHorizontal.
```xml
<ui:ScrollView mode="Vertical" name="scroll" class="scroll-area" />
```

**Foldout** — Section repliable avec header cliquable.
```xml
<ui:Foldout text="Advanced Settings" value="true">
    <ui:Toggle label="Enable VSync" />
</ui:Foldout>
```

**GroupBox** — Conteneur semantique, utile pour grouper des RadioButtons.
```xml
<ui:GroupBox text="Difficulty">
    <ui:RadioButton label="Easy" value="true" />
    <ui:RadioButton label="Hard" />
</ui:GroupBox>
```

**TabView** (Unity 6+) — Navigation par onglets.
```xml
<ui:TabView>
    <ui:Tab label="General"><!-- contenu --></ui:Tab>
    <ui:Tab label="Audio"><!-- contenu --></ui:Tab>
</ui:TabView>
```

## Texte

**Label** — Texte statique ou binde. Supporte le rich text (`<b>`, `<i>`, `<color>`).
```xml
<ui:Label name="score" text="Score: 0" class="score-text" />
```

**TextField** — Saisie texte (single-line, multi-line, password).
```xml
<ui:TextField name="username" label="Username" max-length="20" />
<ui:TextField name="password" label="Password" password="true" />
<ui:TextField name="bio" multiline="true" />
```

**IntegerField / FloatField / LongField / DoubleField** — Champs numeriques types.
```xml
<ui:IntegerField name="health" label="Health" value="100" />
<ui:FloatField name="speed" label="Speed" value="5.5" />
```

**Vector2Field / Vector3Field / Vector4Field** — Champs vectoriels (surtout Editor UI).

## Actions

**Button** — Bouton cliquable. Evenement `clicked` en C#.
```xml
<ui:Button name="btn-start" text="Start Game" class="primary-button" />
```
```csharp
root.Q<Button>("btn-start").clicked += () => Debug.Log("Clicked!");
```

**Toggle** — Case a cocher booleenne.
```xml
<ui:Toggle name="toggle-music" label="Music" value="true" />
```
```csharp
root.Q<Toggle>("toggle-music").RegisterValueChangedCallback(evt =>
    AudioManager.SetMusic(evt.newValue));
```

**RadioButtonGroup** — Selection exclusive.
```xml
<ui:RadioButtonGroup label="Quality" value="1">
    <ui:RadioButton label="Low" />
    <ui:RadioButton label="Medium" />
    <ui:RadioButton label="High" />
</ui:RadioButtonGroup>
```

**ToggleButtonGroup** (Unity 6+) — Boutons toggle exclusifs (aspect bouton, pas checkbox).

## Selection

**DropdownField** — Menu deroulant.
```xml
<ui:DropdownField name="resolution" label="Resolution"
    choices="1920x1080,1280x720,640x480" value="1920x1080" />
```
```csharp
var dropdown = root.Q<DropdownField>("resolution");
dropdown.choices = new List<string> { "1920x1080", "1280x720" };
dropdown.RegisterValueChangedCallback(evt => SetResolution(evt.newValue));
```

**EnumField** — Dropdown automatique depuis un enum C#.
```csharp
var enumField = new EnumField("Quality", QualityLevel.Medium);
root.Add(enumField);
```

## Collections

**ListView** — Liste virtualisee performante (inventaire, leaderboard).
```xml
<ui:ListView name="inventory" fixed-item-height="40" />
```
```csharp
var listView = root.Q<ListView>("inventory");
listView.itemsSource = items;
listView.makeItem = () => new Label();
listView.bindItem = (element, index) => (element as Label).text = items[index].Name;
listView.fixedItemHeight = 40;
```

**TreeView** — Arborescence repliable (file browser, scene tree).

**MultiColumnListView / MultiColumnTreeView** (Unity 6+) — Tableaux avec colonnes triables.

## Valeurs

**Slider / SliderInt** — Curseur continu ou entier.
```xml
<ui:Slider name="volume" label="Volume" low-value="0" high-value="1"
    value="0.8" show-input-field="true" />
<ui:SliderInt name="fov" label="FOV" low-value="60" high-value="120" value="90" />
```

**MinMaxSlider** — Curseur double (plage de valeurs).
```xml
<ui:MinMaxSlider name="range" label="Spawn Range"
    low-limit="0" high-limit="100" min-value="20" max-value="80" />
```

**ProgressBar** — Barre de progression (lecture seule).
```xml
<ui:ProgressBar name="loading" title="Loading..." low-value="0" high-value="100" />
```

## Custom Controls (Unity 6+)

`[UxmlElement]` + `[UxmlAttribute]` remplace l'ancien UxmlFactory/UxmlTraits.

```csharp
[UxmlElement]
public partial class HealthBar : VisualElement
{
    [UxmlAttribute]
    public float Value
    {
        get => _value;
        set { _value = Mathf.Clamp01(value); UpdateFill(); }
    }
    private float _value = 1f;

    [UxmlAttribute]
    public Color BarColor { get; set; } = Color.green;

    private readonly VisualElement _fill;

    public HealthBar()
    {
        var bg = new VisualElement();
        bg.style.flexGrow = 1;
        bg.style.backgroundColor = new Color(0.2f, 0.2f, 0.2f);
        bg.style.borderTopLeftRadius = bg.style.borderTopRightRadius = 4;
        bg.style.borderBottomLeftRadius = bg.style.borderBottomRightRadius = 4;
        bg.style.overflow = Overflow.Hidden;
        _fill = new VisualElement();
        _fill.style.height = Length.Percent(100);
        _fill.style.backgroundColor = BarColor;
        bg.Add(_fill);
        Add(bg);
        UpdateFill();
    }

    private void UpdateFill() => _fill?.style.SetWidth(Length.Percent(_value * 100f));
}
```
```xml
<HealthBar name="player-hp" value="0.75" bar-color="green" style="height: 20px;" />
```

## Proprietes USS — Reference rapide

### Flexbox
| Propriete | Valeurs courantes |
|-----------|-------------------|
| `flex-direction` | row, column, row-reverse, column-reverse |
| `flex-grow` / `flex-shrink` | 0, 1, ... |
| `flex-wrap` | nowrap, wrap, wrap-reverse |
| `justify-content` | flex-start, center, flex-end, space-between, space-around |
| `align-items` / `align-self` | flex-start, center, flex-end, stretch |

### Spacing / Sizing
`margin`, `padding`, `width`, `height`, `min-width`, `max-width`, `border-width`, `border-radius`, `border-color`

### Texte
| Propriete | Exemple |
|-----------|---------|
| `font-size` | 16px |
| `color` | rgb(230, 230, 240) |
| `-unity-font-style` | bold, italic, bold-and-italic |
| `-unity-text-align` | middle-center, upper-left |
| `white-space` | normal, nowrap |
| `text-overflow` | clip, ellipsis |

### Visuels
`background-color`, `background-image`, `-unity-background-scale-mode` (scale-to-fit, stretch-to-fill), `opacity`, `overflow`

### Transitions et Pseudo-classes
```css
.card {
    transition: scale 0.2s ease-in-out, background-color 0.2s;
}
.card:hover { scale: 1.03; background-color: rgb(50, 50, 70); }
.card:active { scale: 0.98; }
.toggle:checked { background-color: rgb(50, 120, 220); }
.input:focus { border-color: rgb(80, 140, 240); border-width: 2px; }
.button:disabled { opacity: 0.5; }
```

Pseudo-classes : `:hover`, `:active`, `:focus`, `:checked`, `:disabled`, `:enabled`, `:root`.
