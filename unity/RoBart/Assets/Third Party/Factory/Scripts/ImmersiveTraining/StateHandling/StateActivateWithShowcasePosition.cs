using System.Collections.Generic;
using ImmersiveTraining.Management;
using UnityEngine;

namespace ImmersiveTraining.StateHandling
{
    public class StateActivateWithShowcasePosition : StateActivateAndDeactivateObjects, IUseTimer
    {
        [SerializeField] private GameObject _gameObjectToShowcase;
        [SerializeField] private Transform _showcaseTransform;
        [SerializeField] private int _timeAllowedInSeconds = 35;
        private Vector3 _startingPosition;
        private Quaternion _startingRotation;

        public bool CountsDown { get => !TrainingTypeManager.Instance.IsTrainingMode; }
        public int TimeAllowedInSeconds { get => _timeAllowedInSeconds; set => _timeAllowedInSeconds = value; }

        public void Start()
        {
            _startingPosition = _gameObjectToShowcase.transform.position;
            _startingRotation = _gameObjectToShowcase.transform.rotation;
        }

        public override void ActivateState(List<GameObject> _activatedByStateObjects)
        {
            base.ActivateState(_activatedByStateObjects);
            _gameObjectToShowcase.SetActive(true);
            _gameObjectToShowcase.transform.position = _showcaseTransform.position;
            _gameObjectToShowcase.transform.rotation = _showcaseTransform.rotation;
        }

        public override void DeactivateState()
        {
            base.DeactivateState();
            _gameObjectToShowcase.transform.position = _startingPosition;
            _gameObjectToShowcase.transform.rotation = _startingRotation;
        }
    }
}
