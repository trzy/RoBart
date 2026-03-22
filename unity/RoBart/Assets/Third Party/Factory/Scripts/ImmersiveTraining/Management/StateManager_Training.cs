using System.Collections.Generic;
using System.Linq;
using ImmersiveTraining.StateHandling;
using UnityEngine;

namespace ImmersiveTraining.Management
{
    public class StateManager_Training : StateManager
    {
        private List<GameObject> _activatedByStateObjects = new List<GameObject>();

        void Start()
        {
            FindAllStateDrivenObjects();
        
            EventManager.StartListening(EventTypes.TRAINING_STATE_CRITERIA_REACHED, IncrementTrainingState);
            EventManager.StartListening(EventTypes.RESET_TRAINING, (GameObject obj) => SetStateToIndex(0));

            if (_stateData.Count != 0)
            {
                _stateData[_stateIndex].ActivateState(_activatedByStateObjects);
                EventManager.TriggerEvent(EventTypes.STATE_CHANGED, this.gameObject);
            }
        }

        private void FindAllStateDrivenObjects()
        {
            ActivatedByState[] _activatedByStateObjectsByType = GameObject.FindObjectsByType<ActivatedByState>(FindObjectsInactive.Include, FindObjectsSortMode.None);

            foreach (var activatedByStateObject in _activatedByStateObjectsByType)
            {
                _activatedByStateObjects.Add(activatedByStateObject.gameObject);
            }
        }

        private void IncrementTrainingState(GameObject trainingStateDataObject)
        {
            if (_stateIndex == _stateData.Count - 1)
            {
                _stateData[_stateIndex].DeactivateState();
                EventManager.TriggerEvent(EventTypes.TRAINING_COMPLETE, gameObject);
            }
            else IncrementState();
        }

        public override void IncrementState()
        {
            SetStateToIndex(Mathf.Clamp(_stateIndex + 1, 0, _stateData.Count - 1));
        }
    
        public override void DecrementState()
        {
            SetStateToIndex(Mathf.Clamp(_stateIndex - 1, 0, _stateData.Count - 1));
        }
    
        private void SetStateToIndex(int incomingIndex)
        {
            //if(incomingIndex == _stateIndex) return;
        
            _stateData[_stateIndex].DeactivateState();
            _stateIndex = incomingIndex;
            _stateData[_stateIndex].ActivateState(_activatedByStateObjects);
        
            EventManager.TriggerEvent(EventTypes.STATE_CHANGED, this.gameObject);
        }

        public void ReActivateState()
        {
            SetStateToIndex(_stateIndex);
        }

        public string GetCurrentStateInfoText()
        {
            return _stateData[_stateIndex].GetInfoMessage();
        }

        public GameObject GetCurrentTrainingPartToMove()
        {
            if (_stateData[_stateIndex] is not StateTrainingWithPass) return null;

            StateTrainingWithPass currentTrainingStep = (StateTrainingWithPass)_stateData[_stateIndex];
            return currentTrainingStep.PartToMove;
        }

        public string GetStateTrackerText()
        {
            return $"{_stateIndex + 1} / {_stateData.Count}";
        }

        public int GetStateCount()
        {
            return _stateData.Count();
        }
    
        public bool CheckIfObjectShouldBeActiveInCurrentState(GameObject objectToCheckFor)
        {
            if (_stateData.Count == 0) return true;
            return _stateData[_stateIndex].MayObjectBeActiveInThisState(objectToCheckFor);
        }
    
        private void ResetStateIndex(GameObject callingObject)
        {
            _stateIndex = 0;
        }

        public List<StateTrainingWithPass> GetTrainingStates()
        {
            List<StateTrainingWithPass> trainingStates = new List<StateTrainingWithPass>();

            for (int i = 0; i < _stateData.Count; i++)
            {
                if (_stateData[i] is StateTrainingWithPass) trainingStates.Add((StateTrainingWithPass)_stateData[i]);
            }

            return trainingStates;
        }
    }
}
