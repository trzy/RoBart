using UnityEngine;

namespace ImmersiveTraining.Management
{
    public class TrainingTimeOutHandler : MonoBehaviour
    {
        public GameObject timeOutPanel;
        public GameObject instructionPanel;

        private void Start()
        {
            EventManager.StartListening(EventTypes.ALLOWED_TIME_EXPIRED, HandleTrainingTimeExpiration);
        }

        private void HandleTrainingTimeExpiration(GameObject arg0)
        {
            timeOutPanel.SetActive(true);
            instructionPanel.SetActive(false); //close it just to be sure, may need to reset its toggle too
        }
    }
}
