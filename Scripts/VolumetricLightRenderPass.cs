using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace JARcraft.Game.Rendering
{
    public class VolumetricLightRenderPass : ScriptableRenderPass
    {
        const string profilerTag = "Volumetric Light Post Process";

        VolumetricLightSettings settings;
        VolumetricLightRendererFeature.RenderStage renderStage;

        RTHandle colorBuffer;
        RTHandle temporaryBuffer1;
        RTHandle temporaryBuffer2;
        RTHandle temporaryBuffer3;

        Material material;

        public VolumetricLightRenderPass()
        {
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            material = CoreUtils.CreateEngineMaterial("Hidden/Volumetric Lighting");
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            settings = VolumeManager.instance.stack.GetComponent<VolumetricLightSettings>();

            if (!ShouldRender())
            {
                return;
            }

            material.SetFloat("_Scattering", settings.scatteringPower.value);
            material.SetInt("_MaxSteps", settings.maxSteps.value);
            material.SetFloat("_MaxDistance", settings.maxDistance.value);
            material.SetFloat("_Jitter", settings.jitter.value);

            material.SetFloat("_GuassSamples", settings.iterations.value);
            material.SetFloat("_GuassAmount", settings.blend.value);

            material.SetFloat("_Intensity", settings.intensity.value);

            material.SetInt("_NormalizeRayMarch", renderStage == VolumetricLightRendererFeature.RenderStage.Composit ? 0 : 1);

            RenderTextureDescriptor descriptor = renderingData.cameraData.cameraTargetDescriptor;

            descriptor.depthBufferBits = 0; // Color and depth cannot be combined in RTHandles

            colorBuffer = renderingData.cameraData.renderer.cameraColorTargetHandle;

            RenderingUtils.ReAllocateIfNeeded(ref temporaryBuffer1, Vector2.one / settings.downsampling.value, descriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_TemporaryBuffer1");
            RenderingUtils.ReAllocateIfNeeded(ref temporaryBuffer2, Vector2.one / settings.downsampling.value, descriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_TemporaryBuffer2");
            RenderingUtils.ReAllocateIfNeeded(ref temporaryBuffer3, descriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_TemporaryBuffer3");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (!ShouldRender())
            {
                return;
            }

            CommandBuffer cmd = CommandBufferPool.Get();

            using (new ProfilingScope(cmd, new ProfilingSampler(profilerTag)))
            {
                DoBlits(cmd);
            }

            context.ExecuteCommandBuffer(cmd);

            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        void DoBlits(CommandBuffer cmd)
        {
            cmd.Blit(colorBuffer, temporaryBuffer1, material, 0); // Raymarch

            if (renderStage == VolumetricLightRendererFeature.RenderStage.Raymarch)
            {
                cmd.Blit(temporaryBuffer1, colorBuffer);
                return;
            }

            cmd.Blit(temporaryBuffer1, temporaryBuffer2, material, 1); // Blur x
            cmd.Blit(temporaryBuffer2, temporaryBuffer1, material, 2); // Blur y

            if (renderStage == VolumetricLightRendererFeature.RenderStage.Blur)
            {
                cmd.Blit(temporaryBuffer1, colorBuffer);
                return;
            }

            cmd.SetGlobalTexture("_volumetricTexture", temporaryBuffer1);

            cmd.Blit(colorBuffer, temporaryBuffer2, material, 4);
            cmd.SetGlobalTexture("_LowResDepth", temporaryBuffer2);

            // Upscale and Composite
            cmd.Blit(colorBuffer, temporaryBuffer3, material, 3);
            cmd.Blit(temporaryBuffer3, colorBuffer); // Back to source
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            if (cmd == null)
            {
                throw new System.ArgumentNullException("cmd");
            }

            colorBuffer = null;
        }

        public void Dispose()
        {
            temporaryBuffer1?.Release();
            temporaryBuffer2?.Release();
            temporaryBuffer3?.Release();

            CoreUtils.Destroy(material);
        }

        bool ShouldRender()
        {
            return settings.active && settings.intensity.value > 0;
        }

        public void SetRenderStage(VolumetricLightRendererFeature.RenderStage renderStage)
        {
            this.renderStage = renderStage;
        }
    }
}
