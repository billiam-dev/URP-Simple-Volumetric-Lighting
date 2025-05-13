using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace Billiam.Game.Rendering
{
    public class VolumetricLightRendererFeature : ScriptableRendererFeature
    {
        public enum RenderStage
        {
            Raymarch,
            Blur,
            Composit
        }

        [SerializeField]
        private RenderStage debugRenderStage = RenderStage.Composit;

        private VolumetricLightRenderPass pass;

        public override void Create()
        {
            name = "Volumetric Lighting";
            pass = new VolumetricLightRenderPass();
        }

        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            base.SetupRenderPasses(renderer, renderingData);

            if (pass != null)
            {
                pass.SetRenderStage(debugRenderStage);
            }
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(pass);
        }

        protected override void Dispose(bool disposing)
        {
            pass.Dispose();
        }
    }
}
