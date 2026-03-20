# Audio Patterns Unity 6+

Patterns d'implementation audio bases sur ScriptableObjects et le systeme event-driven.

---

## 1. AudioManager SO-based

### AudioCueSO : definition d'un son

```csharp
using UnityEngine;
using UnityEngine.Audio;

[CreateAssetMenu(fileName = "NewAudioCue", menuName = "Audio/Audio Cue")]
public class AudioCueSO : ScriptableObject
{
    [Header("Clips")]
    [SerializeField] private AudioClip[] clips;

    [Header("Settings")]
    [SerializeField, Range(0f, 1f)] private float volumeMin = 0.8f;
    [SerializeField, Range(0f, 1f)] private float volumeMax = 1f;
    [SerializeField, Range(0.8f, 1.2f)] private float pitchMin = 0.95f;
    [SerializeField, Range(0.8f, 1.2f)] private float pitchMax = 1.05f;

    [Header("Routing")]
    [SerializeField] private AudioMixerGroup outputGroup;

    public AudioClip GetRandomClip()
    {
        if (clips == null || clips.Length == 0) return null;
        return clips[Random.Range(0, clips.Length)];
    }

    public float GetRandomVolume() => Random.Range(volumeMin, volumeMax);
    public float GetRandomPitch() => Random.Range(pitchMin, pitchMax);
    public AudioMixerGroup OutputGroup => outputGroup;
}
```

### AudioCueEventChannelSO : canal d'evenement

```csharp
using UnityEngine;

[CreateAssetMenu(fileName = "AudioCueEventChannel", menuName = "Audio/Audio Cue Event Channel")]
public class AudioCueEventChannelSO : ScriptableObject
{
    public System.Action<AudioCueSO, Vector3> OnAudioCueRequested;

    public void RaiseEvent(AudioCueSO cue, Vector3 position = default)
    {
        OnAudioCueRequested?.Invoke(cue, position);
    }
}
```

### SoundEmitter : wrapper AudioSource poolable

```csharp
using System.Collections;
using UnityEngine;
using UnityEngine.Audio;

[RequireComponent(typeof(AudioSource))]
public class SoundEmitter : MonoBehaviour
{
    private AudioSource source;
    public bool IsPlaying => source.isPlaying;

    private void Awake()
    {
        source = GetComponent<AudioSource>();
        source.playOnAwake = false;
    }

    public void Play(AudioClip clip, float volume, float pitch, AudioMixerGroup group, bool loop = false)
    {
        source.clip = clip;
        source.volume = volume;
        source.pitch = pitch;
        source.outputAudioMixerGroup = group;
        source.loop = loop;
        source.Play();
    }

    public void PlayOneShot(AudioClip clip, float volume, float pitch, AudioMixerGroup group)
    {
        source.outputAudioMixerGroup = group;
        source.pitch = pitch;
        source.PlayOneShot(clip, volume);
    }

    public void Stop()
    {
        source.Stop();
        source.clip = null;
    }

    public void SetPosition(Vector3 position)
    {
        transform.position = position;
    }

    public void Configure3D(float spatialBlend, float minDistance, float maxDistance)
    {
        source.spatialBlend = spatialBlend;
        source.minDistance = minDistance;
        source.maxDistance = maxDistance;
        source.rolloffMode = AudioRolloffMode.Logarithmic;
    }
}
```

### AudioManager : orchestrateur avec pool

```csharp
using System.Collections.Generic;
using UnityEngine;

public class AudioManager : MonoBehaviour
{
    [Header("Config")]
    [SerializeField] private int poolSize = 16;
    [SerializeField] private SoundEmitter emitterPrefab;

    [Header("Event Channel")]
    [SerializeField] private AudioCueEventChannelSO sfxChannel;

    private readonly Queue<SoundEmitter> availableEmitters = new();
    private readonly List<SoundEmitter> activeEmitters = new();

    private void Awake()
    {
        InitPool();
    }

    private void OnEnable()
    {
        sfxChannel.OnAudioCueRequested += HandleAudioCueRequested;
    }

    private void OnDisable()
    {
        sfxChannel.OnAudioCueRequested -= HandleAudioCueRequested;
    }

    private void InitPool()
    {
        for (int i = 0; i < poolSize; i++)
        {
            SoundEmitter emitter = Instantiate(emitterPrefab, transform);
            emitter.gameObject.SetActive(false);
            availableEmitters.Enqueue(emitter);
        }
    }

    private void HandleAudioCueRequested(AudioCueSO cue, Vector3 position)
    {
        AudioClip clip = cue.GetRandomClip();
        if (clip == null) return;

        SoundEmitter emitter = GetEmitter();
        if (emitter == null) return;

        emitter.SetPosition(position);
        emitter.PlayOneShot(clip, cue.GetRandomVolume(), cue.GetRandomPitch(), cue.OutputGroup);
        StartCoroutine(ReturnAfterPlay(emitter, clip.length / emitter.GetComponent<AudioSource>().pitch));
    }

    private SoundEmitter GetEmitter()
    {
        if (availableEmitters.Count > 0)
        {
            SoundEmitter emitter = availableEmitters.Dequeue();
            emitter.gameObject.SetActive(true);
            activeEmitters.Add(emitter);
            return emitter;
        }

        // Voler l'emitter actif le plus ancien
        if (activeEmitters.Count > 0)
        {
            SoundEmitter oldest = activeEmitters[0];
            oldest.Stop();
            activeEmitters.RemoveAt(0);
            activeEmitters.Add(oldest);
            return oldest;
        }

        return null;
    }

    private System.Collections.IEnumerator ReturnAfterPlay(SoundEmitter emitter, float duration)
    {
        yield return new WaitForSeconds(duration + 0.1f);
        ReturnEmitter(emitter);
    }

    private void ReturnEmitter(SoundEmitter emitter)
    {
        emitter.Stop();
        emitter.gameObject.SetActive(false);
        activeEmitters.Remove(emitter);
        availableEmitters.Enqueue(emitter);
    }
}
```

### Usage depuis n'importe quel script

```csharp
public class Weapon : MonoBehaviour
{
    [SerializeField] private AudioCueSO fireSound;
    [SerializeField] private AudioCueEventChannelSO sfxChannel;

    public void Fire()
    {
        sfxChannel.RaiseEvent(fireSound, transform.position);
        // ... logique de tir
    }
}
```

---

## 2. SFX Pooling simplifie

Pattern minimaliste si le systeme SO complet est excessif :

```csharp
public class SFXPool : MonoBehaviour
{
    [SerializeField] private int poolSize = 8;
    private readonly Queue<AudioSource> pool = new();

    private void Awake()
    {
        for (int i = 0; i < poolSize; i++)
        {
            var go = new GameObject($"SFX_{i}");
            go.transform.SetParent(transform);
            var src = go.AddComponent<AudioSource>();
            src.playOnAwake = false;
            pool.Enqueue(src);
        }
    }

    public void PlaySFX(AudioClip clip, Vector3 position, float volume = 1f)
    {
        if (pool.Count == 0) return;

        AudioSource src = pool.Dequeue();
        src.transform.position = position;
        src.PlayOneShot(clip, volume);
        StartCoroutine(ReturnToPool(src, clip.length));
    }

    private System.Collections.IEnumerator ReturnToPool(AudioSource src, float delay)
    {
        yield return new WaitForSeconds(delay + 0.05f);
        pool.Enqueue(src);
    }
}
```

---

## 3. Music Crossfade avec Awaitable

Transition fluide entre deux pistes musicales avec `Awaitable` (Unity 6+) :

```csharp
using UnityEngine;

public class MusicManager : MonoBehaviour
{
    [SerializeField] private AudioSource sourceA;
    [SerializeField] private AudioSource sourceB;
    [SerializeField] private float crossfadeDuration = 2f;

    private AudioSource currentSource;
    private bool isCrossfading;

    private void Awake()
    {
        currentSource = sourceA;
        sourceA.loop = true;
        sourceB.loop = true;
        sourceB.volume = 0f;
    }

    public async void CrossfadeTo(AudioClip newTrack)
    {
        if (isCrossfading) return;
        isCrossfading = true;

        AudioSource fadeOut = currentSource;
        AudioSource fadeIn = currentSource == sourceA ? sourceB : sourceA;

        fadeIn.clip = newTrack;
        fadeIn.volume = 0f;
        fadeIn.Play();

        float elapsed = 0f;
        float startVolume = fadeOut.volume;

        while (elapsed < crossfadeDuration)
        {
            elapsed += Time.unscaledDeltaTime;
            float t = Mathf.SmoothStep(0f, 1f, elapsed / crossfadeDuration);

            fadeOut.volume = Mathf.Lerp(startVolume, 0f, t);
            fadeIn.volume = Mathf.Lerp(0f, 1f, t);

            await Awaitable.NextFrameAsync();
        }

        fadeOut.Stop();
        fadeOut.clip = null;
        fadeIn.volume = 1f;
        currentSource = fadeIn;
        isCrossfading = false;
    }

    public void SetMusicVolume(float normalizedVolume)
    {
        currentSource.volume = normalizedVolume;
    }
}
```

---

## 4. AudioMixer Snapshots

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

## 5. Spatial Audio 3D Setup

Configuration d'un AudioSource pour le son 3D :

```csharp
using UnityEngine;

public static class AudioSpatialSetup
{
    /// <summary>
    /// Configure un AudioSource pour le son 3D avec des parametres standards.
    /// </summary>
    public static void Configure3D(
        AudioSource source,
        float minDistance = 1f,
        float maxDistance = 50f,
        float dopplerLevel = 0.5f,
        AudioRolloffMode rolloff = AudioRolloffMode.Logarithmic)
    {
        source.spatialBlend = 1f; // Full 3D
        source.minDistance = minDistance;
        source.maxDistance = maxDistance;
        source.dopplerLevel = dopplerLevel;
        source.rolloffMode = rolloff;
        source.spread = 0f; // Point source (augmenter pour source large)
    }

    /// <summary>
    /// Presets par type de son.
    /// </summary>
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
    Footstep,
    Gunshot,
    Explosion,
    Voice,
    Ambiance
}
```

---

## 6. Audio Random Container (Unity 6.0+)

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
// L'Audio Random Container se comporte comme un AudioResource
[SerializeField] private AudioResource footstepContainer; // Glisser le container ici

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
