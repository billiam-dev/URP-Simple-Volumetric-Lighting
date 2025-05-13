using UnityEngine;

[ExecuteAlways]
public class SceneMainLight : MonoBehaviour
{
    /*
     * Your main light should be the most intense directional light in the scene.
     * This script can be used to update global properties such as the light direction, which can be used by various shader effects.
    */
    [SerializeField]
    private Light mainLight;

    private void Update()
    {
        if (mainLight)
        {
            Shader.SetGlobalVector("_LightDirection", mainLight.transform.forward);
        }
    }

#if UNITY_EDITOR
    void OnValidate()
    {
        if (!mainLight)
        {
            Debug.LogWarning("No light assigned");
            return;
        }

        if (LightIsValid())
        {
            mainLight.gameObject.isStatic = true;
        }
        else
        {
            Debug.LogWarning("Main light must be of type 'Directional'!");
        }
    }

    bool LightIsValid()
    {
        return mainLight.type == LightType.Directional;
    }
#endif
}
