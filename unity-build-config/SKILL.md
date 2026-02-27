---
name: "Unity Build & CI/CD Configurator"
description: "Configure le pipeline de build Unity, CI/CD, et deployment. Triggers: /build-config, /ci, /deploy, 'configurer build', 'github actions unity', 'gitlab ci unity', 'gitignore unity', 'build automation'. Scanne le projet, genere les scripts de build C#, les workflows CI/CD, et les fichiers Git optimises."
---

# Unity Build & CI/CD Configurator

## Ce que fait cette skill

Configure l'ensemble du pipeline de build Unity : scripts de build C# automatises, workflows CI/CD (GitHub Actions ou GitLab CI), fichiers `.gitignore` et `.gitattributes` optimises avec Git LFS, et checklist pre-release par plateforme. Scanne le projet existant pour adapter la configuration.

## Prerequis

- Un projet Unity existant avec `ProjectSettings/` et `Assets/`
- Un repository Git (ou pret a etre initialise)
- Pour CI/CD : une licence Unity (Personal, Plus, Pro) stockee en secret

## Demarrage rapide

1. L'utilisateur demande une configuration de build (ex: "configure CI/CD pour Windows et WebGL")
2. Le skill scanne le projet (scenes, packages, settings)
3. Le skill genere les fichiers de configuration adaptes

## Guide etape par etape

### Etape 1 : Identifier les plateformes cibles

Si l'utilisateur ne precise pas, demander les plateformes parmi :
- **Desktop** : StandaloneWindows64, StandaloneOSX, StandaloneLinux64
- **Mobile** : Android, iOS
- **Web** : WebGL
- **Console** : PS5, XboxSeriesX, Switch (necessite SDK proprietaire)

### Etape 2 : Scanner le projet existant

Collecter les informations du projet avec les outils Claude Code :

```
Glob "Assets/**/*.unity"               → lister les scenes
Glob "ProjectSettings/*"               → verifier les settings existants
Read "Packages/manifest.json"          → packages et version Unity
Read "ProjectSettings/ProjectSettings.asset" → scripting backend, company name
Grep "com.unity.render-pipelines"      → pipeline de rendu
Glob ".gitignore"                      → verifier si existant
Glob ".gitattributes"                  → verifier si LFS configure
```

### Build Profiles (Unity 6+)

Unity 6 remplace les Build Settings traditionnels par des **Build Profiles**, des assets configurables par plateforme.

**Avantages des Build Profiles :**
- Plusieurs configurations independantes par plateforme (ex: Debug iOS, Release iOS, Demo Android)
- Switchable sans reconfigurer manuellement les Build Settings
- Scriptable et versionnable dans Git

**Setup :**
1. `File > Build Profiles` (remplace `File > Build Settings`)
2. Creer un profil par configuration : `New Build Profile`
3. Configurer par profil : scenes, scripting defines, compression, development build
4. Activer un profil : double-click ou API

**Impact sur les scripts de build C# :**
```csharp
// Avant (Build Settings classiques)
BuildPipeline.BuildPlayer(scenes, outputPath, BuildTarget.Android, BuildOptions.None);

// Apres (Build Profiles Unity 6+)
// Les Build Profiles sont des assets .buildprofile
// En CLI, utiliser -activeBuildProfile au lieu de -buildTarget
```

**Impact CI/CD :**
```bash
# Avant
unity-editor -buildTarget Android -executeMethod Build.Perform

# Apres (Unity 6+)
unity-editor -activeBuildProfile "Assets/Settings/BuildProfiles/Android_Release.buildprofile" -executeMethod Build.Perform
```

**Coexistence :** Les Build Profiles n'empechent pas l'usage de `BuildPipeline.BuildPlayer()` classique, mais il est recommande de migrer pour les nouveaux projets.

### Etape 3 : Generer le script de build C#

Creer `Assets/Editor/BuildAutomation.cs` :

```csharp
using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

public static class BuildAutomation
{
    private static string[] GetEnabledScenes() =>
        EditorBuildSettings.scenes.Where(s => s.enabled).Select(s => s.path).ToArray();

    private static void ExecuteBuild(BuildTarget target, string path, BuildOptions opts = BuildOptions.None)
    {
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        var report = BuildPipeline.BuildPlayer(GetEnabledScenes(), path, target, opts);
        Debug.Log($"Build {target}: {report.summary.result} ({report.summary.totalSize / (1024*1024)} MB)");
        if (report.summary.result != BuildResult.Succeeded)
            throw new Exception($"Build failed: {report.summary.totalErrors} error(s)");
    }

    [MenuItem("Build/Windows x64")]
    public static void BuildWindows() => ExecuteBuild(BuildTarget.StandaloneWindows64, "Builds/Windows/Game.exe");

    [MenuItem("Build/macOS")]
    public static void BuildMacOS() => ExecuteBuild(BuildTarget.StandaloneOSX, "Builds/macOS/Game.app");

    [MenuItem("Build/Linux x64")]
    public static void BuildLinux() => ExecuteBuild(BuildTarget.StandaloneLinux64, "Builds/Linux/Game.x86_64");

    [MenuItem("Build/WebGL")]
    public static void BuildWebGL()
    {
        PlayerSettings.WebGL.compressionFormat = WebGLCompressionFormat.Brotli;
        ExecuteBuild(BuildTarget.WebGL, "Builds/WebGL");
    }

    [MenuItem("Build/Android")]
    public static void BuildAndroid()
    {
        PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
        PlayerSettings.SetScriptingBackend(BuildTargetGroup.Android, ScriptingBackend.IL2CPP);
        ExecuteBuild(BuildTarget.Android, "Builds/Android/Game.apk");
    }

    [MenuItem("Build/iOS")]
    public static void BuildiOS()
    {
        PlayerSettings.SetScriptingBackend(BuildTargetGroup.iOS, ScriptingBackend.IL2CPP);
        ExecuteBuild(BuildTarget.iOS, "Builds/iOS");
    }

    // Entrypoint pour CI (ligne de commande)
    public static void BuildFromCommandLine()
    {
        var args = Environment.GetCommandLineArgs();
        string target = "StandaloneWindows64";
        for (int i = 0; i < args.Length; i++)
            if (args[i] == "-buildTarget" && i + 1 < args.Length) target = args[i + 1];
        var method = typeof(BuildAutomation).GetMethod($"Build{target.Replace("Standalone", "")}");
        if (method == null) throw new Exception($"Unknown target: {target}");
        method.Invoke(null, null);
    }
}
```

Adapter ce template selon les plateformes identifiees a l'etape 1. Supprimer les methodes non necessaires.

### Etape 4 : Generer la configuration CI/CD

**Option A : GitHub Actions** (recommande, utilise game-ci)

Creer `.github/workflows/unity-build.yml` :

```yaml
name: Unity Build & Test
on:
  push: { branches: [main, develop] }
  pull_request: { branches: [main] }
env:
  UNITY_LICENSE: ${{ secrets.UNITY_LICENSE }}
  UNITY_EMAIL: ${{ secrets.UNITY_EMAIL }}
  UNITY_PASSWORD: ${{ secrets.UNITY_PASSWORD }}
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - uses: actions/cache@v4
        with:
          path: Library
          key: Library-Test-${{ hashFiles('Assets/**', 'Packages/**', 'ProjectSettings/**') }}
      - uses: game-ci/unity-test-runner@v4
        with: { testMode: EditMode, githubToken: "${{ secrets.GITHUB_TOKEN }}" }
      - uses: game-ci/unity-test-runner@v4
        with: { testMode: PlayMode, githubToken: "${{ secrets.GITHUB_TOKEN }}" }
  build:
    needs: test
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        targetPlatform: [StandaloneWindows64, StandaloneOSX, WebGL]
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - uses: actions/cache@v4
        with:
          path: Library
          key: Library-${{ matrix.targetPlatform }}-${{ hashFiles('Assets/**', 'Packages/**', 'ProjectSettings/**') }}
      - uses: game-ci/unity-builder@v4
        with: { targetPlatform: "${{ matrix.targetPlatform }}" }
      - uses: actions/upload-artifact@v4
        with:
          name: Build-${{ matrix.targetPlatform }}
          path: build/${{ matrix.targetPlatform }}
          retention-days: 14
```

**Note Unity 6+** : Adapter les workflows CI/CD pour utiliser `-activeBuildProfile` au lieu de `-buildTarget` si le projet utilise les Build Profiles.

**Option B : GitLab CI**

Creer `.gitlab-ci.yml` :

```yaml
stages: [test, build]
variables:
  UNITY_VERSION: "6000.0"
.unity_base: &unity_base
  image: unityci/editor:ubuntu-${UNITY_VERSION}-base-3
  before_script:
    - unity-editor -quit -batchmode -nographics -manualLicenseFile "$UNITY_LICENSE_FILE" || true

test:
  <<: *unity_base
  stage: test
  script:
    - unity-editor -runTests -testPlatform EditMode -testResults results.xml -batchmode -nographics
  artifacts:
    reports: { junit: results.xml }
    when: always

build:windows:
  <<: *unity_base
  stage: build
  needs: [test]
  script:
    - unity-editor -executeMethod BuildAutomation.BuildWindows -quit -batchmode -nographics
  artifacts:
    paths: [Builds/Windows/]
    expire_in: 7 days
```

Dupliquer le job `build:` pour chaque plateforme cible en changeant la methode et le path.

### Etape 5 : Generer .gitignore et .gitattributes

**.gitignore** optimise Unity (adapter selon les besoins) :

```
/[Ll]ibrary/
/[Tt]emp/
/[Oo]bj/
/[Bb]uild/
/[Bb]uilds/
/[Ll]ogs/
/[Uu]ser[Ss]ettings/
/[Mm]emoryCaptures/
/[Rr]ecordings/
*.csproj
*.sln
*.suo
*.tmp
*.user
*.userprefs
*.pidb
*.booproj
*.svd
*.pdb
*.mdb
*.opendb
*.VC.db
.vs/
.idea/
.DS_Store
Thumbs.db
*.apk
*.aab
*.ipa
crashlytics-buildid.txt
sysinfo.txt
*.keystore
!debug.keystore
```

**.gitattributes** avec LFS (une ligne par type de fichier binaire) :

```
# Unity YAML merge
*.unity merge=unityyamlmerge
*.prefab merge=unityyamlmerge
*.asset merge=unityyamlmerge

# Git LFS - Modeles 3D
*.fbx filter=lfs diff=lfs merge=lfs -text
*.FBX filter=lfs diff=lfs merge=lfs -text
*.obj filter=lfs diff=lfs merge=lfs -text
*.blend filter=lfs diff=lfs merge=lfs -text
# Git LFS - Textures
*.png filter=lfs diff=lfs merge=lfs -text
*.jpg filter=lfs diff=lfs merge=lfs -text
*.psd filter=lfs diff=lfs merge=lfs -text
*.tga filter=lfs diff=lfs merge=lfs -text
*.tif filter=lfs diff=lfs merge=lfs -text
*.exr filter=lfs diff=lfs merge=lfs -text
*.hdr filter=lfs diff=lfs merge=lfs -text
# Git LFS - Audio/Video
*.wav filter=lfs diff=lfs merge=lfs -text
*.mp3 filter=lfs diff=lfs merge=lfs -text
*.ogg filter=lfs diff=lfs merge=lfs -text
*.mp4 filter=lfs diff=lfs merge=lfs -text
# Git LFS - Misc
*.unitypackage filter=lfs diff=lfs merge=lfs -text
*.dll filter=lfs diff=lfs merge=lfs -text
```

### Etape 6 : Pre-build checks

Ajouter cette methode dans `BuildAutomation.cs` pour valider avant chaque build :

```csharp
[MenuItem("Build/Pre-Build Check")]
public static void PreBuildCheck()
{
    var scenes = GetEnabledScenes();
    if (scenes.Length == 0) throw new Exception("No scenes in Build Settings!");
    if (EditorUtility.scriptCompilationFailed) throw new Exception("Compilation errors!");
    Debug.Log($"Pre-build OK: {scenes.Length} scene(s).");
}
```

Verifier aussi : pas de references manquantes dans les prefabs, tests EditMode passent.

## Checklist pre-release par plateforme

**Toutes plateformes** : 0 erreurs compilation, tests passent, scenes correctes dans Build Settings, pas de refs manquantes, version number a jour, icones/splash configures.

**Android** : Min API 24+, keystore securise (pas dans le repo), IL2CPP, ARM64, permissions AndroidManifest.

**iOS** : Signing Team ID, provisioning profile, min iOS 15+, descriptions permissions dans Info.plist, IL2CPP obligatoire.

**WebGL** : Compression Brotli (prod) ou Gzip, memory size 256-512 MB, exceptions = Explicitly Thrown, test multi-navigateurs.

**Desktop (Win/Mac/Linux)** : IL2CPP pour release, architecture x64, code signing (macOS notarization si distribution).

## Regles strictes

- **TOUJOURS** scanner le projet existant avant de generer des configs
- **TOUJOURS** utiliser IL2CPP pour les builds release (pas Mono)
- **TOUJOURS** configurer Git LFS avant le premier commit d'assets binaires
- **TOUJOURS** mettre les secrets (licence Unity, keystore) dans les variables CI, jamais dans les fichiers
- **TOUJOURS** inclure un job de tests avant le job de build dans le CI
- **JAMAIS** hardcoder de licence Unity ou credentials dans les fichiers CI
- **JAMAIS** inclure `Library/`, `Temp/`, ou `obj/` dans le version control
- **JAMAIS** committer de fichiers `.keystore` (sauf `debug.keystore`)
- **PREFERER** GitHub Actions avec game-ci comme solution CI par defaut
- **PREFERER** le cache du dossier `Library/` pour accelerer les builds CI

## Skills connexes

- Le script BuildAutomation necessite un editor tool plus avance ? Utiliser `/unity-editor-tools` (Unity Editor Tools)
- Generer un script de build custom ? Utiliser `/unity-code-gen` (Unity Code Gen) pour le code C# Editor

## Troubleshooting

| Probleme | Solution |
|----------|----------|
| Build CI echoue "No valid Unity license" | Configurer `UNITY_LICENSE` en secret. Generer via `unity-editor -createManualActivationFile` puis activer sur license.unity3d.com |
| Cache Library/ invalide | Changer la cle de cache ou la supprimer. Le cache depend de la version Unity |
| Build tres lent en CI | Activer le cache Library/, utiliser `il2CppCodeGeneration: OptimizeSize` pour les builds CI non-release |
| Erreur LFS "smudge filter" | Verifier que Git LFS est installe sur le runner CI (`git lfs install`) |
| WebGL build out of memory | Augmenter `PlayerSettings.WebGL.memorySize`, reduire les assets, activer le streaming |
| Android keystore introuvable | Utiliser un path relatif au projet ou une variable d'environnement pour le chemin du keystore |
| iOS signing echoue en CI | Utiliser `fastlane match` ou configurer les certificats via le Keychain du runner macOS |
| Scenes manquantes dans le build | Verifier `EditorBuildSettings.scenes` dans le script ou ajouter les scenes manuellement via le menu Build Settings |
