using UnityEngine;

namespace DistributionCenter
{
    public class wheelRotation : MonoBehaviour
    {
        public GameObject botObj;
        public GameObject[] Wheel_ARR;
        public float rotationSpeed = 100f;
        public float decelerationRate = 1f;
        public float easingRate = 5f;

        public float moveDirection = 0f;
        public float turnDirection = 0f;

        private float currentRotationSpeed = 0f;
        private Vector3 lastPosition;
        private float moveThreshold = 0.001f;

        void Start()
        {
            lastPosition = botObj.transform.position;
        }

        void Update()
        {
            Vector3 currentPosition = botObj.transform.position;
            float distanceMoved = Vector3.Distance(currentPosition, lastPosition);
            bool isMoving = distanceMoved > moveThreshold;

            bool isTurning = Mathf.Abs(turnDirection) > 0f;

            if (isMoving || isTurning)
            {
                currentRotationSpeed = Mathf.Lerp(currentRotationSpeed, rotationSpeed, Time.deltaTime * easingRate);
            }
            else
            {
                currentRotationSpeed = Mathf.Lerp(currentRotationSpeed, 0f, Time.deltaTime * decelerationRate);
            }

            lastPosition = currentPosition;

            RotateWheels();
        }

        void RotateWheels()
        {
            float direction = Mathf.Sign(moveDirection);

            if (direction == 0f && Mathf.Abs(turnDirection) > 0f)
                direction = Mathf.Sign(turnDirection) * 0.5f;

            foreach (GameObject wheel in Wheel_ARR)
            {
                if (wheel != null)
                    wheel.transform.Rotate(Vector3.forward * Time.deltaTime * currentRotationSpeed * direction);
            }
        }
    }
}