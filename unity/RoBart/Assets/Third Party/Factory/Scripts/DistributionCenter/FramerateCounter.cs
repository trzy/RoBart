using UnityEngine;
using UnityEngine.UI;

namespace DistributionCenter
{
    public class FramerateCounter : MonoBehaviour
    {
        public Text fpsText;
        private float deltaTime = 0.0f;
        private float fpsUpdateInterval = 0.5f;

        void Update()
        {
            deltaTime += (Time.unscaledDeltaTime - deltaTime) * 0.1f;

            if (fpsUpdateInterval > 0)
            {
                fpsUpdateInterval -= Time.unscaledDeltaTime;
                if (fpsUpdateInterval <= 0)
                {
                    int fps = Mathf.RoundToInt(1.0f / deltaTime);
                    fpsText.text = fps + "FPS";
                    fpsUpdateInterval = 0.5f;
                }
            }
        }
    }
}