using System.Collections.Generic;
using ImmersiveTraining.Management;
using UnityEngine;

namespace ImmersiveTraining.StateHandling
{
    public class StateData : MonoBehaviour
    {
        [SerializeField] private string _stepName;
        [TextArea]
        [SerializeField] private string _infoMessage;

        protected IUseTimer timer;

        public string StateName { get => string.IsNullOrEmpty(_stepName) ? gameObject.name : _stepName; set => _stepName = value; }

        public virtual void ActivateState(List<GameObject> _activatedByStateObjects)
        {
            timer = this as IUseTimer;
            if (timer != null)
            {
                EventManager.TriggerEvent(EventTypes.START_TIMER, gameObject);
            }
        }

        public virtual void DeactivateState()
        {
            timer = this as IUseTimer;
            if (timer != null)
            {
                EventManager.TriggerEvent(EventTypes.STOP_TIMER, gameObject);
            }
        }

        public string GetInfoMessage()
        {
            return _infoMessage;
        }

        public virtual bool MayObjectBeActiveInThisState(GameObject targetObject)
        {
            return false;
        }
    }
}