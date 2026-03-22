using UnityEngine;

namespace ImmersiveTraining.Management
{
    public class ResetTraining : MonoBehaviour
    {
        public void TriggerTrainingReset()
        {
            EventManager.TriggerEvent(EventTypes.RESET_TRAINING, gameObject);
        }
    }
}
