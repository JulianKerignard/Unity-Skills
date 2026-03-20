# Shader Templates & Render Graph Patterns

## Templates par pipeline

### Built-in Render Pipeline : ShaderLab + CG/HLSL

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

### URP : ShaderLab + HLSL avec includes URP

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

### HDRP

Meme structure que URP mais avec les includes HDRP (`Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/`). Preferer Shader Graph pour HDRP quand c'est possible.

## Render Graph API

Unity 6 utilise le **Render Graph** comme backend pour URP et HDRP. Les custom render passes doivent migrer vers cette API. `SetupRenderPasses` est **deprecie**.

### Migration obligatoire

| Ancien (deprecie) | Nouveau (Render Graph) |
|---|---|
| `ScriptableRenderPass.Execute(ScriptableRenderContext, ref RenderingData)` | `ScriptableRenderPass.RecordRenderGraph(RenderGraph, ContextContainer)` |
| `SetupRenderPasses(...)` dans ScriptableRendererFeature | `AddRenderPasses(ScriptableRenderer, ref RenderingData)` |
| Allocation manuelle de RTHandles | `RenderGraph.CreateTexture(desc)` — gestion automatique |
| `cmd.Blit(...)` | `RenderGraphUtils.BlitMaterialParameters` via Render Graph |

### Pattern : Custom Fullscreen Pass (URP)

```csharp
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class CustomFullscreenPass : ScriptableRenderPass
{
    private Material _material;

    public CustomFullscreenPass(Material material)
    {
        _material = material;
        renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing;
    }

    public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
    {
        var resourceData = frameData.Get<UniversalResourceData>();

        using (var builder = renderGraph.AddRasterRenderPass<PassData>("Custom Fullscreen", out var passData))
        {
            passData.material = _material;
            builder.SetRenderAttachment(resourceData.activeColorTexture, 0);
            builder.SetRenderFunc((PassData data, RasterGraphContext ctx) =>
            {
                ctx.cmd.DrawProcedural(Matrix4x4.identity, data.material, 0, MeshTopology.Triangles, 3);
            });
        }
    }

    private class PassData
    {
        public Material material;
    }
}
```

### Avantages du Render Graph

- **Gestion automatique des ressources** : pas besoin d'allouer/liberer les render textures manuellement
- **Culling de passes** : les passes non-utilisees sont automatiquement supprimees
- **Meilleur profiling** : chaque passe apparait clairement dans le Frame Debugger
- **Fullscreen Shader Graph (6.3+)** : pour les post-process simples, preferer Fullscreen Shader Graph au custom pass code — zero C#, resultats visuels immediats

## ShadowCaster Pass

Pass **requis** pour que l'objet projette des ombres en URP. L'ajouter systematiquement apres le pass ForwardLit :

```hlsl
// Pass ShadowCaster — REQUIS pour que l'objet projette des ombres en URP
Pass
{
    Name "ShadowCaster"
    Tags { "LightMode"="ShadowCaster" }
    ZWrite On
    ZTest LEqual
    ColorMask 0

    HLSLPROGRAM
    #pragma vertex vert
    #pragma fragment frag
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShadowCasterPass.hlsl"
    // Utilise les vertex/fragment du ShadowCasterPass.hlsl
    ENDHLSL
}
```
