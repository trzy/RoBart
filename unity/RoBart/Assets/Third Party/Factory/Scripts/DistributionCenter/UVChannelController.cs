using UnityEngine;

namespace DistributionCenter
{
    public class UVChannelSwitcher : MonoBehaviour
    {
        public Renderer targetRenderer;
        public int uvChannel = 0;

        void Start()
        {
            if (targetRenderer == null)
                return;

            targetRenderer.material = new Material(targetRenderer.material);

            UpdateUVChannel();
        }

        public void UpdateUVChannel()
        {
            if (targetRenderer != null)
            {
                targetRenderer.material.SetFloat("_UVChannel", uvChannel);
            }
        }

        public void SetUVChannel(int channel)
        {
            uvChannel = channel;
            UpdateUVChannel();
        }
    }
}