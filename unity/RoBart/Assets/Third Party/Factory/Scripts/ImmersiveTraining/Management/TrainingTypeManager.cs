using System.Collections.Generic;
using ImmersiveTraining.StateHandling;
using ImmersiveTraining.TrainingInteractions;
using UnityEngine;
using UnityEngine.InputSystem;

namespace ImmersiveTraining.Management
{
    public class TrainingTypeManager : Singleton<TrainingTypeManager>
    {
        public GameObject[] objectsUsedForTrainingMode;
        public bool startInTrainingMode;
        public bool IsTrainingMode => _isTrainingMode;
    
        private StateManager_Training _stateManager_Training;
        private List<StateTrainingWithPass> _trainingStates;
    
        private bool _isTrainingMode;

        private void Start()
        {
            _isTrainingMode = startInTrainingMode;
            _stateManager_Training = FindFirstObjectByType<StateManager_Training>();

            _trainingStates = _stateManager_Training.GetTrainingStates();
        
            SetTrainingModeObjectsActive(_isTrainingMode);
        
            EventManager.StartListening(EventTypes.RESET_TRAINING, ResetTraining);
            EventManager.StartListening(EventTypes.ALLOWED_TIME_EXPIRED, DisableAllMovableObjectColliders);
        }
    
        private void Update()
        {
            if (Keyboard.current.tKey.wasPressedThisFrame)
            {
                EnableTrainingMode();
            }
        
            if (Keyboard.current.fKey.wasPressedThisFrame)
            {
                EnableIndependentMode();
            }

            if (Keyboard.current.rKey.wasPressedThisFrame)
            {
                EventManager.TriggerEvent(EventTypes.RESET_TRAINING, gameObject);
            }

            if (Keyboard.current.bKey.wasPressedThisFrame)
            {
                ToggleTrainingMode();
            }
        }

        public void ToggleTrainingMode()
        {
            _isTrainingMode = !_isTrainingMode;
            SetTrainingModeObjectsActive(_isTrainingMode);
            _stateManager_Training.ReActivateState();
        }

        public void EnableTrainingMode()
        {
            _isTrainingMode = true;
            SetTrainingModeObjectsActive(_isTrainingMode);
            _stateManager_Training.ReActivateState();
        }

        public void EnableTrainingModeWithReset()
        {
            EventManager.TriggerEvent(EventTypes.RESET_TRAINING, gameObject);
        
            Invoke(nameof(EnableTrainingMode), 1.1f);
        }
    
        public void EnableIndependentMode()
        {
            _isTrainingMode = false;
            SetTrainingModeObjectsActive(_isTrainingMode);
        }

        void SetTrainingModeObjectsActive(bool trainingIsActive)
        {
            for (int i = 0; i < objectsUsedForTrainingMode.Length; i++)
            {
                objectsUsedForTrainingMode[i].SetActive(trainingIsActive);
            }

            if (trainingIsActive)
            {
                //Remove all the drag and drops if frustration mode was on before
                for (int i = 0; i < _trainingStates.Count; i++)
                {
                    TrainingPartMover goDrag = _trainingStates[i].PartToMove.GetComponent<TrainingPartMover>();
                    if (goDrag != null && _trainingStates[i].PartToMove != _stateManager_Training.GetCurrentTrainingPartToMove()) Destroy(goDrag); //if its there and its not the current training state remove it
                }
            }
            else
            {
                //Make all objects drag-able in frustration mode 
                for (int i = 0; i < _trainingStates.Count; i++)
                {
                    TrainingPartMover goDrag = _trainingStates[i].PartToMove.GetComponent<TrainingPartMover>();
                    if (goDrag == null)
                    {
                        TrainingPartMover newDrag = _trainingStates[i].PartToMove.AddComponent<TrainingPartMover>();
                        newDrag.SetStateData(_trainingStates[i].GetTrainingData());
                    }
                }
            }
            EventManager.TriggerEvent(EventTypes.RESET_TIMER, gameObject);
        }

        private void ResetTraining(GameObject arg0)
        {
            _isTrainingMode = false;
            SetTrainingModeObjectsActive(_isTrainingMode);
        
            for (int i = 0; i < _trainingStates.Count; i++)
            {
                _trainingStates[i].PartToMove.GetComponent<TrainingPartMover>().ReturnToStartingPosition();
            }
        }

        private void DisableAllMovableObjectColliders(GameObject arg0)
        {
            for (int i = 0; i < _trainingStates.Count; i++)
            {
                _trainingStates[i].PartToMove.GetComponent<BoxCollider>().enabled = false;
            }
        }
    }
}
