using UnityEngine;
using UnityEngine.AI;
using UnityEngine.InputSystem;

namespace DistributionCenter
{
    public class AgentMovement : MonoBehaviour
    {
        public float rotationSpeed = 90f;
        public float moveSpeed = 3.5f;
        public float controlTimeout = 5f;

        [Header("Audio Controls")]
        public AudioSource moveAudio;
        public float fadeInSpeed = 2f;
        public float fadeOutSpeed = 2f;
        public float maxVolume = 1f;

        private NavMeshAgent agent;
        private wheelRotation wheelRot;
        private RandomAgentMovement agentManager;
        private int agentIndex = -1;

        private bool manualControl = false;
        private float controlTimer = 0f;
        private bool shouldPlayMoveAudio = false;

        void Start()
        {
            agent = GetComponent<NavMeshAgent>();
            wheelRot = GetComponent<wheelRotation>();
            agentManager = GetComponentInParent<RandomAgentMovement>();
            agentIndex = FindAgentIndex();

            SetupAudio(moveAudio);
        }

        void SetupAudio(AudioSource audio)
        {
            if (audio != null)
            {
                audio.loop = true;
                audio.playOnAwake = false;
                audio.volume = 0f;
            }
        }

        void Update()
        {
            if (agent == null || !agent.enabled) return;

            float forward = 0f;
            float rotate = 0f;

            bool w = Keyboard.current.wKey.isPressed;
            bool s = Keyboard.current.sKey.isPressed;
            bool a = Keyboard.current.aKey.isPressed;
            bool d = Keyboard.current.dKey.isPressed;

            if (w) forward = 1f;
            if (s) forward = -1f;
            if (a) rotate = -1f;
            if (d) rotate = 1f;

            bool isControlling = (w || s || a || d);
            bool isMoving = false;

            if (isControlling)
            {
                if (!manualControl)
                {
                    manualControl = true;
                    agent.ResetPath();
                    agent.updatePosition = false;
                    agent.updateRotation = false;
                }

                controlTimer = 0f;

                if (rotate != 0f)
                    transform.Rotate(Vector3.up * rotate * rotationSpeed * Time.deltaTime);

                if (forward != 0f)
                {
                    Vector3 move = transform.forward * forward * moveSpeed * Time.deltaTime;
                    Vector3 nextPos = transform.position + move;

                    Vector3 navMeshPos;
                    if (GetValidNavMeshPosition(nextPos, out navMeshPos))
                    {
                        transform.position = navMeshPos;
                        isMoving = true;
                    }
                }

                if (wheelRot != null)
                {
                    wheelRot.moveDirection = forward;
                    wheelRot.turnDirection = rotate;
                }
            }
            else if (manualControl)
            {
                controlTimer += Time.deltaTime;

                if (controlTimer >= controlTimeout)
                {
                    manualControl = false;

                    Vector3 navMeshPos;
                    if (GetValidNavMeshPosition(transform.position, out navMeshPos))
                    {
                        agent.Warp(navMeshPos);
                    }

                    agent.updatePosition = true;
                    agent.updateRotation = true;
                    agent.isStopped = false;

                    if (wheelRot != null)
                    {
                        wheelRot.moveDirection = 0f;
                        wheelRot.turnDirection = 0f;
                    }

                    if (agentManager != null && agentIndex != -1)
                    {
                        agentManager.ForceAssignNewTarget(agent, agentIndex);
                    }
                }
                else
                {
                    if (wheelRot != null)
                    {
                        wheelRot.moveDirection = 0f;
                        wheelRot.turnDirection = rotate;
                    }
                }
            }
            else
            {
                if (wheelRot != null)
                {
                    wheelRot.moveDirection = 0f;
                    wheelRot.turnDirection = 0f;
                }
            }

            if (!manualControl && agent.velocity.sqrMagnitude > 0.01f)
            {
                isMoving = true;
            }

            shouldPlayMoveAudio = isMoving;
            UpdateAudio(moveAudio, shouldPlayMoveAudio);
        }

        void UpdateAudio(AudioSource source, bool shouldPlay)
        {
            if (source == null) return;

            float targetVolume = shouldPlay ? maxVolume : 0f;
            float fadeSpeed = shouldPlay ? fadeInSpeed : fadeOutSpeed;

            if (shouldPlay)
            {
                if (!source.isPlaying)
                    source.Play();

                source.volume = Mathf.Lerp(source.volume, targetVolume, Time.deltaTime * fadeSpeed);
            }
            else
            {
                source.volume = Mathf.Lerp(source.volume, 0f, Time.deltaTime * fadeSpeed);

                if (source.volume < 0.01f && source.isPlaying)
                    source.Stop();
            }
        }

        bool GetValidNavMeshPosition(Vector3 position, out Vector3 validPosition)
        {
            NavMeshHit hit;
            if (NavMesh.SamplePosition(position, out hit, 0.3f, NavMesh.AllAreas))
            {
                validPosition = hit.position;
                return true;
            }
            validPosition = position;
            return false;
        }

        int FindAgentIndex()
        {
            if (agentManager == null || agentManager.navAgentArr == null)
                return -1;

            for (int i = 0; i < agentManager.navAgentArr.Length; i++)
            {
                if (agentManager.navAgentArr[i] == this.agent)
                    return i;
            }

            return -1;
        }
    }
}