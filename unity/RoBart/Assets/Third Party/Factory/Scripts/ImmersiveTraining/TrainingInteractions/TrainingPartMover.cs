using System;
using System.Collections;
using ImmersiveTraining.Management;
using ImmersiveTraining.StateHandling;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.InputSystem;

namespace ImmersiveTraining.TrainingInteractions
{
    public class TrainingPartMover : MonoBehaviour
    {
        private Camera _mainCamera;
        private GameObject _selectedObject;
        private bool _isDragging = false;
        private Collider _collider;
        private Transform _referencePlane;  //sets the plane about which the part will move and sets the minimum height
        private Vector3 _dragAxis; //this is the axis orthogonal to the plane that will be dragged on
        private Transform _startingTransform;
        private Transform _correctFinalTransform;
        private bool _isAnimating = false;
        private float _moveUpDistance;
        private float _duration;

        public enum DRAG_AXIS
        {
            UP,
            FORWARD,
            RIGHT
        }
    
        void Start()
        {
            _mainCamera = Camera.main;
            _isDragging = false;
            _collider = GetComponent<Collider>();

            EventManager.StartListening(EventTypes.STATE_CHANGED, arg0 => _mainCamera = Camera.main);
        }

        public void SetDragAxis(DRAG_AXIS axis)
        {
            switch (axis)
            {
                case DRAG_AXIS.UP:
                    _dragAxis = transform.up;
                    break;
                case DRAG_AXIS.FORWARD:
                    _dragAxis = transform.forward;
                    break;
                case DRAG_AXIS.RIGHT:
                    _dragAxis = transform.right;
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(axis), axis, null);
            }
        }

        void Update()
        {
            if (_isAnimating) return;
        
            // Detect mouse button press
            if (Mouse.current.leftButton.wasPressedThisFrame)
            {
                // Perform the raycast
                Vector2 mousePosition = Mouse.current.position.value;
                Ray ray = Camera.main.ScreenPointToRay(new Vector3(mousePosition.x, mousePosition.y, 0));
                RaycastHit hit;
                if (Physics.Raycast(ray, out hit))
                {
                    if (hit.collider.gameObject == this.gameObject)
                    {
                        _selectedObject = hit.collider.gameObject;
                        _selectedObject.transform.rotation = quaternion.identity; //to keep proper orientations regardless of how they're stored on the ground (may remove or set an a variable as needed)
                        _isDragging = true;
                    }
                }
            }

            // Dragging the object
            if (_isDragging && _selectedObject != null)
            {
                Vector2 mousePosition = Mouse.current.position.value;
                Ray ray = _mainCamera.ScreenPointToRay(new Vector3(mousePosition.x, mousePosition.y, 0));
                Plane dragPlane = (_referencePlane != null) ?  new Plane(_referencePlane.transform.forward, _referencePlane.transform.position) :  new Plane(_dragAxis, _selectedObject.transform.position);
                float dist;
                if (dragPlane.Raycast(ray, out dist))
                {
                    Vector3 hitPoint = ray.GetPoint(dist);
                    //selectedObject.transform.position = hitPoint - offset;
                    hitPoint = new Vector3(hitPoint.x, Mathf.Clamp(hitPoint.y, _referencePlane.transform.position.y, 3f) , hitPoint.z);
                    _selectedObject.transform.position = hitPoint;
                }
            }

            // Release the object
            if (Mouse.current.leftButton.wasReleasedThisFrame && _isDragging)
            {
                _isDragging = false;
                _selectedObject = null;
                EventManager.TriggerEvent(EventTypes.TRAINING_STATE_COMPLETION_CHECK, gameObject); //Could call this repeatedly in update if repeated checks were desired
            }
        }

        public void SetStateData(StateTrainingWithPass.TrainingData trainingData)
        {
            _referencePlane = trainingData.referencePlane;
            _startingTransform = trainingData.startingTransform;
            _correctFinalTransform = trainingData.correctFinalTransform;
            _moveUpDistance = trainingData.moveUpDistance;
            _duration = trainingData.duration;
        }
    
        public void ReturnToStartingPosition()
        {
            if (_isAnimating) return;
            StartCoroutine(ReturnToStartingPositionWithEasing());
        }

        private IEnumerator ReturnToStartingPositionWithEasing()
        {
            _isAnimating = true;
        
            if (_collider != null) _collider.enabled = false;
        
            Vector3 initialPosition = transform.position;
            Vector3 moveUpPosition = _startingTransform.position + Vector3.up * _moveUpDistance;

            // Phase 1: Return to Move Up Position
            yield return SmoothMove(transform, initialPosition, moveUpPosition, _duration / 4);

            // Phase 2: Return to Initial Position
            yield return SmoothMoveAndRotate(transform, transform.position, _startingTransform.position, transform.rotation, _startingTransform.rotation, _duration / 4);
        
            if (_collider != null) _collider.enabled = true;
        
            _isAnimating = false;
        }

        public void AutoPlayCurrenStep(Action onComplete)
        {
            if (_isAnimating)
            {
                onComplete?.Invoke();
                return;
            }
        
            StartCoroutine(AutoPlayCurrentStepWithEasing(onComplete));
        }

        private IEnumerator AutoPlayCurrentStepWithEasing(Action onComplete)
        {
            _isAnimating = true;

            if (_collider != null) _collider.enabled = false;

            Vector3 moveUpPosition = _startingTransform.position + Vector3.up * _moveUpDistance;

            // Phase 1: Move Up
            yield return SmoothMoveAndRotate(transform, _startingTransform.position, moveUpPosition, _startingTransform.rotation, quaternion.identity,  _duration);

            // Phase 2: Move to Target
            yield return SmoothMove(transform, moveUpPosition, _correctFinalTransform.position, _duration);
        
            // Phase 3: Return to Move Up Position
            yield return SmoothMove(transform, _correctFinalTransform.position, moveUpPosition, _duration / 2);

            // Phase 4: Return to Initial Position
            yield return SmoothMoveAndRotate(transform, moveUpPosition, _startingTransform.position, quaternion.identity, _startingTransform.rotation, _duration / 2);

            onComplete?.Invoke();
        
            if (_collider != null) _collider.enabled = true;
        
            _isAnimating = false;
        }
    
        public void AutoCompleteCurrenStep(Action onComplete)
        {
            if (_isAnimating)
            {
                onComplete?.Invoke();
                return;
            }
        
            StartCoroutine(AutoCompleteCurrentStepWithEasing(onComplete));
        }
    
        private IEnumerator AutoCompleteCurrentStepWithEasing(Action onComplete)
        {
            _isAnimating = true;

            if (_collider != null) _collider.enabled = false;

            Vector3 moveUpPosition = _startingTransform.position + Vector3.up * _moveUpDistance;

            // Phase 1: Move Up
            yield return SmoothMoveAndRotate(transform, _startingTransform.position, moveUpPosition, _startingTransform.rotation, quaternion.identity,  _duration);

            // Phase 2: Move to Target
            yield return SmoothMove(transform, moveUpPosition, _correctFinalTransform.position, _duration);
        
            EventManager.TriggerEvent(EventTypes.TRAINING_STATE_COMPLETION_CHECK, gameObject);
        
            onComplete?.Invoke();
        
            if (_collider != null) _collider.enabled = true;
        
            _isAnimating = false;
        }
    
        private IEnumerator SmoothMove(Transform objectToMove, Vector3 start, Vector3 end, float duration)
        {
            float elapsedTime = 0f;
            while (elapsedTime < duration)
            {
                float t = elapsedTime / duration;
                t = Mathf.SmoothStep(0, 1, t); // Ease in-out
                objectToMove.position = Vector3.Lerp(start, end, t);
                elapsedTime += Time.deltaTime;
                yield return null;
            }
            objectToMove.position = end; // Ensure it snaps to the exact end position.
        }

        private IEnumerator SmoothMoveAndRotate(Transform objectToMove, Vector3 start, Vector3 end, Quaternion startRotation, Quaternion endRotation, float duration)
        {
            float elapsedTime = 0f;
            while (elapsedTime < duration)
            {
                float t = elapsedTime / duration;
                t = Mathf.SmoothStep(0, 1, t); // Ease in-out
        
                // Interpolate position
                objectToMove.position = Vector3.Lerp(start, end, t);
        
                // Interpolate rotation
                objectToMove.rotation = Quaternion.Slerp(startRotation, endRotation, t);
        
                elapsedTime += Time.deltaTime;
                yield return null;
            }
    
            // Ensure the object snaps to the exact end position and rotation
            objectToMove.position = end;
            objectToMove.rotation = endRotation;
        }
    }
}
