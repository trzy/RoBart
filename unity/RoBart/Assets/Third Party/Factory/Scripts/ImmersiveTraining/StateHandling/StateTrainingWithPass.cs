using System;
using System.Collections.Generic;
using ImmersiveTraining.Management;
using ImmersiveTraining.TrainingInteractions;
using UnityEngine;
using UnityEngine.Serialization;

namespace ImmersiveTraining.StateHandling
{
    public class StateTrainingWithPass : StateActivateAndDeactivateObjects, IMessageForModalPanel, IUseTimer
    {
        [SerializeField] private Material _instructionScreen;
        [SerializeField] private Texture _instructionTexture;
        [SerializeField] private Animator _instructionModelAnimator;
        [SerializeField] private String _animatorParameterForCurrentStepAnimation;
        [SerializeField] private GameObject _partToMove;
        [SerializeField] private GameObject _ghostPrefab;
        [SerializeField] private int _timeAllowedInSeconds = 35;
        public GameObject PartToMove => _partToMove;
        public bool CountsDown { get => !TrainingTypeManager.Instance.IsTrainingMode; }    
        public int TimeAllowedInSeconds { get => _timeAllowedInSeconds; set => _timeAllowedInSeconds = value; }

        [SerializeField] private Transform _referencePlane;
        [SerializeField] private TrainingPartMover.DRAG_AXIS _partToMoveVirtualPlaneNormalAxis;
        [SerializeField] private Transform _originalPartToMoveAssembledTransform;
        [SerializeField] private float _distanceToConsiderCorrect = 0.1f;
        [SerializeField] private string _messageForModalPanel = "Training Step Complete!";
        [SerializeField] private bool _shouldPartsBeParentedAfterStepComplete = false;

        [FormerlySerializedAs("moveUpDistance")]
        [Header("Autoplay Demonstration Values")]
        [SerializeField] private float _moveUpDistance = 2f; // Distance to move up.
        [FormerlySerializedAs("duration")] [SerializeField] private float _duration = 2f; // Duration for the movement phases.
    
        private bool _isAutoPlaying;

        private GameObject _cachedStartingTransform;
        private GameObject _cachedGhostPart;
        private TrainingData _trainingData;
    
        public class TrainingData
        {
            public Transform referencePlane;
            public Transform startingTransform;
            public Transform correctFinalTransform;
            public float moveUpDistance;
            public float duration;
        }
    
        private void Awake()
        {
            _cachedStartingTransform = new GameObject();
            _cachedStartingTransform.name = gameObject.name + "startingTransform";
            _cachedStartingTransform.transform.position = _partToMove.transform.position;
            _cachedStartingTransform.transform.rotation = _partToMove.transform.rotation;
        
            _trainingData = new TrainingData()
            {
                referencePlane = _referencePlane,
                startingTransform = _cachedStartingTransform.transform,
                correctFinalTransform = _originalPartToMoveAssembledTransform,
                moveUpDistance = _moveUpDistance,
                duration = _duration
            };
        }

        public override void ActivateState(List<GameObject> _activatedByStateObjects)
        {
            base.ActivateState(_activatedByStateObjects);

            if (_instructionModelAnimator == null)
            {
                _instructionScreen.mainTexture = _instructionTexture;
            }
            else
            {
                _instructionModelAnimator.SetTrigger(_animatorParameterForCurrentStepAnimation);
            }
        
            PartToMove.transform.position = _trainingData.startingTransform.position;

            if (PartToMove.GetComponent<TrainingPartMover>() == null) PartToMove.AddComponent<TrainingPartMover>();
            if (_referencePlane != null)
            {
                PartToMove.GetComponent<TrainingPartMover>().SetStateData(GetTrainingData());
            }
            else PartToMove.GetComponent<TrainingPartMover>().SetDragAxis(_partToMoveVirtualPlaneNormalAxis);
        
            EventManager.StartListening(EventTypes.AUTOPLAY_STATE_DEMONSTRATION, AutoplayStateDemo);
            EventManager.StartListening(EventTypes.TRAINING_STATE_COMPLETION_CHECK, CheckForStateCompletion);

            EnableGhostPart();
        }

        private void EnableGhostPart()
        {
            if (TrainingTypeManager.Instance.IsTrainingMode && _cachedGhostPart == null)
            {
                _cachedGhostPart = Instantiate(_ghostPrefab, _originalPartToMoveAssembledTransform.position, _originalPartToMoveAssembledTransform.rotation);
            }
        }

        public override void DeactivateState()
        {
            if (_cachedGhostPart != null) DestroyImmediate(_cachedGhostPart);
        
            EventManager.StopListening(EventTypes.AUTOPLAY_STATE_DEMONSTRATION, AutoplayStateDemo);
            EventManager.StopListening(EventTypes.TRAINING_STATE_COMPLETION_CHECK, CheckForStateCompletion);
            base.DeactivateState();
        }

        private void CheckForStateCompletion(GameObject movingPart)
        {
            float distanceToSnapPoint = Vector3.Distance(PartToMove.transform.position, _originalPartToMoveAssembledTransform.position);

            if (distanceToSnapPoint < _distanceToConsiderCorrect)
            {
                PartToMove.transform.position = _originalPartToMoveAssembledTransform.position;
                if (_shouldPartsBeParentedAfterStepComplete) PartToMove.transform.parent = _originalPartToMoveAssembledTransform;
            
                Destroy(PartToMove.GetComponent<TrainingPartMover>());
                BoxCollider boxCollider = PartToMove.GetComponent<BoxCollider>();
                if (boxCollider == null)
                    Debug.Log("Box Collider Not Found on Part to Move");
                else boxCollider.enabled = false;
            
                EventManager.TriggerEvent(EventTypes.POP_MODAL_PANEL_WITH_MESSAGE_ON_OBJECT, gameObject);
                EventManager.TriggerEvent(EventTypes.TRAINING_STATE_CRITERIA_REACHED, gameObject);
            }
            else
            {
                movingPart.GetComponent<TrainingPartMover>().ReturnToStartingPosition();
            }
        }

        public string MessageForModal()
        {
            return _messageForModalPanel;
        }
    
        private void AutoplayStateDemo(GameObject arg0)
        {
            if (_isAutoPlaying) return;

            _isAutoPlaying = true;

            PartToMove.GetComponent<TrainingPartMover>().AutoPlayCurrenStep(onComplete: () => _isAutoPlaying =false);
        }

        public void AutoCompleteState()
        {
            if (_isAutoPlaying) return;

            _isAutoPlaying = true;

            PartToMove.GetComponent<TrainingPartMover>().AutoCompleteCurrenStep(onComplete: () => _isAutoPlaying =false);
        }

        public TrainingData GetTrainingData()
        {
            return _trainingData;
        }
    }
}
