---
name: "Unity Shader Generator"
description: "Genere des shaders Unity (HLSL/ShaderLab) pour effets visuels. Triggers: /shader, /shader-gen, 'creer un shader', 'effet visuel shader', 'dissolve', 'outline', 'toon shading', 'hologram', 'water shader'. Detecte automatiquement le render pipeline (URP/HDRP/Built-in) et produit un fichier .shader pret a l'emploi avec instructions de Material."
---

# Unity Shader Generator

## Ce que fait cette skill

Genere des shaders Unity complets (fichiers `.shader`) adaptes au render pipeline du projet. Couvre les effets courants : dissolve, outline, toon, hologram, force field, water, triplanar, vertex displacement. Produit du code HLSL/ShaderLab propre, optimise mobile, avec instructions de setup Material.

## Prerequis

- Un projet Unity existant avec un `Packages/manifest.json`
- Connaissance de l'effet souhaite (description textuelle ou reference visuelle)
- Acces en ecriture au dossier `Assets/`

## Demarrage rapide

1. L'utilisateur decrit l'effet voulu (ex: "un shader de dissolve avec bordure lumineuse")
2. Le skill detecte le render pipeline du projet
3. Le skill genere le fichier `.shader` et les instructions Material

## Guide etape par etape

### Etape 1 : Identifier l'effet desire

Analyser la demande utilisateur. Classifier l'effet parmi les recettes connues :
- **Dissolve** : destruction progressive avec seuil
- **Outline** : contour colore autour d'un objet
- **Toon/Cel-shading** : rendu cartoon avec paliers de lumiere
- **Hologram** : effet holographique avec scanlines et transparence
- **Force field** : bouclier energetique avec fresnel et intersection
- **Water surface** : eau avec vagues et transparence
- **Triplanar mapping** : projection UV en world-space
- **Vertex displacement** : deformation de vertices par noise
- **Custom** : combiner les techniques ci-dessus

### Etape 2 : Detecter le render pipeline

Utiliser Grep sur le fichier `manifest.json` du projet :

```
Grep "com.unity.render-pipelines.universal" dans Packages/manifest.json → URP
Grep "com.unity.render-pipelines.high-definition" dans Packages/manifest.json → HDRP
Aucun match → Built-in Render Pipeline
```

Cette detection est **obligatoire** avant de generer le moindre code.

### Etape 3 : Choisir le format shader

Selon le pipeline detecte :

**Built-in Render Pipeline** : ShaderLab + CG/HLSL

```hlsl
Shader "Game/Effect_Name"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("Color", Color) = (1,1,1,1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        CGPROGRAM
        #pragma surface surf Standard fullforwardshadows
        struct Input { float2 uv_MainTex; };
        sampler2D _MainTex;
        fixed4 _Color;
        void surf (Input IN, inout SurfaceOutputStandard o)
        {
            fixed4 c = tex2D(_MainTex, IN.uv_MainTex) * _Color;
            o.Albedo = c.rgb;
            o.Alpha = c.a;
        }
        ENDCG
    }
    Fallback "Diffuse"
}
```

**URP** : ShaderLab + HLSL avec includes URP

```hlsl
Shader "Game/Effect_Name"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("Color", Color) = (1,1,1,1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
            };

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4 _Color;
            CBUFFER_END

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                return OUT;
            }
            half4 frag (Varyings IN) : SV_Target
            {
                half4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv) * _Color;
                return col;
            }
            ENDHLSL
        }
    }
    Fallback "Universal Render Pipeline/Lit"
}
```

**HDRP** : meme structure que URP mais avec les includes HDRP (`Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/`). Preferer Shader Graph pour HDRP quand c'est possible.

### Etape 4 : Generer le shader

Ecrire le fichier `.shader` complet dans le projet :
- **Emplacement** : `Assets/Shaders/` ou `Assets/Art/Shaders/`
- **Nommage** : `Game_Category_EffectName.shader` (ex: `Game_FX_Dissolve.shader`)
- Inclure : Properties, SubShader, Pass(es), vertex/fragment, Fallback

### Etape 5 : Instructions Material

Toujours fournir les instructions de setup Material :
1. Dans Unity : `Assets > Create > Material`
2. Assigner le shader dans le dropdown Material (chercher `Game/Category/EffectName`)
3. Configurer les Properties exposees (textures, couleurs, seuils)
4. Appliquer le Material sur le GameObject cible

## Recettes d'effets

### Dissolve

Principe : sampler une noise texture, `clip()` selon un seuil, emission sur le bord.

```hlsl
// Properties requises :
// _NoiseTex ("Noise", 2D), _DissolveAmount ("Amount", Range(0,1)),
// _EdgeWidth ("Edge Width", Range(0,0.1)), _EdgeColor ("Edge Color", Color)

half4 frag (Varyings IN) : SV_Target
{
    half4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv) * _Color;
    half noise = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, IN.uv).r;
    clip(noise - _DissolveAmount);
    half edge = smoothstep(_DissolveAmount, _DissolveAmount + _EdgeWidth, noise);
    col.rgb = lerp(_EdgeColor.rgb, col.rgb, edge);
    return col;
}
```

### Outline (deux passes)

Pass 1 : extrusion des vertices le long des normales (back-face). Pass 2 : rendu normal.

```hlsl
// Pass "Outline" (Cull Front)
Varyings vertOutline (Attributes IN)
{
    Varyings OUT;
    float3 posOS = IN.positionOS.xyz + IN.normalOS * _OutlineWidth;
    OUT.positionHCS = TransformObjectToHClip(posOS);
    return OUT;
}
half4 fragOutline (Varyings IN) : SV_Target { return _OutlineColor; }
```

### Toon / Cel-shading

Paliers de lumiere via `step()` ou `smoothstep()`, rim lighting par fresnel.

```hlsl
half NdotL = saturate(dot(IN.normalWS, _MainLightPosition.xyz));
half toon = smoothstep(_ShadowThreshold - 0.01, _ShadowThreshold + 0.01, NdotL);
half3 diffuse = lerp(_ShadowColor.rgb, col.rgb, toon);
half rim = 1.0 - saturate(dot(IN.normalWS, normalize(IN.viewDirWS)));
rim = smoothstep(_RimThreshold - 0.1, _RimThreshold + 0.1, rim);
diffuse += _RimColor.rgb * rim;
```

### Hologram

Scanlines + fresnel + transparence + jitter vertex.

```hlsl
// Vertex : jitter aleatoire
float jitter = frac(sin(dot(IN.positionOS.xy, float2(12.9898, 78.233))) * 43758.5453);
IN.positionOS.x += jitter * _JitterAmount * step(0.99, frac(_Time.y * _JitterSpeed));

// Fragment
half scanline = frac(IN.positionWS.y * _ScanlineCount + _Time.y * _ScanlineSpeed);
scanline = step(_ScanlineDensity, scanline);
half rim = pow(1.0 - saturate(dot(IN.normalWS, IN.viewDirWS)), _FresnelPower);
half4 col = _HoloColor * (scanline * 0.5 + 0.5) * (rim + 0.3);
col.a = (_HoloAlpha + rim * 0.5) * scanline;
```

### Force field

Fresnel + intersection avec la scene (depth buffer) + distortion animee.

```hlsl
half depth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, IN.screenUV), _ZBufferParams);
half intersection = 1.0 - saturate((depth - IN.positionHCS.w) / _IntersectionWidth);
half rim = pow(1.0 - saturate(dot(IN.normalWS, IN.viewDirWS)), _FresnelPower);
half pattern = SAMPLE_TEXTURE2D(_PatternTex, sampler_PatternTex, IN.uv + _Time.y * _ScrollSpeed).r;
half4 col = _FieldColor * (rim + intersection) * pattern;
col.a = saturate(rim + intersection) * _FieldAlpha;
```

### Water surface

Vertex displacement (somme de sinus) + scrolling normal maps + depth-based transparency.

```hlsl
// Vertex displacement
float wave = sin(IN.positionOS.x * _WaveFreq + _Time.y * _WaveSpeed) * _WaveAmp;
wave += sin(IN.positionOS.z * _WaveFreq * 0.7 + _Time.y * _WaveSpeed * 1.3) * _WaveAmp * 0.5;
IN.positionOS.y += wave;

// Fragment : dual normal map scrolling
float2 uv1 = IN.uv + _Time.y * _ScrollDir1 * _ScrollSpeed;
float2 uv2 = IN.uv + _Time.y * _ScrollDir2 * _ScrollSpeed * 0.8;
half3 n1 = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv1));
half3 n2 = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv2));
half3 normal = normalize(n1 + n2);
```

### Triplanar mapping

Projection UV sur 3 axes en world-space, blend par la normale.

```hlsl
half4 triplanar(TEXTURE2D_PARAM(tex, samp), float3 posWS, float3 normalWS, float sharpness)
{
    half3 blend = pow(abs(normalWS), sharpness);
    blend /= (blend.x + blend.y + blend.z);
    half4 cx = SAMPLE_TEXTURE2D(tex, samp, posWS.yz);
    half4 cy = SAMPLE_TEXTURE2D(tex, samp, posWS.xz);
    half4 cz = SAMPLE_TEXTURE2D(tex, samp, posWS.xy);
    return cx * blend.x + cy * blend.y + cz * blend.z;
}
```

### Vertex displacement

Deformation par noise pour terrain, tissu, explosions.

```hlsl
float3 displaced = IN.positionOS.xyz;
float n = noise(displaced.xz * _NoiseScale + _Time.y * _AnimSpeed);
displaced += IN.normalOS * n * _DisplaceAmount;
OUT.positionHCS = TransformObjectToHClip(displaced);
```

## Fonctions utilitaires HLSL

Inclure dans le shader selon les besoins :

```hlsl
float2 rotateUV(float2 uv, float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    uv -= 0.5;
    uv = float2(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
    uv += 0.5;
    return uv;
}

float noise(float2 p)
{
    return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

half fresnel(float3 normal, float3 viewDir, half power)
{
    return pow(1.0 - saturate(dot(normal, viewDir)), power);
}

float remap(float value, float from1, float to1, float from2, float to2)
{
    return from2 + (value - from1) * (to2 - from2) / (to1 - from1);
}
```

## Optimisation mobile

- Utiliser `half` au lieu de `float` pour couleurs, UV, normales
- Maximum 4 samples texture par pass
- Eviter les dependent texture reads (calculer les UV dans le vertex shader)
- Utiliser `#pragma shader_feature` et non `#pragma multi_compile` (reduit les variants compilees)
- Pas de branching dynamique (`if`) : utiliser `step()`, `lerp()`, `saturate()` a la place
- Tester avec `#pragma target 3.0` minimum
- Utiliser `Tags { "Queue"="Geometry" }` sauf si transparence requise

## Regles strictes

- **TOUJOURS** detecter le render pipeline avant de generer du code
- **TOUJOURS** inclure un `Fallback` shader
- **TOUJOURS** exposer les parametres cles comme Properties (jamais de valeurs hardcodees)
- **TOUJOURS** fournir les instructions Material apres le shader
- **TOUJOURS** placer le fichier dans `Assets/Shaders/` ou sous-dossier
- **TOUJOURS** nommer le shader avec le pattern `Game/Category/EffectName`
- **JAMAIS** melanger `CGPROGRAM/ENDCG` et `HLSLPROGRAM/ENDHLSL` dans le meme shader
- **JAMAIS** utiliser des surface shaders en URP/HDRP (vertex/fragment uniquement)
- **JAMAIS** oublier le `CBUFFER_START(UnityPerMaterial)` en URP (necessaire pour SRP Batcher)
- **PREFERER** `half` precision pour les targets mobiles
- **PREFERER** Shader Graph pour les artistes non-techniques (fournir une description nodale)

## Skills connexes

- Le shader est pour un prototype rapide ? Utiliser `/proto` (Unity Rapid Proto) pour le setup scene
- Configurer le build apres les shaders ? Utiliser `/build-config` (Unity Build & CI/CD Configurator)

## Troubleshooting

| Probleme | Solution |
|----------|----------|
| Shader rose/magenta | Erreur de compilation : verifier les includes du pipeline, les noms de fonctions, les semantiques |
| SRP Batcher incompatible | Mettre toutes les Properties dans un `CBUFFER_START(UnityPerMaterial)` / `CBUFFER_END` |
| Shader ne fonctionne pas en URP | Verifier les tags `"RenderPipeline"="UniversalPipeline"` et `"LightMode"="UniversalForward"` |
| Transparence ne s'affiche pas | Ajouter `Tags { "Queue"="Transparent" }`, `Blend SrcAlpha OneMinusSrcAlpha`, `ZWrite Off` |
| Ombre absente | Ajouter un pass `ShadowCaster` avec les includes appropriees |
| Performance faible mobile | Reduire les samples texture, passer en `half`, supprimer les `if` dynamiques |
| Textures floues / tiling incorrect | Verifier `TRANSFORM_TEX(IN.uv, _MainTex)` et les `_ST` variables dans le CBUFFER |
| Depth intersection ne fonctionne pas | S'assurer que `_CameraDepthTexture` est active (URP : cocher Depth Texture dans le pipeline asset) |
