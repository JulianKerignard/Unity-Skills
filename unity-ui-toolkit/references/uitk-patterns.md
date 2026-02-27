# UI Toolkit — Patterns et Architectures

Patterns reutilisables pour structurer des interfaces UI Toolkit robustes.

## Data Binding Runtime (Unity 6+)

Le data binding natif connecte les proprietes C# directement aux elements UXML.

### ViewModel

```csharp
public class PlayerStatsViewModel : MonoBehaviour, INotifyBindablePropertyChanged
{
    public event EventHandler<BindablePropertyChangedEventArgs> propertyChanged;

    [CreateProperty]
    public int Health
    {
        get => _health;
        set { _health = value; Notify(); }
    }
    private int _health = 100;

    [CreateProperty]
    public string PlayerName
    {
        get => _playerName;
        set { _playerName = value; Notify(); }
    }
    private string _playerName = "Player";

    private void Notify([CallerMemberName] string property = "")
        => propertyChanged?.Invoke(this, new BindablePropertyChangedEventArgs(property));
}
```

### UXML : `<ui:Label binding-path="Health" />` — lie automatiquement la propriete.

### Connexion : `root.dataSource = viewModel;` dans le presenter.

## Navigation Stack Pattern

Push/pop d'ecrans, similaire a un navigation controller mobile.

```csharp
public class ScreenNavigator : MonoBehaviour
{
    [SerializeField] private UIDocument document;
    private readonly Stack<VisualElement> _screenStack = new();
    private VisualElement _root;

    private void Awake() => _root = document.rootVisualElement;

    public void PushScreen(VisualTreeAsset screenAsset)
    {
        if (_screenStack.TryPeek(out var current))
            current.style.display = DisplayStyle.None;
        var screen = screenAsset.Instantiate();
        screen.style.flexGrow = 1;
        _root.Add(screen);
        _screenStack.Push(screen);
    }

    public void PopScreen()
    {
        if (_screenStack.Count <= 1) return;
        var screen = _screenStack.Pop();
        screen.RemoveFromHierarchy();
        if (_screenStack.TryPeek(out var previous))
            previous.style.display = DisplayStyle.Flex;
    }

    public void PopToRoot()
    {
        while (_screenStack.Count > 1)
        {
            var screen = _screenStack.Pop();
            screen.RemoveFromHierarchy();
        }
        if (_screenStack.TryPeek(out var root))
            root.style.display = DisplayStyle.Flex;
    }
}
```

## Theming avec USS Variables

### Variables.uss

```css
:root {
    --color-primary: rgb(50, 120, 220);
    --color-bg: rgb(30, 30, 40);
    --color-bg-panel: rgb(40, 40, 55);
    --color-text: rgb(230, 230, 240);
    --color-text-muted: rgb(140, 140, 160);
    --font-size-body: 16px;
    --font-size-title: 48px;
    --spacing-sm: 4px;
    --spacing-md: 8px;
    --spacing-lg: 16px;
    --radius-sm: 4px;
    --radius-md: 8px;
}
.button-primary {
    background-color: var(--color-primary);
    color: var(--color-text);
    font-size: var(--font-size-body);
}
```

### Changer de theme : swap le StyleSheet sur `root.styleSheets` via C#.

```csharp
root.styleSheets.Clear();
root.styleSheets.Add(isDark ? darkTheme : lightTheme);
```

## Responsive Layout

### Wrap Layout (grille adaptative)

```css
.grid-container {
    flex-direction: row;
    flex-wrap: wrap;
    justify-content: flex-start;
}
.grid-item {
    width: 150px;
    min-width: 120px;
    max-width: 200px;
    flex-grow: 1;
    margin: 4px;
    height: 180px;
}
```

### Pseudo-media-queries via C#

Ecouter `GeometryChangedEvent`, lire `root.resolvedStyle.width`, puis toggle des classes :

```csharp
root.EnableInClassList("layout-mobile", width < 800);
root.EnableInClassList("layout-desktop", width >= 800);
```
```css
.layout-desktop .sidebar { display: flex; width: 250px; }
.layout-mobile .sidebar { display: none; }
```

## World-Space UI

### Billboard (face camera)

```csharp
public class WorldSpaceUI : MonoBehaviour
{
    [SerializeField] private Camera mainCamera;

    private void LateUpdate()
    {
        if (mainCamera != null)
            transform.rotation = Quaternion.LookRotation(
                transform.position - mainCamera.transform.position);
    }
}
```

Pour beaucoup d'entites, preferer l'approche RenderTexture : PanelSettings pointe
vers une RT, et un MeshRenderer affiche cette RT sur un quad.

## Modal / Popup Pattern

```csharp
public static class ModalHelper
{
    public static VisualElement ShowModal(VisualElement parent, VisualTreeAsset content)
    {
        var overlay = new VisualElement();
        overlay.style.position = Position.Absolute;
        overlay.style.top = 0; overlay.style.bottom = 0;
        overlay.style.left = 0; overlay.style.right = 0;
        overlay.style.backgroundColor = new Color(0, 0, 0, 0.6f);
        overlay.style.justifyContent = Justify.Center;
        overlay.style.alignItems = Align.Center;
        overlay.Add(content.Instantiate());
        overlay.RegisterCallback<ClickEvent>(evt =>
        {
            if (evt.target == overlay) overlay.RemoveFromHierarchy();
        });
        parent.Add(overlay);
        return overlay;
    }
}
```

## ListView avec ItemTemplate

Creer un `.uxml` pour l'item, puis binder via `makeItem` / `bindItem` :

```csharp
var listView = root.Q<ListView>("inventory-list");
listView.itemsSource = _items;
listView.fixedItemHeight = 60;
listView.makeItem = () => itemTemplate.Instantiate();
listView.bindItem = (element, index) =>
{
    element.Q<Label>("item-name").text = _items[index].Name;
    element.Q<Label>("item-value").text = $"{_items[index].Value}g";
};
```

## Animation Patterns

### Transitions USS (prefere pour les effets simples)

```css
.card {
    transition: translate 0.3s ease-out, opacity 0.3s ease-out;
    translate: 0 0;
    opacity: 1;
}
.card.slide-out { translate: -100% 0; opacity: 0; }
.card.slide-in-right { translate: 100% 0; opacity: 0; }
```

### Animation procedurale C# (pour effets complexes)

```csharp
public static class UIAnimations
{
    public static void FadeIn(VisualElement el, float duration = 0.3f)
    {
        el.style.opacity = 0;
        el.style.display = DisplayStyle.Flex;
        el.style.transitionProperty = new List<StylePropertyName> { new("opacity") };
        el.style.transitionDuration = new List<TimeValue> { new(duration, TimeUnit.Second) };
        el.schedule.Execute(() => el.style.opacity = 1);
    }
}
```
