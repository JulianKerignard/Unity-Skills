# Build Templates & CI/CD Configurations

Reference des templates de code pour la skill Unity Build & CI/CD Configurator.

## Build Profiles (Unity 6+)

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

## BuildAutomation.cs

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

Adapter ce template selon les plateformes identifiees. Supprimer les methodes non necessaires.

## GitHub Actions (Option A)

Creer `.github/workflows/unity-build.yml` (utilise game-ci) :

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

## GitLab CI (Option B)

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

## .gitignore Unity

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

## .gitattributes avec LFS

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

## Pre-build Checks

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
