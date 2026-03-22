using ImmersiveTraining.Management;
using UnityEngine;

namespace ImmersiveTraining.TrainingInteractions
{
   public class FireAutoPlayEvent : MonoBehaviour
   {
      public void TriggerAutoPlay()
      {
         EventManager.TriggerEvent(EventTypes.AUTOPLAY_STATE_DEMONSTRATION, gameObject);
      }
   }
}
