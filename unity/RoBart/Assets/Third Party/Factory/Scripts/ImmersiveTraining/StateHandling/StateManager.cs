using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace ImmersiveTraining.StateHandling
{
    public class StateManager : MonoBehaviour
    {
        [SerializeField] protected List<StateData> _stateData;

        protected int _stateIndex;
        public int StateIndex { get => _stateIndex; }
        public StateData CurrentState { get => _stateData[_stateIndex]; }
    
        public virtual void IncrementState()
        {
        }

        public virtual void DecrementState()
        {
        }

        public string GetCurrentStateInfoText()
        {
            return _stateData[_stateIndex].GetInfoMessage();
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
    }
}
