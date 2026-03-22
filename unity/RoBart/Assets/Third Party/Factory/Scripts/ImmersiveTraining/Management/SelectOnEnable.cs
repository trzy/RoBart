using UnityEngine;
using UnityEngine.EventSystems;

namespace ImmersiveTraining.Management
{
    public class SelectOnEnable : MonoBehaviour
    {
        private void OnEnable()
        {
            EventSystem eventSystem = FindObjectOfType<EventSystem>();
        
            eventSystem.SetSelectedGameObject(this.gameObject);
        }
    }
}
