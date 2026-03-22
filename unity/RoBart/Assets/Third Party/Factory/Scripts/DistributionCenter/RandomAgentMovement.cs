using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.AI;
using UnityEngine.UI;

namespace DistributionCenter
{
    [System.Serializable]
    public class TargetGroup
    {
        public GameObject[] targets;
    }

    public class RandomAgentMovement : MonoBehaviour
    {
        public NavMeshAgent[] navAgentArr;
        public TargetGroup[] agentTargetsArr;
        public bool[] agentEnabledArr;

        public Button startStopBTN;
        public Text startStopBTNText;

        public float minWaitTime = 1f;
        public float maxWaitTime = 3f;
        public float slowDownDistance = 2f;
        public float minSpeedFactor = 0.2f;

        [Header("Button Animation")]
        public float buttonAnimSpeed = 2f;

        private Dictionary<NavMeshAgent, Queue<int>> agentRecentTargets = new Dictionary<NavMeshAgent, Queue<int>>();
        private Dictionary<NavMeshAgent, float> agentMaxSpeeds = new Dictionary<NavMeshAgent, float>();
        private Dictionary<NavMeshAgent, Coroutine> movementCoroutines = new Dictionary<NavMeshAgent, Coroutine>();

        private bool isAgent0Running = false;
        private Coroutine animateColorRoutine;

        private Color colorA = new Color32(0x16, 0xB5, 0x53, 0xFF);
        private Color colorB = new Color32(0xFF, 0x00, 0x00, 0xFF);

        void Start()
        {
            for (int i = 0; i < navAgentArr.Length; i++)
            {
                var agent = navAgentArr[i];

                if (agentEnabledArr.Length <= i || !agentEnabledArr[i])
                {
                    if (agent != null)
                        agent.gameObject.SetActive(false);
                    continue;
                }

                agent.autoBraking = false;
                agentMaxSpeeds[agent] = agent.speed;
                agentRecentTargets[agent] = new Queue<int>();

                if (i != 0)
                    AssignRandomTarget(agent, i);
            }

            if (startStopBTN != null)
                startStopBTN.onClick.AddListener(ToggleAgent0);

            UpdateButtonUI();
        }

        void Update()
        {
            for (int i = 0; i < navAgentArr.Length; i++)
            {
                if (agentEnabledArr.Length <= i || !agentEnabledArr[i])
                    continue;

                var agent = navAgentArr[i];

                if (i == 0 && !isAgent0Running)
                    continue;

                if (agent.pathPending)
                    continue;

                float remainingDistance = agent.remainingDistance;

                if (remainingDistance <= slowDownDistance)
                {
                    float speedFactor = Mathf.Lerp(minSpeedFactor, 1f, remainingDistance / slowDownDistance);
                    agent.speed = agentMaxSpeeds[agent] * speedFactor;
                }
                else
                {
                    agent.speed = agentMaxSpeeds[agent];
                }

                if (remainingDistance <= agent.stoppingDistance && (!agent.hasPath || agent.velocity.sqrMagnitude == 0f))
                {
                    if (!movementCoroutines.ContainsKey(agent) || movementCoroutines[agent] == null)
                    {
                        movementCoroutines[agent] = StartCoroutine(WaitAndAssignTarget(agent, i));
                    }
                }
            }
        }

        IEnumerator WaitAndAssignTarget(NavMeshAgent agent, int agentIndex)
        {
            float waitTime = Random.Range(minWaitTime, maxWaitTime);
            yield return new WaitForSeconds(waitTime);
            AssignRandomTarget(agent, agentIndex);
            movementCoroutines[agent] = null;
        }

        public void AssignRandomTarget(NavMeshAgent agent, int agentIndex)
        {
            if (agentTargetsArr == null || agentIndex >= agentTargetsArr.Length)
                return;

            GameObject[] agentTargets = agentTargetsArr[agentIndex].targets;
            if (agentTargets == null || agentTargets.Length == 0)
                return;

            if (!agentRecentTargets.ContainsKey(agent))
                agentRecentTargets[agent] = new Queue<int>();

            Queue<int> recentTargets = agentRecentTargets[agent];
            int newIndex;

            do
            {
                newIndex = Random.Range(0, agentTargets.Length);
            }
            while (recentTargets.Contains(newIndex) && recentTargets.Count < agentTargets.Length);

            recentTargets.Enqueue(newIndex);
            if (recentTargets.Count > 2)
                recentTargets.Dequeue();

            agent.SetDestination(agentTargets[newIndex].transform.position);
        }

        public void ForceAssignNewTarget(NavMeshAgent agent, int agentIndex)
        {
            if (movementCoroutines.ContainsKey(agent) && movementCoroutines[agent] != null)
            {
                StopCoroutine(movementCoroutines[agent]);
                movementCoroutines[agent] = null;
            }

            AssignRandomTarget(agent, agentIndex);
        }

        void ToggleAgent0()
        {
            if (agentEnabledArr.Length == 0 || !agentEnabledArr[0])
                return;

            var agent = navAgentArr[0];
            isAgent0Running = !isAgent0Running;

            if (!isAgent0Running)
            {
                agent.ResetPath();
                if (movementCoroutines.ContainsKey(agent) && movementCoroutines[agent] != null)
                {
                    StopCoroutine(movementCoroutines[agent]);
                    movementCoroutines[agent] = null;
                }

                if (animateColorRoutine != null)
                    StopCoroutine(animateColorRoutine);
            }
            else
            {
                AssignRandomTarget(agent, 0);
                if (animateColorRoutine != null)
                    StopCoroutine(animateColorRoutine);
                animateColorRoutine = StartCoroutine(AnimateButtonColor());
            }

            UpdateButtonUI();
        }

        void UpdateButtonUI()
        {
            if (startStopBTNText != null)
                startStopBTNText.text = isAgent0Running ? "AUTO MODE ON" : "AUTO MODE ON";

            if (!isAgent0Running)
            {
                ColorBlock cb = startStopBTN.colors;
                cb.normalColor = colorA;
                cb.highlightedColor = colorA;
                cb.pressedColor = colorA;
                cb.selectedColor = colorA;
                startStopBTN.colors = cb;
            }
        }

        IEnumerator AnimateButtonColor()
        {
            float t = 0f;
            while (true)
            {
                t += Time.deltaTime;
                float lerp = (Mathf.Sin(t * buttonAnimSpeed) + 1f) / 2f;
                Color lerpedColor = Color.Lerp(colorA, colorB, lerp);

                ColorBlock cb = startStopBTN.colors;
                cb.normalColor = lerpedColor;
                cb.highlightedColor = lerpedColor;
                cb.pressedColor = lerpedColor;
                cb.selectedColor = lerpedColor;
                startStopBTN.colors = cb;

                yield return null;
            }
        }
    }
}