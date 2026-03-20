# Audio Avance : Mixer, Spatial & Random Container

Patterns avances pour AudioMixer snapshots, spatialisation 3D et Audio Random Container (Unity 6+).

---

## 1. AudioMixer Snapshots

Transitions entre ambiances sonores via snapshots :

```csharp
using UnityEngine;
using UnityEngine.Audio;

[CreateAssetMenu(fileName = "AudioMoodConfig", menuName = "Audio/Mood Config")]
public class AudioMoodConfigSO : ScriptableObject
{
    [System.Serializable]
    public struct MoodEntry
    {
        public string name;
        public AudioMixerSnapshot snapshot;
        public float transitionTime;
    }

    [SerializeField] private MoodEntry[] moods;

    public void TransitionTo(string moodName)
    {
        foreach (var mood in moods)
        {
            if (mood.name == moodName)
            {
                mood.snapshot.TransitionTo(mood.transitionTime);
                return;
            }
        }
        Debug.LogWarning($"Mood '{moodName}' not found in {name}");
    }
}
```

**Configuration des snapshots dans l'AudioMixer :**

| Snapshot | SFX | Music | Ambiance | Notes |
|----------|-----|-------|----------|-------|
| Normal | 0 dB | -6 dB | -10 dB | Gameplay standard |
| Combat | 0 dB | -12 dB | -20 dB | SFX prioritaires |
| Underwater | -3 dB | -15 dB | 0 dB | Low-pass sur Master |
| Pause | -80 dB | -6 dB | -80 dB | Musique seule |
| Cutscene | -80 dB | 0 dB | -6 dB | Dialogues + musique |

```csharp
// Usage
[SerializeField] private AudioMoodConfigSO moodConfig;

public void EnterCombat() => moodConfig.TransitionTo("Combat");
public void ExitCombat() => moodConfig.TransitionTo("Normal");
public void PauseGame() => moodConfig.TransitionTo("Pause");
```

---

## 2. Spatial Audio 3D Setup

Configuration d'un AudioSource pour le son 3D :

```csharp
using UnityEngine;

public static class AudioSpatialSetup
{
    public static void Configure3D(
        AudioSource source,
        float minDistance = 1f,
        float maxDistance = 50f,
        float dopplerLevel = 0.5f,
        AudioRolloffMode rolloff = AudioRolloffMode.Logarithmic)
    {
        source.spatialBlend = 1f;
        source.minDistance = minDistance;
        source.maxDistance = maxDistance;
        source.dopplerLevel = dopplerLevel;
        source.rolloffMode = rolloff;
        source.spread = 0f;
    }

    public static void ApplyPreset(AudioSource source, SpatialPreset preset)
    {
        switch (preset)
        {
            case SpatialPreset.Footstep:
                Configure3D(source, minDistance: 1f, maxDistance: 15f, dopplerLevel: 0f);
                break;
            case SpatialPreset.Gunshot:
                Configure3D(source, minDistance: 5f, maxDistance: 100f, dopplerLevel: 0.3f);
                break;
            case SpatialPreset.Explosion:
                Configure3D(source, minDistance: 10f, maxDistance: 200f, dopplerLevel: 0f);
                source.spread = 60f;
                break;
            case SpatialPreset.Voice:
                Configure3D(source, minDistance: 1f, maxDistance: 20f, dopplerLevel: 0f);
                break;
            case SpatialPreset.Ambiance:
                Configure3D(source, minDistance: 5f, maxDistance: 30f, dopplerLevel: 0f);
                source.spread = 180f;
                break;
        }
    }
}

public enum SpatialPreset
{
    Footstep, Gunshot, Explosion, Voice, Ambiance
}
```

---

## 3. Audio Random Container (Unity 6.0+)

Le **Audio Random Container** est un asset natif Unity 6+ qui remplace les scripts de randomisation manuelle. Configuration via l'Inspector uniquement (pas de code necessaire).

### Creation

1. **Project** > clic droit > **Create > Audio > Audio Random Container**
2. Glisser les clips variants dans la liste (ex: 5 variantes de footstep)
3. Configurer :
   - **Trigger Mode** : `On Play` (lance un clip au hasard) ou `Automatic` (enchaine)
   - **Avoid Repeating Last** : nombre de clips a eviter en repetition (ex: 2)
   - **Volume / Pitch Randomization** : plage min/max
   - **Output** : assigner le AudioMixerGroup cible

### Usage en code

```csharp
[SerializeField] private AudioResource footstepContainer;
private AudioSource source;

private void PlayFootstep()
{
    source.resource = footstepContainer;
    source.Play();
}
```

### Quand utiliser

| Situation | Solution |
|-----------|----------|
| Footsteps avec 3-8 variantes | Audio Random Container |
| Impacts avec pitch variable | Audio Random Container |
| SFX unique sans variation | AudioCueSO classique |
| Logique conditionnelle complexe | Code custom (AudioCueSO) |
