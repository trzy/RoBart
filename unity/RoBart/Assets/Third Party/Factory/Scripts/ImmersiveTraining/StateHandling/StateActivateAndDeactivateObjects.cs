using System.Collections.Generic;
using ImmersiveTraining.Management;
using UnityEngine;

namespace ImmersiveTraining.StateHandling
{
    public class StateActivateAndDeactivateObjects : StateData
    {
        [SerializeField] protected List<GameObject> _objectsToActivate;

        public override void ActivateState(List<GameObject> _activatedByStateObjects)
        {
            base.ActivateState(_activatedByStateObjects);
            ActivateAllObjects(_activatedByStateObjects);
            DeActivateAllObjects(_activatedByStateObjects);
        }

        private void ActivateAllObjects(List<GameObject> _activatedByStateObjects)
        {
            for (int i = 0; i < _objectsToActivate.Count; i++)
            {
                if (_objectsToActivate[i].GetComponent<HideInsteadOfDeactivate>() != null)
                {
                    foreach (MeshRenderer meshRenderer in _objectsToActivate[i].GetComponentsInChildren<MeshRenderer>())
                    {
                        meshRenderer.enabled = true;
                    }

                    foreach (Collider collider in _objectsToActivate[i].GetComponentsInChildren<Collider>())
                    {
                        collider.enabled = true;
                    }
                }
                else _objectsToActivate[i].SetActive(true);
                if (!_activatedByStateObjects.Contains(_objectsToActivate[i])) Debug.LogWarning($"An object {_objectsToActivate[i].name} does not have the ActivatedByState tag component and will not be disabled properly by other states"); 
            }
        
            EventManager.TriggerEvent(EventTypes.STATE_ACTIVATION_EVENT, gameObject);
        }
    
        private void DeActivateAllObjects(List<GameObject> _activatedByStateObjects)
        {
            for (int i = 0; i < _activatedByStateObjects.Count; i++)
            {
                if (_objectsToActivate.Contains(_activatedByStateObjects[i])) continue; //don't disable objects that should remain on
            
                if (_activatedByStateObjects[i].GetComponent<HideInsteadOfDeactivate>() != null)
                {
                    foreach (MeshRenderer meshRenderer in _activatedByStateObjects[i].GetComponentsInChildren<MeshRenderer>())
                    {
                        meshRenderer.enabled = false;
                    }

                    foreach (Collider collider in _activatedByStateObjects[i].GetComponentsInChildren<Collider>())
                    {
                        collider.enabled = false;
                    }
                }
                else _activatedByStateObjects[i].SetActive(false);
            }
        
            EventManager.TriggerEvent(EventTypes.STATE_DEACTIVATION_EVENT, gameObject);
        }

        public override bool MayObjectBeActiveInThisState(GameObject targetObject)
        {
            return _objectsToActivate.Contains(targetObject);
        }
    }
}
