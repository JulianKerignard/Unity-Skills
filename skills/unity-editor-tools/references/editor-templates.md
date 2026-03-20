# Editor Tool Templates

## Template CustomEditor (IMGUI)

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

## Template CustomEditor — UI Toolkit (Unity 6+)

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

## Template PropertyDrawer

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

## Template EditorWindow (avec tabs et toolbar)

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

## Template MenuItem (avec validation)

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
