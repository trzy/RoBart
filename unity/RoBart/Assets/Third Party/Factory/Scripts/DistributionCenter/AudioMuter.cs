using UnityEngine;
using UnityEngine.UI;

namespace DistributionCenter
{
    public class AudioMuter : MonoBehaviour
    {
        public Button muteToggleButton;
        private bool isMuted = false;

        void Start()
        {
            if (muteToggleButton != null)
                muteToggleButton.onClick.AddListener(ToggleAudio);
        }

        public void ToggleAudio()
        {
            isMuted = !isMuted;
            AudioListener.volume = isMuted ? 0f : 1f;
        }
    }
}