# HLSL Utilities — Unity Shader Generator

Fonctions utilitaires et conseils d'optimisation pour le skill `/shader-gen`.

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

## Debugging helpers

Fonctions utiles pour visualiser les donnees intermediaires dans le shader :

```hlsl
// Visualiser les normales (debug)
half4 debugNormals(float3 normalWS)
{
    return half4(normalWS * 0.5 + 0.5, 1.0);
}

// Visualiser les UVs (debug)
half4 debugUVs(float2 uv)
{
    return half4(uv.x, uv.y, 0, 1);
}
```

Usage : remplacer temporairement le `return` du fragment shader par `return debugNormals(IN.normalWS);` pour diagnostiquer les problemes de normales ou d'UVs.

## Optimisation mobile

- Utiliser `half` au lieu de `float` pour couleurs, UV, normales
- Maximum 4 samples texture par pass
- Eviter les dependent texture reads (calculer les UV dans le vertex shader)
- Utiliser `#pragma shader_feature` et non `#pragma multi_compile` (reduit les variants compilees)
- Pas de branching dynamique (`if`) : utiliser `step()`, `lerp()`, `saturate()` a la place
- Tester avec `#pragma target 3.0` minimum
- Utiliser `Tags { "Queue"="Geometry" }` sauf si transparence requise
