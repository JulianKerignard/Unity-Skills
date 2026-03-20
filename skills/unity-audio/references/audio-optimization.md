# Audio Optimization & Import Settings

Guide d'optimisation audio pour Unity 6+. Couvre les import settings, les anti-patterns courants, les budgets memoire par plateforme, et le Scriptable Audio Pipeline (Unity 6.3+).

---

## 1. Import Settings par type audio

| Type | Load Type | Compression | Quality | Sample Rate | Force Mono | Preload |
|------|-----------|-------------|---------|-------------|------------|---------|
| SFX court (< 1s) | Decompress On Load | Vorbis | 70% | 22050 Hz | Oui | Oui |
| SFX moyen (1-5s) | Compressed In Memory | Vorbis | 70% | 44100 Hz | Non | Oui |
| SFX long (> 5s) | Compressed In Memory | Vorbis | 60% | 44100 Hz | Non | Non |
| Musique | Streaming | Vorbis | 50% | 44100 Hz | Non | Non |
| Ambiance loop | Streaming | Vorbis | 50% | 22050 Hz | Oui | Non |
| UI (click, hover) | Decompress On Load | PCM ou ADPCM | - | 22050 Hz | Oui | Oui |
| Voix/dialogues | Compressed In Memory | Vorbis | 65% | 44100 Hz | Oui | Non |

### Notes sur les Load Types

- **Decompress On Load** : decompresse en RAM au chargement. Rapide a jouer, consomme beaucoup de memoire. Reserveur aux clips courts (< 200 Ko compresses).
- **Compressed In Memory** : stocke compresse en RAM, decompresse a la volee. Bon compromis CPU/memoire pour les clips moyens.
- **Streaming** : lit depuis le disque en temps reel. Quasi zero RAM mais utilise le I/O disque. Obligatoire pour la musique et les longues boucles.

### Configuration par plateforme

```csharp
// Script d'import automatique (placer dans un dossier Editor)
using UnityEditor;
using UnityEngine;

public class AudioImportProcessor : AssetPostprocessor
{
    private void OnPreprocessAudio()
    {
        var importer = (AudioImporter)assetImporter;
        string path = importer.assetPath.ToLower();

        AudioImporterSampleSettings settings = importer.defaultSampleSettings;

        if (path.Contains("/sfx/"))
        {
            settings.loadType = AudioClipLoadType.DecompressOnLoad;
            settings.compressionFormat = AudioCompressionFormat.Vorbis;
            settings.quality = 0.7f;
            importer.forceToMono = true;
        }
        else if (path.Contains("/music/"))
        {
            settings.loadType = AudioClipLoadType.Streaming;
            settings.compressionFormat = AudioCompressionFormat.Vorbis;
            settings.quality = 0.5f;
            importer.forceToMono = false;
        }
        else if (path.Contains("/ambiance/"))
        {
            settings.loadType = AudioClipLoadType.Streaming;
            settings.compressionFormat = AudioCompressionFormat.Vorbis;
            settings.quality = 0.5f;
            importer.forceToMono = true;
        }
        else if (path.Contains("/ui/"))
        {
            settings.loadType = AudioClipLoadType.DecompressOnLoad;
            settings.compressionFormat = AudioCompressionFormat.ADPCM;
            importer.forceToMono = true;
        }

        importer.defaultSampleSettings = settings;

        // Override mobile
        AudioImporterSampleSettings mobileSettings = settings;
        mobileSettings.quality = Mathf.Min(settings.quality, 0.5f);
        mobileSettings.sampleRateSetting = AudioSampleRateSetting.OverrideSampleRate;
        mobileSettings.sampleRateOverride = 22050;
        importer.SetOverrideSampleSettings("Android", mobileSettings);
        importer.SetOverrideSampleSettings("iOS", mobileSettings);
    }
}
```

---

## 2. Anti-patterns audio

| # | Anti-pattern | Severite | Impact | Correction |
|---|-------------|----------|--------|------------|
| 1 | Musique en `Decompress On Load` | Critique | 50-200 Mo RAM gaspilles | Passer en `Streaming` |
| 2 | `AudioSource.Play()` pour SFX rapides | Haute | Sons coupes, pas de superposition | Utiliser `PlayOneShot()` ou pool |
| 3 | `Instantiate`/`Destroy` par son joue | Haute | GC spikes, fragmentation | Pool de SoundEmitters |
| 4 | Tous les clips en stereo | Haute | Double memoire inutile | `Force Mono` sauf musique |
| 5 | Pas de AudioMixerGroup assigne | Haute | Volume impossible a controler globalement | Router chaque source vers un groupe |
| 6 | `spatialBlend = 0` sur son 3D | Moyenne | Son audible partout, pas de spatialisation | Mettre `spatialBlend = 1` |
| 7 | Sample rate 48000 Hz sur SFX | Moyenne | Fichiers plus gros sans gain perceptible | Override a 22050 Hz |
| 8 | Pas de limite de voix simultanees | Moyenne | 100+ voix = CPU spike | `AudioSettings.SetMaxVoices()`, priorites |
| 9 | Volume lineaire au lieu de logarithmique | Basse | Controle de volume non naturel | `Mathf.Log10(v) * 20f` pour dB |
| 10 | AudioListener absent ou duplique | Basse | Pas de son ou son double | Un seul AudioListener sur la camera active |
| 11 | Clips non trimmes (silence en debut/fin) | Basse | Latence percue, memoire gaspillee | Trimmer dans un editeur audio externe |

---

## 3. Scriptable Audio Pipeline (Unity 6.3+)

> Fonctionnalite experimentale introduite en Unity 6.3. Permet de creer des pipelines audio custom avec des noeuds DSP compiles en Burst.

### Architecture

Le Scriptable Audio Pipeline repose sur deux concepts :

- **Control Part** : s'execute sur le main thread, gere la logique de haut niveau (declenchement, parametres, routing). Pas de contrainte temps-reel.
- **Real-Time Part** : s'execute sur le thread audio, traite les echantillons. Doit etre Burst-compatible (pas d'allocations, pas de managed references).

### Types de noeuds

| Noeud | Role | Exemple |
|-------|------|---------|
| **Generator** | Produit un signal audio | Oscillateur, lecteur de samples |
| **Processor** | Transforme un signal | Filtre, reverb, distortion |
| **Mixer** | Combine plusieurs signaux | Mixeur de canaux |
| **Root Output** | Sortie finale vers le hardware | Un seul par pipeline |

### Quand utiliser

- Synthese procedurale (moteur de vehicule, sons dynamiques)
- Effets DSP custom (reverb spatiale, vocoder)
- Prototypage de plugins audio sans code natif
- Audio reactif au gameplay en temps reel

### Quand NE PAS utiliser

- Lecture simple de clips (AudioSource suffit)
- Musique pre-enregistree (AudioSource + Streaming)
- Projets ciblant la compatibilite Unity < 6.3

---

## 4. Budgets memoire audio par plateforme

| Plateforme | Budget RAM audio | Max voix simultanees | Notes |
|------------|-----------------|---------------------|-------|
| Mobile (low-end) | 15-25 Mo | 24 | Privilegier ADPCM pour SFX |
| Mobile (high-end) | 30-50 Mo | 32 | Vorbis acceptable |
| Desktop | 80-150 Mo | 64 | Qualite superieure possible |
| Console | 100-200 Mo | 64-128 | Selon la console et le jeu |
| VR/AR | 40-80 Mo | 48 | Spatialisation couteuse en CPU |
| WebGL | 20-40 Mo | 24 | Compression limitee, pas de Streaming fiable |

### Calcul rapide de la memoire audio

```
Memoire decomppressee = duree(s) x sampleRate x canaux x 2 (16-bit) octets

Exemples :
- SFX 0.5s mono 22050 Hz  = 0.5 x 22050 x 1 x 2 = ~22 Ko
- SFX 3s stereo 44100 Hz  = 3 x 44100 x 2 x 2 = ~529 Ko
- Musique 3min stereo 44100 Hz = 180 x 44100 x 2 x 2 = ~31 Mo
```

> La musique de 3 minutes decomppressee occupe 31 Mo : c'est pourquoi le `Streaming` est obligatoire pour les pistes musicales.

### Recommandations par categorie

| Categorie | Budget type | Strategie |
|-----------|------------|-----------|
| SFX | 5-15 Mo | Decompress On Load, mono, 22 kHz |
| Musique | 0 Mo (streaming) | Streaming, jamais en RAM |
| Ambiance | 0 Mo (streaming) | Streaming, mono, 22 kHz |
| UI | 1-3 Mo | Decompress On Load, ADPCM, mono |
| Voix | 5-20 Mo | Compressed In Memory, mono |

---

## 5. Checklist d'optimisation

- [ ] Tous les clips musicaux sont en `Streaming`
- [ ] Les SFX courts (< 1s) sont en `Decompress On Load` et `Force Mono`
- [ ] Chaque AudioSource a un `AudioMixerGroup` assigne
- [ ] Le nombre max de voix est configure (`AudioSettings`)
- [ ] Les import settings sont overrides par plateforme (mobile = qualite reduite)
- [ ] Pas de clips en stereo inutilement (mono sauf musique et effets stereo specifiques)
- [ ] Le Audio Profiler a ete verifie (pas de voix fantomes, pas de clips orphelins)
- [ ] Les sons 3D ont `spatialBlend = 1` et des distances min/max coherentes
- [ ] Les volumes sont geres via AudioMixer (pas `AudioSource.volume` direct)
- [ ] Les SFX utilisent `PlayOneShot()` ou un pool, jamais `Play()` repete
