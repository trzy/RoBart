using UnityEngine;

namespace ImmersiveTraining.Management
{
    public class StaticCameraLocationManager : MonoBehaviour
    {
        public Transform[] staticCameraTransforms;
        public GameObject cameraObject;
        public float timeBetweenLocations;
    
        private int _currentIndex = 0; 
        private bool _isTransitioning = false;
        private float _transitionTime = 0.0f;
        private Vector3 startPosition;
        private Quaternion startRotation;
        private Vector3 targetPosition;
        private Quaternion targetRotation;

        void Start()
        {
            EventManager.StartListening(EventTypes.NETWORK_AVATAR_SPAWNED, (triggerObject) => cameraObject = triggerObject);
        }

        void Update()
        {
            if (!_isTransitioning)
            {
                if (Input.GetKeyDown(KeyCode.RightArrow)) 
                {
                    MoveToNextLocation();
                }
                else if (Input.GetKeyDown(KeyCode.LeftArrow))
                {
                    MoveToPreviousLocation();
                }
            }
            else
            {
                _transitionTime += Time.deltaTime;

                float t = Mathf.Clamp01(_transitionTime / timeBetweenLocations);
                cameraObject.transform.position = Vector3.Lerp(startPosition, targetPosition, t);
                cameraObject.transform.rotation = Quaternion.Slerp(startRotation, targetRotation, t);
            
                if (t >= 1.0f)
                {
                    _isTransitioning = false;
                }
            }
        }

        private void MoveToNextLocation()
        {
            _currentIndex = (_currentIndex + 1) % staticCameraTransforms.Length; // Wrap around
            StartTransitionToLocation(_currentIndex);
        }
    
        private void MoveToPreviousLocation()
        {
            _currentIndex = (_currentIndex - 1 + staticCameraTransforms.Length) % staticCameraTransforms.Length; // Wrap around
            StartTransitionToLocation(_currentIndex);
        }

        private void StartTransitionToLocation(int index)
        {
            if (staticCameraTransforms.Length > 0 && cameraObject != null)
            {
                startPosition = cameraObject.transform.position;
                startRotation = cameraObject.transform.rotation;
                targetPosition = staticCameraTransforms[index].position;
                targetRotation = staticCameraTransforms[index].rotation;

                _isTransitioning = true;
                _transitionTime = 0.0f;
            }
        }
    }
}