using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.InputSystem;

[RequireComponent(typeof(Rigidbody))]
[RequireComponent(typeof(CascadedPIDController))]
[RequireComponent(typeof(CascadedOrientationPIDController))]
public class RoBartController : MessageReceivingBehavior, IActionHandler
{
    [SerializeField]
    [Tooltip("Translation speed (m/sec)")]
    private float m_translationSpeed = 5.0f;

    [SerializeField]
    [Tooltip("Rotational speed (deg/sec)")]
    private float m_rotationSpeed = 180.0f;

    [SerializeField]
    [Tooltip("Timeout (seconds) waiting for position goal to be reached")]
    private float m_positionTimeoutSeconds = 30.0f;

    [SerializeField]
    [Tooltip("Timeout (seconds) waiting for orientation to settle after position is reached")]
    private float m_orientationTimeoutSeconds = 5.0f;

    [SerializeField]
    private NavigablePointSampler.Parameters m_navigablePointParameters = NavigablePointSampler.Parameters.Default;

    private Rigidbody m_rb;
    private OccupancyMapBuilder m_occupancyMapBuilder;

    private GameObject m_positionTarget;
    private GameObject m_orientationTarget;
    private CascadedPIDController m_positionPIDController;
    private CascadedOrientationPIDController m_orientationPIDController;

    private readonly Queue<(Net.Session session, ActionsMessage msg)> m_actionsQueue = new Queue<(Net.Session, ActionsMessage)>();
    private bool m_isProcessingActions = false;
    private ObservationsMessage m_pendingObservations;

    private List<Vector3> m_landmarkWorldPoints = new List<Vector3>();

    private struct KeyboardControls
    {
        public bool forward;
        public bool backward;
        public bool strafeLeft;
        public bool strafeRight;
        public bool turnLeft;
        public bool turnRight;

        public readonly bool AnyPressed
        {
            get { return forward || backward || strafeLeft || strafeRight || turnLeft || turnRight; }
        }

        public static KeyboardControls Sample()
        {
            Keyboard keyboard = Keyboard.current;
            return new KeyboardControls()
            {
                forward = keyboard.upArrowKey.isPressed || keyboard.wKey.isPressed,
                backward = keyboard.downArrowKey.isPressed || keyboard.sKey.isPressed,
                strafeLeft = keyboard.commaKey.isPressed || keyboard.qKey.isPressed,
                strafeRight = keyboard.periodKey.isPressed || keyboard.eKey.isPressed,
                turnLeft = keyboard.leftArrowKey.isPressed || keyboard.aKey.isPressed,
                turnRight = keyboard.rightArrowKey.isPressed || keyboard.dKey.isPressed
            };
        }
    }

    private void Awake()
    {
        m_rb = GetComponent<Rigidbody>();
        m_occupancyMapBuilder = GetComponentInChildren<OccupancyMapBuilder>();
        m_positionPIDController = GetComponent<CascadedPIDController>();
        m_orientationPIDController = GetComponent<CascadedOrientationPIDController>();

        // Create targets for PID controllers
        m_positionTarget = new GameObject(name: "Target - Position");
        m_orientationTarget = new GameObject(name: "Target - Orientation");
    }

    private void OnEnable()
    {
        // Set PID target objects
        m_positionPIDController.target = m_positionTarget.transform;
        m_orientationPIDController.target = m_orientationTarget.transform;

        // Disable PID controllers
        m_positionPIDController.enabled = false;
        m_orientationPIDController.enabled = false;
    }

    private void FixedUpdate()
    {
        // Keyboard input overrides PIDs
        KeyboardControls keys = KeyboardControls.Sample();
        if (keys.AnyPressed)
        {
            MoveDirectly(keys);
            m_positionPIDController.enabled = false;
            m_orientationPIDController.enabled = false;
        }

        // // Check goal reached
        // if (m_positionPIDController.Error < 1e-2)
        // {
        //     m_positionPIDController.enabled = false;
        //     m_orientationPIDController.enabled = false;
        // }
    }

    private void Update()
    {
        // Mouse click sets PID target and turns them on
        if (Mouse.current.leftButton.wasPressedThisFrame)
        {
            if (SetPIDGoalsToClickedPosition())
            {
                m_positionPIDController.enabled = true;
                m_orientationPIDController.enabled = true;
            }
        }

        // Process actions
        if (!m_isProcessingActions)
        {
            StartCoroutine(ProcessActionsQueueCoroutine());
        }

    }

    private void MoveDirectly(KeyboardControls keys)
    {
        Vector3 deltaPosition = Vector3.zero;
        float deltaAngleDegrees = 0;

        if (keys.forward)
        {
            deltaPosition += transform.forward;
        }

        if (keys.backward)
        {
            deltaPosition += -transform.forward;
        }

        if (keys.strafeLeft)
        {
            deltaPosition += -transform.right;
        }

        if (keys.strafeRight)
        {
            deltaPosition += transform.right;
        }

        if (keys.turnLeft)
        {
            deltaAngleDegrees -= 1.0f;
        }

        if (keys.turnRight)
        {
            deltaAngleDegrees += 1.0f;
        }

        m_rb.MovePosition(transform.position + deltaPosition.XZProject().normalized * m_translationSpeed * Time.fixedDeltaTime);
        m_rb.MoveRotation(Quaternion.AngleAxis(angle: deltaAngleDegrees * m_rotationSpeed * Time.fixedDeltaTime, axis: Vector3.up) * transform.localRotation);
    }

    private bool SetPIDGoalsToClickedPosition()
    {
        Vector2 screenPoint = Mouse.current.position.value;

        Ray ray = Camera.main.ScreenPointToRay(screenPoint);
        RaycastHit hit;
        if (Physics.Raycast(ray: ray, hitInfo: out hit, maxDistance: 1000))
        {
            m_positionTarget.transform.position = hit.point.XZProject();

            Debug.Log($"Hit Position = {m_positionTarget.transform.position}, Name = {hit.collider.name}, screenPoint = {screenPoint}");

            // Place orientation target slightly beyond the position target so that the orientation
            // PID controller can still track when the desired position is reached. This is a bit
            // of a hack and will fail if we overshoot the position.
            Vector3 toTarget = (m_positionTarget.transform.position - transform.position).XZProject().normalized;
            m_orientationTarget.transform.position = m_positionTarget.transform.position + toTarget * 0.1f;

            // Indicate that we have updated the PID goals
            return true;
        }
        else
        {
            Debug.Log("No hit");
        }

        // Raycast did not succeed, indicate goals not set
        return false;
    }

    public override void OnActionsMessage(Net.Session session, ActionsMessage msg)
    {
        m_actionsQueue.Enqueue((session, msg));
    }

    private IEnumerator ProcessActionsQueueCoroutine()
    {
        m_isProcessingActions = true;
        while (m_actionsQueue.Count > 0)
        {
            var (session, msg) = m_actionsQueue.Dequeue();

            object[] actions = new object[msg.actions.Length];
            for (int i = 0; i < msg.actions.Length; i++)
            {
                actions[i] = ActionDecoder.DecodeAction(msg.actions[i]);
            }

            m_pendingObservations = new ObservationsMessage();
            foreach (object action in actions)
            {
                if (action != null)
                {
                    IEnumerator coroutine = ActionDispatcher.Dispatch(action, this);
                    if (coroutine != null)
                    {
                        yield return StartCoroutine(coroutine);
                    }
                }
            }
            session.Send(ref m_pendingObservations);
        }
        m_isProcessingActions = false;
    }

    public IEnumerator OnMoveAction(MoveAction action)
    {
        Debug.Log($"OnMoveAction: distance={action.distance}");

        Vector3 startPosition = transform.position;

        // Set position target along forward axis and place orientation target just beyond it
        Vector3 goalPosition = (transform.position + transform.forward.XZProject().normalized * action.distance).XZProject();
        m_positionTarget.transform.position = goalPosition;
        m_orientationTarget.transform.position = goalPosition + (goalPosition - startPosition).XZProject().normalized * 0.1f;
        m_positionPIDController.enabled = true;
        m_orientationPIDController.enabled = true;

        // Wait for position to be reached or timeout
        yield return new WaitUntilOrTimeout(() => m_positionPIDController.Error < 1e-2f, m_positionTimeoutSeconds);
        m_positionPIDController.enabled = false;

        // Wait for orientation to settle or timeout
        yield return new WaitUntilOrTimeout(() => m_orientationPIDController.Error < 1e-2f, m_orientationTimeoutSeconds);
        m_orientationPIDController.enabled = false;

        float distanceMoved = Vector3.Distance(transform.position.XZProject(), startPosition.XZProject());
        Debug.Log($"OnMoveAction: moved {distanceMoved:F3} m (requested {action.distance:F3} m)");
        m_pendingObservations.description += $"Move: travelled {distanceMoved:F3} m (requested {action.distance:F3} m).\n";
    }

    public IEnumerator OnMoveToAction(MoveToAction action)
    {
        Debug.Log($"OnMoveToAction: pointNumber={action.pointNumber}");
        yield break;
    }

    public IEnumerator OnTurnInPlaceAction(TurnInPlaceAction action)
    {
        Debug.Log($"OnTurnInPlaceAction: degrees={action.degrees}");
        Vector3 startForward = transform.forward.XZProject().normalized;
        // Positive degrees = left (counterclockwise); Unity positive-Y rotation = clockwise, so negate
        Vector3 targetForward = Quaternion.AngleAxis(-action.degrees, Vector3.up) * startForward;
        bool success = false;
        yield return StartCoroutine(FaceForward(targetForward, v => success = v));
        float actualDegrees = Vector3.SignedAngle(startForward, transform.forward.XZProject().normalized, Vector3.up);
        string status = success ? "completed" : "timed out";
        m_pendingObservations.description += $"Turn: {status}, rotated {actualDegrees:F1} deg (requested {action.degrees:F1} deg left).\n";
    }

    public IEnumerator OnFaceTowardAction(FaceTowardAction action)
    {
        Debug.Log($"OnFaceTowardAction: pointNumber={action.pointNumber}");
        yield break;
    }

    public IEnumerator OnFaceTowardHeadingAction(FaceTowardHeadingAction action)
    {
        Debug.Log($"OnFaceTowardHeadingAction: headingDegrees={action.headingDegrees}");
        // Heading 0 = world +Z, increasing clockwise; matches Unity positive-Y rotation convention
        Vector3 targetForward = Quaternion.AngleAxis(action.headingDegrees, Vector3.up) * Vector3.forward;
        bool success = false;
        yield return StartCoroutine(FaceForward(targetForward, v => success = v));
        float actualHeading = Vector3.SignedAngle(Vector3.forward, transform.forward.XZProject().normalized, Vector3.up);
        string status = success ? "completed" : "timed out";
        m_pendingObservations.description += $"Face heading: {status}, now facing {actualHeading:F1} deg (requested {action.headingDegrees:F1} deg).\n";
    }

    public IEnumerator OnScan360Action(Scan360Action action)
    {
        Debug.Log("OnScan360Action");

        Vector3 startForward = transform.forward.XZProject().normalized;

        // Build target directions at 45-degree increments, returning to start on the last step
        var steps = new List<Vector3>();
        for (int i = 1; i <= 7; i++)
            steps.Add(Quaternion.AngleAxis(45f * i, Vector3.up) * startForward);
        steps.Add(startForward);

        // Forward pass
        int numSucceeded = 0;
        bool wasSuccessful = true;
        foreach (Vector3 targetForward in steps)
        {
            bool success = false;
            Debug.Log($"Facing: {targetForward}");
            yield return StartCoroutine(FaceForward(targetForward, v => success = v));
            if (!success)
            {
                wasSuccessful = false;
                break;
            }
            yield return StartCoroutine(CapturePhoto());
            numSucceeded++;
        }

        // If the forward pass was blocked, return to start and sweep the other way to cover missed angles
        if (!wasSuccessful)
        {
            bool ignored = false;
            yield return StartCoroutine(FaceForward(startForward, v => ignored = v));

            foreach (Vector3 targetForward in steps.AsEnumerable().Reverse().Take(steps.Count - numSucceeded))
            {
                bool success = false;
                Debug.Log($"R Facing: {targetForward}");
                yield return StartCoroutine(FaceForward(targetForward, v => success = v));
                if (!success) break;
                yield return StartCoroutine(CapturePhoto());
            }
        }

        m_pendingObservations.description += "Completed 360 scan.\n";
    }

    public IEnumerator OnTakePhotoAction(TakePhotoAction action)
    {
        Debug.Log("OnTakePhotoAction");
        yield return StartCoroutine(CapturePhoto());
    }

    private IEnumerator FaceForward(Vector3 targetForward, Action<bool> onResult)
    {
        Vector3 fromForward = transform.forward.XZProject().normalized;
        float desiredDegrees = Vector3.Angle(fromForward, targetForward);

        m_orientationTarget.transform.position = transform.position + targetForward.normalized;
        m_orientationPIDController.enabled = true;

        var wait = new WaitUntilOrTimeout(() => m_orientationPIDController.Error < 1e-2f, m_orientationTimeoutSeconds);
        yield return wait;
        m_orientationPIDController.enabled = false;

        if (wait.TimedOut && desiredDegrees > 0f)
        {
            float actualDegrees = Vector3.Angle(fromForward, transform.forward.XZProject().normalized);
            float pctError = Mathf.Abs(actualDegrees / desiredDegrees - 1f);
            if (pctError > 0.2f)
            {
                Debug.LogWarning($"FaceForward: timed out with {pctError:P0} error (desired={desiredDegrees:F1} deg, actual={actualDegrees:F1} deg)");
                onResult(false);
                yield break;
            }
        }

        onResult(true);
    }

    //TODO next: need to ensure we don't self collide in occupancy map with robot itself (need to set special layer for robot)
    private IEnumerator CapturePhoto()
    {
        yield return new WaitForEndOfFrame();
        Texture2D screenshot = ScreenCapture.CaptureScreenshotAsTexture();
        byte[] jpegBytes = screenshot.EncodeToJPG();
        Destroy(screenshot);

        // Landmark IDs are just their index in the global store (begin with 0)
        int nextLandmarkId = m_landmarkWorldPoints.Count;

        AnnotatedPoint[] points = NavigablePointSampler.Sample(
            m_occupancyMapBuilder.Map,
            transform.position,
            transform.forward,
            Camera.main,
            m_navigablePointParameters,
            firstId: nextLandmarkId);
        
        // Store landmarks permanently (the global list maps ID -> world point)
        m_landmarkWorldPoints.AddRange(points.Select(point => point.worldPosition));

        AnnotatedImage annotatedImage = new AnnotatedImage
        {
            imageJpegBase64 = Convert.ToBase64String(jpegBytes),
            points = points
        };
        m_pendingObservations.images = (m_pendingObservations.images ?? Array.Empty<AnnotatedImage>()).Append(annotatedImage).ToArray();
    }

    public IEnumerator OnBackOutAction(BackOutAction action)
    {
        Debug.Log("OnBackOutAction");
        yield break;
    }
}
