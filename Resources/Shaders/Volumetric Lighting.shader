Shader "Hidden/Volumetric Lighting"
{
   Properties
   {
      _MainTex ("Main Texture", 2D) = "white" {}

       // Raymarch
      _Scattering("Scattering Power", Float) = 1
      _MaxSteps("Max Steps", Int) = 25
      _MaxDistance("Max Distance", Float) = 50
      _Jitter("Jitter", Float) = 2

      // Blur
      _Downsampling("Down Sampling", Int) = 2
      _GuassSamples("Iterations", Int) = 3
      _GuassAmount("Blend", Float) = 1
      
      // Compositing
      _Intensity("Intensity", Float) = 1

      // Debug
      _NormalizeRayMarch("Normalize Ray March", Int) = 0
   }
   SubShader
   {
      // No culling or depth
      Cull Off ZWrite Off ZTest Always

      Tags
      {
         "RenderType" = "Opaque"
         "RenderPipeline" = "UniversalPipeline"
      }

      Pass
      {
      Name "Raymarching"

      HLSLPROGRAM

      #pragma prefer_hlslcc gles
      #pragma exclude_renderers d3d11_9x

      #pragma vertex vert
      #pragma fragment frag
      #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN

      #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
      #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

      struct appdata
      {
         float4 vertex : POSITION;
         float2 uv : TEXCOORD0;
      };

      struct v2f
      {
         float4 vertex : SV_POSITION;
         float2 uv : TEXCORRD0;
      };

      v2f vert(appdata v)
      {
         v2f o;
         o.vertex = TransformObjectToHClip(v.vertex.xyz);
         o.uv = v.uv;
         return o;
      }

      sampler2D _MainTex;

      float _Scattering = 1;
      int _MaxSteps = 25;
      float _MaxDistance = 75;
      float _Jitter = 2;

      float3 _LightDirection;

      int _NormalizeRayMarch;

      float random01(float2 p)
      {
         return frac(sin(dot(p, float2(41, 289))) * 45758.5453);
      }

      // Mie scaterring approximated with Henyey-Greenstein phase function.
      float ComputeScattering(float lightDotView, float scattering)
      {
         float result = 1.0f - scattering * scattering;
         float a = abs(1.0f + scattering * scattering - (2.0f * scattering) * lightDotView);
         result /= (4.0f * PI * pow(a, 1.5f));

         return result;
      }

      float RayMarch(v2f i)
      {
         float3 startPosition = _WorldSpaceCameraPos;
         float3 endPosition = ComputeWorldSpacePosition(i.uv, SampleSceneDepth(i.uv), UNITY_MATRIX_I_VP);

         float3 rayVector = endPosition - startPosition;
         float3 rayDirection = normalize(rayVector);
         float rayLength = clamp(length(rayVector), 0, _MaxDistance);

         int steps = _MaxSteps;
         float minStepLength = rayLength / steps;
         float3 step = rayDirection * minStepLength;

         // By adding a jitter value to the ray position, we can get away with marching for fewer steps and boost performance
         float rayStartOffset = random01(i.uv) * minStepLength * _Jitter;
         float3 currentPosition = startPosition + rayStartOffset * rayDirection;

         float accumulatedLight = 0;
         for (int i = 0; i < steps - 1; i++)
         {
            half shadowMapValue = MainLightRealtimeShadow(TransformWorldToShadowCoord(currentPosition));
            if (shadowMapValue > 0)
            {
               accumulatedLight += ComputeScattering(dot(rayDirection, _LightDirection), _Scattering);
            }

            currentPosition += step;
         }

         // Normalize the accumulated light over the number of steps we took
         accumulatedLight /= steps;

         return accumulatedLight;
      }

      float4 frag(v2f i) : SV_Target
      {
         float raymarch = RayMarch(i);
         if (_NormalizeRayMarch)
         {
            raymarch = normalize(raymarch);
         }

         return float4(raymarch, 0, 0, 1);
      }

      ENDHLSL
      }

      Pass
      {
         Name "Gaussian Blur x"

         HLSLPROGRAM

         #pragma vertex vert
         #pragma fragment frag

         #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
         #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

         struct appdata
         {
            float4 vertex : POSITION;
            float2 uv : TEXCOORD0;
         };

         struct v2f
         {
            float4 vertex : SV_POSITION;
            float2 uv : TEXCORRD0;
         };

         v2f vert(appdata v)
         {
            v2f o;
            o.vertex = TransformObjectToHClip(v.vertex.xyz);
            o.uv = v.uv;
            return o;
         }

         sampler2D _MainTex;
         int _GuassSamples;
         float _GuassAmount;

         static const float gauss_filter_weights[] = { 0.14446445f, 0.13543542f, 0.11153505f, 0.08055309f, 0.05087564f, 0.02798160f, 0.01332457f, 0.00545096f };
         #define BLUR_DEPTH_FALLOFF 100.0f

         float frag(v2f i) : SV_TARGET
         {
            float col = 0;
            float accumResult = 0;
            float accumWeights = 0;

            float depthCentre = SampleSceneDepth(i.uv);

            int samples = _GuassSamples;
            for (int index = -samples; index <= samples; index++)
            {
               float2 uv = i.uv + float2(index * _GuassAmount / 1000, 0);
               float kernelSample = tex2D(_MainTex, uv).r;
               float depthKernal = SampleSceneDepth(uv);

               float depthDiff = abs(depthKernal - depthCentre);
               float r2 = depthDiff * BLUR_DEPTH_FALLOFF;
               float g = exp(-r2 * r2);
               float weight = g * gauss_filter_weights[abs(index)];

               accumResult += weight * kernelSample;
               accumWeights += weight;
            }

            col = accumResult / accumWeights;

            return col;
         }

         ENDHLSL
      }

      Pass
      {
         Name "Gaussian Blur y"

         HLSLPROGRAM

         #pragma vertex vert
         #pragma fragment frag

         #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
         #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

         struct appdata
         {
            float4 vertex : POSITION;
            float2 uv : TEXCOORD0;
         };

         struct v2f
         {
            float4 vertex : SV_POSITION;
            float2 uv : TEXCORRD0;
         };

         v2f vert(appdata v)
         {
            v2f o;
            o.vertex = TransformObjectToHClip(v.vertex.xyz);
            o.uv = v.uv;
            return o;
         }

         sampler2D _MainTex;
         int _GuassSamples;
         float _GuassAmount;

         static const float gauss_filter_weights[] = { 0.14446445f, 0.13543542f, 0.11153505f, 0.08055309f, 0.05087564f, 0.02798160f, 0.01332457f, 0.00545096f };
         #define BLUR_DEPTH_FALLOFF 100.0f

         float frag(v2f i) : SV_TARGET
         {
            float col = 0;
            float accumResult = 0;
            float accumWeights = 0;

            float depthCentre = SampleSceneDepth(i.uv);

            int samples = _GuassSamples;
            for (int index = -samples; index <= samples; index++)
            {
               float2 uv = i.uv + float2(0, index * _GuassAmount / 1000);
               float kernelSample = tex2D(_MainTex, uv).r;
               float depthKernal = SampleSceneDepth(uv);

               float depthDiff = abs(depthKernal - depthCentre);
               float r2 = depthDiff * BLUR_DEPTH_FALLOFF;
               float g = exp(-r2 * r2);
               float weight = g * gauss_filter_weights[abs(index)];

               accumResult += weight * kernelSample;
               accumWeights += weight;
            }

            col = accumResult / accumWeights;

            return col;
         }

         ENDHLSL
      }

      Pass
      {
         Name "Compositing"

         HLSLPROGRAM

         #pragma vertex vert
         #pragma fragment frag

         #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
         #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

         struct appdata
         {
            float4 vertex : POSITION;
            float2 uv : TEXCOORD0;
         };

         struct v2f
         {
            float4 vertex : SV_POSITION;
            float2 uv : TEXCORRD0;
         };

         v2f vert(appdata v)
         {
            v2f o;
            o.vertex = TransformObjectToHClip(v.vertex.xyz);
            o.uv = v.uv;
            return o;
         }

         sampler2D _MainTex;
         
         TEXTURE2D(_volumetricTexture);
         SAMPLER(sampler_volumetricTexture);

         TEXTURE2D(_LowResDepth);
         SAMPLER(sampler_LowResDepth);

         float _Intensity;
         float _Downsample;

         float3 LightColor(v2f i)
         {
            float3 pos = ComputeWorldSpacePosition(i.uv, SampleSceneDepth(i.uv), UNITY_MATRIX_I_VP);
            float4 shadowCoord = TransformWorldToShadowCoord(pos);

            return GetMainLight(shadowCoord).color;
         }

         float3 frag(v2f i) : SV_TARGET
         {
            float col = 0;
            int offset = 0;

            float d0 = SampleSceneDepth(i.uv);

            float d1 = _LowResDepth.Sample(sampler_LowResDepth, i.uv, int2(0, 1)).x;
            float d2 = _LowResDepth.Sample(sampler_LowResDepth, i.uv, int2(0, -1)).x;
            float d3 = _LowResDepth.Sample(sampler_LowResDepth, i.uv, int2(1, 0)).x;
            float d4 = _LowResDepth.Sample(sampler_LowResDepth, i.uv, int2(-1, 0)).x;

            d1 = abs(d0 - d1);
            d2 = abs(d0 - d2);
            d3 = abs(d0 - d3);
            d4 = abs(d0 - d4);

            real dmin = min(min(d1, d2), min(d3, d4));

            if (dmin == d1)
            {
               offset = 0;
            }
            else if (dmin == d2)
            {
               offset = 1;
            }
            else if (dmin == d3)
            {
               offset = 2;
            }
            else  if (dmin == d4)
            {
               offset = 3;
            }
             
            col = 0;
            switch (offset) 
            {
               case 0:
                  col = _volumetricTexture.Sample(sampler_volumetricTexture, i.uv, int2(0, 1)).r;
                  break;

               case 1:
                  col = _volumetricTexture.Sample(sampler_volumetricTexture, i.uv, int2(0, -1)).r;
                  break;

               case 2:
                  col = _volumetricTexture.Sample(sampler_volumetricTexture, i.uv, int2(1, 0)).r;
                  break;

               case 3:
                  col = _volumetricTexture.Sample(sampler_volumetricTexture, i.uv, int2(-1, 0)).r;
                  break;

               default:
                  col = _volumetricTexture.Sample(sampler_volumetricTexture, i.uv).r;
                  break;
            }

            float3 finalShaft = saturate(col) * LightColor(i) * _Intensity;
            float3 screen = tex2D(_MainTex, i.uv).rgb;

            return screen + finalShaft;
         }

         ENDHLSL
      }

      Pass
      {
          Name "Sample Depth"

          HLSLPROGRAM

          #pragma vertex vert
          #pragma fragment frag

          #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
          #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

         struct appdata
         {
            float4 vertex : POSITION;
            float2 uv : TEXCOORD0;
         };

         struct v2f
         {
            float4 vertex : SV_POSITION;
            float2 uv : TEXCORRD0;
         };

         v2f vert(appdata v)
         {
            v2f o;
            o.vertex = TransformObjectToHClip(v.vertex.xyz);
            o.uv = v.uv;
            return o;
         }

         float3 frag(v2f i) : SV_Target
         {
            return SampleSceneDepth(i.uv);
         }

         ENDHLSL

      }
   }
}
