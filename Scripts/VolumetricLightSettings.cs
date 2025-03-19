using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace JARcraft.Game.Rendering
{
    [System.Serializable, VolumeComponentMenu("Post-processing/Volumetric Light")]
    public class VolumetricLightSettings : VolumeComponent, IPostProcessComponent
    {
        [Header("Raymarch")]
        public FloatParameter scatteringPower = new ClampedFloatParameter(0.04f, 0f, 1f);
        public ClampedIntParameter maxSteps = new ClampedIntParameter(25, 25, 75);
        public FloatParameter maxDistance = new FloatParameter(50);
        public FloatParameter jitter = new FloatParameter(2);

        [Header("Downsample")]
        public ClampedIntParameter downsampling = new ClampedIntParameter(4, 1, 4);
        public ClampedIntParameter iterations = new ClampedIntParameter(3, 1, 10);
        public ClampedFloatParameter blend = new ClampedFloatParameter(1, 0, 1);

        [Header("Composite")]
        public FloatParameter intensity = new FloatParameter(0);
        
        public bool IsActive()
        {
            return active;
        }

        public bool IsTileCompatible()
        {
            return false;
        }
    }
}
