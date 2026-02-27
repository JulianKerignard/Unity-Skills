# Shader Recipes — Unity Shader Generator

Recettes d'effets visuels pour le skill `/shader-gen`. Chaque recette contient le principe, les Properties requises, et le code HLSL du fragment et/ou vertex shader.

Ces snippets sont prevus pour URP (HLSL). Pour le Built-in pipeline, adapter les includes et macros (voir le template Built-in dans SKILL.md).

---

## 1. Dissolve

Principe : sampler une noise texture, `clip()` selon un seuil, emission sur le bord.

Properties requises :
- `_NoiseTex ("Noise", 2D)` — texture de bruit
- `_DissolveAmount ("Amount", Range(0,1))` — progression du dissolve
- `_EdgeWidth ("Edge Width", Range(0,0.1))` — largeur du bord lumineux
- `_EdgeColor ("Edge Color", Color)` — couleur du bord

```hlsl
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

---

## 2. Outline (deux passes)

Pass 1 : extrusion des vertices le long des normales (back-face). Pass 2 : rendu normal.

Properties requises :
- `_OutlineWidth ("Outline Width", Range(0, 0.1))` — epaisseur du contour
- `_OutlineColor ("Outline Color", Color)` — couleur du contour

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

---

## 3. Toon / Cel-shading

Paliers de lumiere via `step()` ou `smoothstep()`, rim lighting par fresnel.

Properties requises :
- `_ShadowThreshold ("Shadow Threshold", Range(0,1))` — seuil ombre/lumiere
- `_ShadowColor ("Shadow Color", Color)` — couleur de l'ombre
- `_RimThreshold ("Rim Threshold", Range(0,1))` — seuil du rim
- `_RimColor ("Rim Color", Color)` — couleur du rim

```hlsl
half NdotL = saturate(dot(IN.normalWS, _MainLightPosition.xyz));
half toon = smoothstep(_ShadowThreshold - 0.01, _ShadowThreshold + 0.01, NdotL);
half3 diffuse = lerp(_ShadowColor.rgb, col.rgb, toon);
half rim = 1.0 - saturate(dot(IN.normalWS, normalize(IN.viewDirWS)));
rim = smoothstep(_RimThreshold - 0.1, _RimThreshold + 0.1, rim);
diffuse += _RimColor.rgb * rim;
```

---

## 4. Hologram

Scanlines + fresnel + transparence + jitter vertex.

Properties requises :
- `_HoloColor ("Holo Color", Color)` — couleur holographique
- `_HoloAlpha ("Holo Alpha", Range(0,1))` — transparence de base
- `_ScanlineCount ("Scanline Count", Float)` — nombre de scanlines
- `_ScanlineSpeed ("Scanline Speed", Float)` — vitesse de defilement
- `_ScanlineDensity ("Scanline Density", Range(0,1))` — densite des lignes
- `_FresnelPower ("Fresnel Power", Range(0.1, 10))` — puissance du fresnel
- `_JitterAmount ("Jitter Amount", Float)` — amplitude du jitter
- `_JitterSpeed ("Jitter Speed", Float)` — frequence du jitter

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

---

## 5. Force field

Fresnel + intersection avec la scene (depth buffer) + distortion animee.

Properties requises :
- `_FieldColor ("Field Color", Color)` — couleur du champ
- `_FieldAlpha ("Field Alpha", Range(0,1))` — transparence
- `_FresnelPower ("Fresnel Power", Range(0.1, 10))` — puissance du fresnel
- `_IntersectionWidth ("Intersection Width", Float)` — largeur de l'intersection
- `_PatternTex ("Pattern", 2D)` — texture de motif
- `_ScrollSpeed ("Scroll Speed", Float)` — vitesse d'animation

Prerequis : `_CameraDepthTexture` doit etre active dans le pipeline asset URP.

```hlsl
half depth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, IN.screenUV), _ZBufferParams);
half intersection = 1.0 - saturate((depth - IN.positionHCS.w) / _IntersectionWidth);
half rim = pow(1.0 - saturate(dot(IN.normalWS, IN.viewDirWS)), _FresnelPower);
half pattern = SAMPLE_TEXTURE2D(_PatternTex, sampler_PatternTex, IN.uv + _Time.y * _ScrollSpeed).r;
half4 col = _FieldColor * (rim + intersection) * pattern;
col.a = saturate(rim + intersection) * _FieldAlpha;
```

---

## 6. Water surface

Vertex displacement (somme de sinus) + scrolling normal maps + depth-based transparency.

Properties requises :
- `_WaveFreq ("Wave Frequency", Float)` — frequence des vagues
- `_WaveSpeed ("Wave Speed", Float)` — vitesse des vagues
- `_WaveAmp ("Wave Amplitude", Float)` — amplitude des vagues
- `_NormalMap ("Normal Map", 2D)` — normal map pour la surface
- `_ScrollDir1 ("Scroll Dir 1", Vector)` — direction scroll 1
- `_ScrollDir2 ("Scroll Dir 2", Vector)` — direction scroll 2
- `_ScrollSpeed ("Scroll Speed", Float)` — vitesse de scroll

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

---

## 7. Triplanar mapping

Projection UV sur 3 axes en world-space, blend par la normale.

Properties requises :
- `_TriplanarTex ("Triplanar Texture", 2D)` — texture a projeter
- `_TriplanarSharpness ("Sharpness", Range(1, 20))` — nettete du blend

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

---

## 8. Vertex displacement

Deformation par noise pour terrain, tissu, explosions.

Properties requises :
- `_NoiseScale ("Noise Scale", Float)` — echelle du bruit
- `_AnimSpeed ("Anim Speed", Float)` — vitesse d'animation
- `_DisplaceAmount ("Displace Amount", Float)` — amplitude du deplacement

```hlsl
float3 displaced = IN.positionOS.xyz;
float n = noise(displaced.xz * _NoiseScale + _Time.y * _AnimSpeed);
displaced += IN.normalOS * n * _DisplaceAmount;
OUT.positionHCS = TransformObjectToHClip(displaced);
```
