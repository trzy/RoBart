using ImmersiveTraining.Management;
using UnityEngine;

namespace ImmersiveTraining.TrainingInteractions
{
    [RequireComponent(typeof(AudioSource))]
    public class PlaySoundOnTrainingStepComplete : MonoBehaviour
    {
        private AudioSource _audioSource;
    
        void Start()
        {
            _audioSource = GetComponent<AudioSource>();
            EventManager.StartListening(EventTypes.TRAINING_STATE_CRITERIA_REACHED, PlaySound);
        }

        private void PlaySound(GameObject arg0)
        {
            _audioSource.Play();
        }
    }
}
