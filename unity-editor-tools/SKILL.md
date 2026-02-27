---
name: "Unity Editor Tools"
description: "Cree des outils custom pour l'editeur Unity : inspectors personnalises, fenetres d'outils, drawers, menu items, wizards et asset processors. Triggers: /unity-editor-tools, /editor, 'custom inspector', 'editor window', 'property drawer', 'menu item', 'editor tool', 'outil editeur'. Produit des scripts C# dans le dossier Editor avec assembly definition correcte."
---

# Unity Editor Tools

## Ce que fait cette skill

Cette skill genere des outils personnalises pour l'editeur Unity afin d'accelerer les workflows de developpement. Elle couvre tous les types d'extensions editor : CustomEditor, PropertyDrawer, EditorWindow, MenuItem, ScriptableWizard et AssetPostprocessor.

## Prerequis

- Projet Unity avec une structure `Assets/Scripts/` existante
- Connaissance du composant ou du workflow a outiller
- Pas de dependance MCP Unity : utilise uniquement Read, Write, Edit, Grep, Glob, Bash

## Demarrage rapide

1. Identifier le workflow a accelerer dans l'editeur
2. Choisir le type d'outil via l'arbre de decision
3. Verifier la structure assembly Editor
4. Generer le script avec le template adapte
5. Verifier visuellement dans Unity

## Guide etape par etape

### Etape 1 : Identifier le workflow a accelerer

Analyser le besoin utilisateur. Scanner les composants existants pour comprendre le contexte :

```
Glob : Assets/Scripts/**/*.cs
Grep : "class.*MonoBehaviour" dans les fichiers trouves
```

Poser les questions :
- Quel composant ou donnee doit etre plus facile a editer ?
- Quelle action repetitive doit etre automatisee ?
- Quel feedback visuel manque dans l'Inspector ?

### Etape 2 : Choisir le type d'outil

Arbre de decision :

| Besoin | Type | Classe de base |
|--------|------|----------------|
| Personnaliser l'affichage d'un composant dans l'Inspector | `CustomEditor` | `Editor` |
| Personnaliser le rendu d'un type de champ specifique | `PropertyDrawer` | `PropertyDrawer` |
| Creer une fenetre d'outil autonome | `EditorWindow` | `EditorWindow` |
| Ajouter une action rapide dans un menu | `MenuItem` | attribut statique |
| Creer un assistant etape par etape | `ScriptableWizard` | `ScriptableWizard` |
| Traiter les assets a l'import | `AssetPostprocessor` | `AssetPostprocessor` |

### Etape 3 : Verifier la structure assembly Editor

Avant de generer du code, verifier que l'infrastructure Editor existe :

```
1. Glob : Assets/**/Editor/*.asmdef OR Assets/**/Editor.asmdef
2. Si absent : creer le dossier Assets/Scripts/Editor/
3. Creer Game.Editor.asmdef avec reference a Game.Runtime
4. Verifier que le .asmdef cible uniquement la plateforme Editor
```

Structure du fichier `Game.Editor.asmdef` :

```json
{
    "name": "Game.Editor",
    "rootNamespace": "",
    "references": ["Game.Runtime"],
    "includePlatforms": ["Editor"],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": false
}
```

Si aucun `Game.Runtime.asmdef` n'existe, verifier avec Glob dans `Assets/Scripts/` et en creer un si necessaire.

### Etape 4 : Generer le script editor

Utiliser le template correspondant au type choisi a l'etape 2.

#### Template CustomEditor

```csharp
using UnityEditor;
using UnityEngine;

[CustomEditor(typeof(TargetComponent))]
public class TargetComponentEditor : Editor
{
    SerializedProperty _propName;
    bool _foldoutAdvanced;

    void OnEnable()
    {
        _propName = serializedObject.FindProperty("_fieldName");
    }

    public override void OnInspectorGUI()
    {
        serializedObject.Update();

        EditorGUILayout.LabelField("Section principale", EditorStyles.boldLabel);
        EditorGUILayout.PropertyField(_propName);

        EditorGUILayout.Space(8);
        _foldoutAdvanced = EditorGUILayout.Foldout(_foldoutAdvanced, "Avance", true);
        if (_foldoutAdvanced)
        {
            EditorGUI.indentLevel++;
            // Champs avances ici
            EditorGUI.indentLevel--;
        }

        if (GUILayout.Button("Action"))
        {
            var target = (TargetComponent)this.target;
            Undo.RecordObject(target, "Action sur TargetComponent");
            // Logique action
        }

        serializedObject.ApplyModifiedProperties();
    }
}
```

#### Template CustomEditor — UI Toolkit (Unity 6+)

Pour les inspectors complexes, preferer UI Toolkit a IMGUI. Le binding automatique via `SerializedObject` simplifie le code.

```csharp
using UnityEditor;
using UnityEditor.UIElements;
using UnityEngine;
using UnityEngine.UIElements;

[CustomEditor(typeof(TargetComponent))]
public class TargetComponentEditor : Editor
{
    [SerializeField] private VisualTreeAsset inspectorUXML;

    public override VisualElement CreateInspectorGUI()
    {
        var root = new VisualElement();

        // Option 1 : UXML externe (recommande pour les inspectors complexes)
        if (inspectorUXML != null)
        {
            inspectorUXML.CloneTree(root);
        }
        else
        {
            // Option 2 : Construction en code (pour les inspectors simples)
            root.Add(new Label("Section principale") { style = { unityFontStyleAndWeight = FontStyle.Bold } });
            root.Add(new PropertyField(serializedObject.FindProperty("_fieldName")));

            var foldout = new Foldout { text = "Avance", value = false };
            foldout.Add(new PropertyField(serializedObject.FindProperty("_advancedField")));
            root.Add(foldout);

            var actionButton = new Button(() =>
            {
                var target = (TargetComponent)this.target;
                Undo.RecordObject(target, "Action sur TargetComponent");
                // Logique action
            }) { text = "Action" };
            root.Add(actionButton);
        }

        // Le binding avec SerializedObject est automatique pour les PropertyField
        return root;
    }
}
```

Note : Avec `CreateInspectorGUI()`, les `PropertyField` se bindent automatiquement au `SerializedObject`. Pas besoin d'appeler `serializedObject.Update()` / `ApplyModifiedProperties()` manuellement — UI Toolkit le gere.

#### Template PropertyDrawer

```csharp
using UnityEditor;
using UnityEngine;

[CustomPropertyDrawer(typeof(TargetType))]
public class TargetTypeDrawer : PropertyDrawer
{
    public override void OnGUI(Rect position, SerializedProperty property, GUIContent label)
    {
        EditorGUI.BeginProperty(position, label, property);

        position = EditorGUI.PrefixLabel(position, label);
        var indent = EditorGUI.indentLevel;
        EditorGUI.indentLevel = 0;

        // Layout des sous-champs
        var halfWidth = position.width * 0.5f;
        var rectA = new Rect(position.x, position.y, halfWidth - 2, position.height);
        var rectB = new Rect(position.x + halfWidth, position.y, halfWidth, position.height);

        EditorGUI.PropertyField(rectA, property.FindPropertyRelative("fieldA"), GUIContent.none);
        EditorGUI.PropertyField(rectB, property.FindPropertyRelative("fieldB"), GUIContent.none);

        EditorGUI.indentLevel = indent;
        EditorGUI.EndProperty();
    }

    public override float GetPropertyHeight(SerializedProperty property, GUIContent label)
    {
        return EditorGUIUtility.singleLineHeight;
    }
}
```

#### Template EditorWindow (avec tabs et toolbar)

```csharp
using UnityEditor;
using UnityEngine;

public class MyToolWindow : EditorWindow
{
    [MenuItem("Tools/My Tool")]
    static void Open() => GetWindow<MyToolWindow>("My Tool");

    int _selectedTab;
    readonly string[] _tabs = { "General", "Config", "Debug" };
    Vector2 _scrollPos;

    void OnGUI()
    {
        // Toolbar
        EditorGUILayout.BeginHorizontal(EditorStyles.toolbar);
        if (GUILayout.Button("Refresh", EditorStyles.toolbarButton, GUILayout.Width(60)))
            Refresh();
        GUILayout.FlexibleSpace();
        EditorGUILayout.EndHorizontal();

        // Tabs
        _selectedTab = GUILayout.Toolbar(_selectedTab, _tabs);
        EditorGUILayout.Space(4);

        _scrollPos = EditorGUILayout.BeginScrollView(_scrollPos);
        switch (_selectedTab)
        {
            case 0: DrawGeneralTab(); break;
            case 1: DrawConfigTab(); break;
            case 2: DrawDebugTab(); break;
        }
        EditorGUILayout.EndScrollView();
    }

    void DrawGeneralTab() { EditorGUILayout.HelpBox("Contenu general.", MessageType.Info); }
    void DrawConfigTab() { /* Configuration */ }
    void DrawDebugTab() { /* Debug info */ }
    void Refresh() { Repaint(); }
}
```

#### Template MenuItem (avec validation)

```csharp
using UnityEditor;
using UnityEngine;

public static class MyMenuItems
{
    [MenuItem("Tools/Do Thing %#d")] // Ctrl+Shift+D
    static void DoThing()
    {
        var go = Selection.activeGameObject;
        Undo.RecordObject(go, "Do Thing");
        // Action ici
    }

    [MenuItem("Tools/Do Thing", true)]
    static bool ValidateDoThing() => Selection.activeGameObject != null;
}
```

### Etape 5 : Verification visuelle

Apres generation du script :

1. Verifier que le fichier est dans le bon dossier (`Assets/Scripts/Editor/` ou `Assets/Editor/`)
2. Verifier l'absence d'erreurs de compilation : chercher les dependances manquantes
3. S'assurer que le `using UnityEditor;` est present
4. Confirmer que le script ne reference aucun type Editor depuis un assembly Runtime

## Patterns IMGUI courants

```csharp
// Layout horizontal/vertical
EditorGUILayout.BeginHorizontal();
EditorGUILayout.EndHorizontal();

// PropertyField avec label custom
EditorGUILayout.PropertyField(prop, new GUIContent("Label", "Tooltip"));

// Foldout
foldout = EditorGUILayout.Foldout(foldout, "Section", true);

// Barre de progression
EditorGUI.ProgressBar(rect, value, "Loading...");

// ReorderableList (UnityEditorInternal)
var list = new ReorderableList(serializedObject, prop, true, true, true, true);
list.drawElementCallback = (rect, index, active, focused) => { };
list.DoLayoutList();
```

## Patterns UI Toolkit (UITK)

```csharp
// EditorWindow avec UI Toolkit
public void CreateGUI()
{
    var root = rootVisualElement;
    var tree = AssetDatabase.LoadAssetAtPath<VisualTreeAsset>("Assets/Editor/MyWindow.uxml");
    tree.CloneTree(root);
    root.styleSheets.Add(AssetDatabase.LoadAssetAtPath<StyleSheet>("Assets/Editor/MyWindow.uss"));

    // Binding SerializedObject
    root.Bind(serializedObject);
}
```

Pour les nouveaux projets (Unity 6+), preferer UI Toolkit a IMGUI pour les EditorWindow et les CustomEditor complexes. Pour les PropertyDrawer simples, IMGUI reste acceptable. Voir le template CustomEditor UI Toolkit ci-dessus pour un exemple complet.

## Regles strictes

- **TOUJOURS** placer les scripts editor dans `Assets/Scripts/Editor/` ou `Assets/Editor/`
- **TOUJOURS** utiliser un assembly definition `Game.Editor` avec `includePlatforms: ["Editor"]`
- **TOUJOURS** utiliser `serializedObject.Update()` et `ApplyModifiedProperties()` dans les CustomEditor
- **TOUJOURS** utiliser `Undo.RecordObject()` avant de modifier un objet via bouton
- **TOUJOURS** utiliser `EditorGUI.BeginProperty/EndProperty` dans les PropertyDrawer
- **JAMAIS** referencer du code Editor depuis un assembly Runtime
- **JAMAIS** utiliser `target` sans cast dans un CustomEditor (utiliser `(T)target` ou `serializedObject`)
- **JAMAIS** oublier le `GUIContent.none` quand on dessine des sous-champs dans un Drawer
- **JAMAIS** creer de fichier editor a la racine de `Assets/Scripts/`

## Skills connexes

- Generer le composant avant de creer son inspector ? Utiliser `/unity-code-gen` (Unity Code Gen)
- Creer une UI runtime (pas editor) ? Utiliser `/uitk` (Unity UI Toolkit)
- Tester les outils editor ? Utiliser `/unity-test` (Unity Test)

## Troubleshooting

| Probleme | Solution |
|----------|----------|
| `The type or namespace 'Editor' could not be found` | Le script n'est pas dans un dossier Editor ou l'assembly def manque `includePlatforms: ["Editor"]` |
| L'inspector custom ne s'affiche pas | Verifier que `typeof(TargetComponent)` correspond exactement au type cible et que le script compile |
| `NullReferenceException` dans `OnEnable` | Le nom de propriete dans `FindProperty()` ne correspond pas au champ `[SerializeField]` (sensible a la casse) |
| Le PropertyDrawer ne s'applique pas | Verifier que l'attribut `[CustomPropertyDrawer(typeof(T))]` cible le bon type, pas le champ |
| `Multiple editors` warning | Deux CustomEditor ciblent le meme type. Grep pour `CustomEditor(typeof(X))` dans tout le projet |
| Le MenuItem est grise | La methode `Validate` retourne `false`. Verifier les conditions de validation |
| Changements non annulables (Ctrl+Z) | Ajouter `Undo.RecordObject()` avant chaque modification directe |
