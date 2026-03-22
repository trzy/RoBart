using System.Collections;
using DistributionCenter;
using ImmersiveTraining.Management;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;
using WaitForSeconds = UnityEngine.WaitForSeconds;

namespace ImmersiveTraining.StateHandling
{
    public class AttractMode : MonoBehaviour
    {
        [SerializeField] private StateManager_Training _stateManagerTraining;
        [SerializeField] private CameraSwitcher _cameraSwitcher;
        [SerializeField] private TrainingTypeManager _trainingTypeManager;
    
        public float timeToStartAttractModeInSeconds = 10f;
        public float timeToWaitBetweenAttractModeActions = 5f;

        private bool _isAttractMode = false;
        private float _currentTimeToStartAttractMode;
        private Coroutine _runningAttractMode;

        public bool IsAttractMode
        {
            get => _isAttractMode;
            set
            {
                _isAttractMode = value;
                if (_isAttractMode) _runningAttractMode = StartCoroutine(RunAttractMode());
                else
                {
                    if (_runningAttractMode != null) StopCoroutine(_runningAttractMode);
                    ResetTraining();
                }
            }
        }
    
        void Start()
        {
            _stateManagerTraining = FindFirstObjectByType<StateManager_Training>();
            _cameraSwitcher = FindFirstObjectByType<CameraSwitcher>();
            _trainingTypeManager = FindFirstObjectByType<TrainingTypeManager>();
            _currentTimeToStartAttractMode = timeToStartAttractModeInSeconds;
            _isAttractMode = false;

            InputSystem.onEvent += OnInputEvent;
        }

        private IEnumerator RunAttractMode()
        {
            Debug.Log("Run Attract Mode");
            WaitForSeconds waitForSeconds = new WaitForSeconds(timeToWaitBetweenAttractModeActions);
        
            yield return StartCoroutine(ResetTraining());

            for (int i = 0; i < _stateManagerTraining.GetStateCount(); i++)
            {
                StateTrainingWithPass stateTrainingWithPass = (StateTrainingWithPass)_stateManagerTraining.CurrentState;
                stateTrainingWithPass.AutoCompleteState();
                yield return waitForSeconds;
            }
        }

        private IEnumerator ResetTraining()
        {
            EventManager.TriggerEvent(EventTypes.RESET_TRAINING, gameObject);

            yield return new WaitForSeconds(1);
        
            _trainingTypeManager.EnableTrainingMode();
        }

        public void Update()
        {
            if (Keyboard.current.aKey.wasPressedThisFrame)
            {
                IsAttractMode = !IsAttractMode;
            }

            if (IsAttractMode) return;  //if in attract mode don't do the countdown
        
            _currentTimeToStartAttractMode -= Time.deltaTime;

            if (_currentTimeToStartAttractMode <= 0f)
            {
                TimerExpired();
            }
        }

        private void OnInputEvent(InputEventPtr eventPtr, InputDevice device)
        {
            ResetTimer();
        }

        private void ResetTimer()
        {
            _currentTimeToStartAttractMode = timeToStartAttractModeInSeconds;
        }

        private void TimerExpired()
        {
            IsAttractMode = true;
        }
    }
}
