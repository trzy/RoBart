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

    [SerializeField]
    [Tooltip("Visual trace capture rate in Hz during action execution")]
    private float m_traceCaptureHz = 2f;

    [SerializeField]
    [Tooltip("Max distance (m) for per-pixel depth raycasts captured with each photo")]
    private float m_depthMaxDistance = 6f;

    private Rigidbody m_rb;
    private OccupancyMapBuilder m_occupancyMapBuilder;
    private float m_robotRadius;

    private GameObject m_positionTarget;
    private GameObject m_orientationTarget;
    private CascadedPIDController m_positionPIDController;
    private CascadedOrientationPIDController m_orientationPIDController;

    private readonly Queue<(Net.Session session, ActionsMessage msg)> m_actionsQueue = new Queue<(Net.Session, ActionsMessage)>();
    private bool m_isProcessingActions = false;
    private ObservationsMessage m_pendingObservations;

    private LandmarkStore m_landmarkStore;

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
        m_robotRadius = Footprint.GetRadius(gameObject);
        m_landmarkStore = new LandmarkStore(m_navigablePointParameters.PointSpacingMeters * 0.5f);

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

            var traceSamples = new List<VisualTraceSample>();
            bool stopTrace = false;
            bool traceRunning = false;

            foreach (object action in actions)
            {
                if (action != null)
                {
                    bool shouldTrace = action is MoveAction or MoveToAction or MoveToPosAction or MoveToLocationAction
                        or TurnInPlaceAction or FaceTowardAction or FaceTowardPosAction or FaceTowardHeadingAction;

                    if (shouldTrace && !traceRunning)
                    {
                        stopTrace = false;
                        StartCoroutine(VisualTraceCapture.RecordSamples(transform, m_traceCaptureHz, traceSamples, () => stopTrace));
                        traceRunning = true;
                    }
                    else if (!shouldTrace && traceRunning)
                    {
                        stopTrace = true;
                        yield return null;
                        traceRunning = false;
                    }

                    IEnumerator coroutine = ActionDispatcher.Dispatch(action, this);
                    if (coroutine != null)
                    {
                        yield return StartCoroutine(coroutine);
                    }
                }
            }

            if (traceRunning)
            {
                stopTrace = true;
                yield return null;
            }
            m_pendingObservations.visualTrace = traceSamples.ToArray();

            Vector3 forward = transform.forward.XZProject().normalized;
            m_pendingObservations.description += $"\nCurrent pos=({transform.position.x:F2},{transform.position.z:F2}), fwd=({forward.x:F2},{forward.z:F2})\n";
            m_pendingObservations.currentPosition = new VectorXZ { x = transform.position.x, z = transform.position.z };
            m_pendingObservations.currentForward = new VectorXZ { x = forward.x, z = forward.z };
            PopulateMaps(ref m_pendingObservations);
            session.Send(ref m_pendingObservations);
        }
        m_isProcessingActions = false;
    }

    public IEnumerator OnMoveAction(MoveAction action)
    {
        Debug.Log($"OnMoveAction: distance={action.distance}");

        Vector3 startPosition = transform.position;

        // Set position target along forward axis
        Vector3 goalPosition = (transform.position + transform.forward.XZProject().normalized * action.distance).XZProject();
        m_positionTarget.transform.position = goalPosition;
        
        // Orientation target depends on whether we are moving forwards or backwards (negative 
        // distance implies moving facing backwards, such as backing out)
        if (action.distance >= 0)
        {
            m_orientationTarget.transform.position = goalPosition + (goalPosition - startPosition).XZProject().normalized * 0.1f;
        }
        else
        {
            // Directly in front of us, so we don't turn while moving backwards
            m_orientationTarget.transform.position = (transform.position + transform.forward.XZProject().normalized * 1.0f).XZProject();
        }
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

        if (!m_landmarkStore.IsValidId(action.pointNumber))
        {
            Debug.LogError($"OnMoveToAction: point {action.pointNumber} not found (have {m_landmarkStore.Count} landmarks)");
            m_pendingObservations.description += $"Move to point {action.pointNumber}: failed (unknown point).\n";
            yield break;
        }

        Vector3 goal = m_landmarkStore[action.pointNumber];
        List<Vector3> path = PathFinder.FindPath(m_occupancyMapBuilder.Map, transform.position, goal, m_robotRadius);

        if (path == null || path.Count == 0)
        {
            Debug.LogWarning($"OnMoveToAction: no path found to point {action.pointNumber}");
            m_pendingObservations.description += $"Move to point {action.pointNumber}: no path found.\n";
            yield break;
        }

        Debug.Log($"OnMoveToAction: following {path.Count}-waypoint path to point {action.pointNumber}");
        yield return StartCoroutine(FollowPath(path));

        float distanceToGoal = Vector3.Distance(transform.position.XZProject(), goal.XZProject());
        m_pendingObservations.description += $"Move to point {action.pointNumber}: arrived, {distanceToGoal:F2} m from goal.\n";
    }

    public IEnumerator OnMoveToPosAction(MoveToPosAction action)
    {
        Debug.Log($"OnMoveToPosAction: x={action.x}, z={action.z}");

        Vector3 goal = new Vector3(action.x, 0, action.z);
        List<Vector3> path = PathFinder.FindPath(m_occupancyMapBuilder.Map, transform.position, goal, m_robotRadius);

        if (path == null || path.Count == 0)
        {
            Debug.LogWarning($"OnMoveToPosAction: no path found to ({action.x}, {action.z})");
            m_pendingObservations.description += $"Move to pos ({action.x:F1},{action.z:F1}): no path found.\n";
            yield break;
        }

        Debug.Log($"OnMoveToPosAction: following {path.Count}-waypoint path");
        yield return StartCoroutine(FollowPath(path));

        float distanceToGoal = Vector3.Distance(transform.position.XZProject(), goal.XZProject());
        m_pendingObservations.description += $"Move to pos ({action.x:F1},{action.z:F1}): arrived, {distanceToGoal:F2} m from goal.\n";
    }

    public IEnumerator OnMoveToLocationAction(MoveToLocationAction action)
    {
        Debug.Log($"OnMoveToLocationAction: x={action.x}, z={action.z}, forwardX={action.forwardX}, forwardZ={action.forwardZ}");

        Vector3 goal = new Vector3(action.x, 0, action.z);
        Vector3 targetForward = new Vector3(action.forwardX, 0, action.forwardZ);
        List<Vector3> path = PathFinder.FindPath(m_occupancyMapBuilder.Map, transform.position, goal, m_robotRadius);

        if (path == null || path.Count == 0)
        {
            Debug.LogWarning($"OnMoveToLocationAction: no path found to ({action.x}, {action.z})");
            m_pendingObservations.description += $"Move to location ({action.x:F1},{action.z:F1}): no path found.\n";
            yield break;
        }

        Debug.Log($"OnMoveToLocationAction: following {path.Count}-waypoint path");
        yield return StartCoroutine(FollowPath(path, targetForward));

        float distanceToGoal = Vector3.Distance(transform.position.XZProject(), goal.XZProject());
        m_pendingObservations.description += $"Move to location ({action.x:F1},{action.z:F1}): arrived, {distanceToGoal:F2} m from goal.\n";
    }

    private IEnumerator FollowPath(List<Vector3> waypoints, Vector3? targetForward = null)
    {
        foreach (Vector3 waypoint in waypoints)
        {
            // Face toward the waypoint before driving to it
            Vector3 toWaypoint = (waypoint - transform.position).XZProject();
            if (toWaypoint.magnitude > 1e-3f)
            {
                bool ignored = false;
                yield return StartCoroutine(FaceForward(toWaypoint.normalized, v => ignored = v));
            }

            // Drive to the waypoint
            Vector3 waypointXZ = waypoint.XZProject();
            m_positionTarget.transform.position = waypointXZ;
            m_orientationTarget.transform.position = waypointXZ + (waypoint - transform.position).XZProject().normalized * 0.1f;
            m_positionPIDController.enabled = true;
            m_orientationPIDController.enabled = true;

            yield return new WaitUntilOrTimeout(() => m_positionPIDController.Error < 1e-2f, m_positionTimeoutSeconds);
            m_positionPIDController.enabled = false;
            m_orientationPIDController.enabled = false;
        }

        // Orient to target forward direction after reaching destination
        if (targetForward.HasValue)
        {
            Vector3 fwd = targetForward.Value.XZProject().normalized;
            if (fwd.magnitude > 1e-3f)
            {
                bool ignored = false;
                yield return StartCoroutine(FaceForward(fwd, v => ignored = v));
            }
        }
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

        if (!m_landmarkStore.IsValidId(action.pointNumber))
        {
            Debug.LogError($"OnFaceTowardAction: point {action.pointNumber} not found (have {m_landmarkStore.Count} landmarks)");
            m_pendingObservations.description += $"Face toward point {action.pointNumber}: failed (unknown point).\n";
            yield break;
        }

        Vector3 toTarget = (m_landmarkStore[action.pointNumber] - transform.position).XZProject();
        if (toTarget.magnitude < 1e-3f)
        {
            m_pendingObservations.description += $"Face toward point {action.pointNumber}: already at target position.\n";
            yield break;
        }

        bool success = false;
        yield return StartCoroutine(FaceForward(toTarget.normalized, v => success = v));

        float actualHeading = Vector3.SignedAngle(Vector3.forward, transform.forward.XZProject().normalized, Vector3.up);
        string status = success ? "completed" : "timed out";
        m_pendingObservations.description += $"Face toward point {action.pointNumber}: {status}, now facing {actualHeading:F1} deg.\n";
    }

    public IEnumerator OnFaceTowardPosAction(FaceTowardPosAction action)
    {
        Debug.Log($"OnFaceTowardPosAction: x={action.x}, z={action.z}");

        Vector3 target = new Vector3(action.x, 0, action.z);
        Vector3 toTarget = (target - transform.position).XZProject();
        if (toTarget.magnitude < 1e-3f)
        {
            m_pendingObservations.description += $"Face toward pos ({action.x:F1},{action.z:F1}): already at target position.\n";
            yield break;
        }

        bool success = false;
        yield return StartCoroutine(FaceForward(toTarget.normalized, v => success = v));

        float actualHeading = Vector3.SignedAngle(Vector3.forward, transform.forward.XZProject().normalized, Vector3.up);
        string status = success ? "completed" : "timed out";
        m_pendingObservations.description += $"Face toward pos ({action.x:F1},{action.z:F1}): {status}, now facing {actualHeading:F1} deg.\n";
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
        int width = screenshot.width;
        int height = screenshot.height;
        byte[] jpegBytes = screenshot.EncodeToJPG();
        Destroy(screenshot);

        AnnotatedPoint[] points = NavigablePointSampler.Sample(
            m_occupancyMapBuilder.Map,
            transform.position,
            transform.forward,
            Camera.main,
            m_navigablePointParameters,
            firstId: 0);

        // Deduplicate against existing landmarks and assign stable IDs
        points = m_landmarkStore.Resolve(points);

        Vector3[] depthMap = ComputeDepthMap(Camera.main, width, height, m_depthMaxDistance);

        Vector3 fwd = transform.forward.XZProject().normalized;
        AnnotatedImage annotatedImage = new AnnotatedImage
        {
            imageJpegBase64 = Convert.ToBase64String(jpegBytes),
            cameraPosition = new VectorXZ { x = transform.position.x, z = transform.position.z },
            cameraForward  = new VectorXZ { x = fwd.x, z = fwd.z },
            points = points,
            depthWidth = width,
            depthHeight = height,
            depthMap = depthMap
        };
        m_pendingObservations.images = (m_pendingObservations.images ?? Array.Empty<AnnotatedImage>()).Append(annotatedImage).ToArray();
    }

    // Casts one ray per (sub)pixel against scene colliders and returns world-space hit points
    // in a row-major, top-left-origin array (matching JPEG pixel order). Misses (out of range or
    // no collider) are encoded as (1e6, 1e6, 1e6).
    // Cost is O(width * height) raycasts; at full screen resolution this blocks the main thread for
    // a noticeable time. Replace with a depth-buffer + inverse-VP reconstruction if perf matters.
    private const float DepthMissSentinel = 1e6f;
    private static Vector3[] ComputeDepthMap(Camera cam, int width, int height, float maxDistance)
    {
        Vector3[] depth = new Vector3[width * height];
        Vector3 miss = new Vector3(DepthMissSentinel, DepthMissSentinel, DepthMissSentinel);
        for (int y = 0; y < height; y++)
        {
            // Image rows are top-down; Unity screen coords have origin at bottom-left, so flip y.
            float screenY = (height - 1 - y) + 0.5f;
            int rowBase = y * width;
            for (int x = 0; x < width; x++)
            {
                Ray ray = cam.ScreenPointToRay(new Vector3(x + 0.5f, screenY, 0f));
                if (Physics.Raycast(ray, out RaycastHit hit, maxDistance))
                {
                    depth[rowBase + x] = hit.point;
                }
                else
                {
                    depth[rowBase + x] = miss;
                }
            }
        }
        return depth;
    }

    private void PopulateMaps(ref ObservationsMessage obs)
    {
        var occupancyMap = m_occupancyMapBuilder.Map;
        var lastVisitedMap = m_occupancyMapBuilder.LastVisitedMap;

        int cellsWide = occupancyMap.CellsWide;
        int cellsDeep = occupancyMap.CellsDeep;
        int totalCells = cellsWide * cellsDeep;

        obs.mapCellsWide = cellsWide;
        obs.mapCellsDeep = cellsDeep;
        obs.mapCellSize = occupancyMap.CellSize;
        obs.mapOriginX = occupancyMap.Center.x - cellsWide * occupancyMap.CellSize / 2f;
        obs.mapOriginZ = occupancyMap.Center.z - cellsDeep * occupancyMap.CellSize / 2f;

        obs.occupancy = new int[totalCells];
        obs.lastVisited = new float[totalCells];

        for (int z = 0; z < cellsDeep; z++)
        {
            for (int x = 0; x < cellsWide; x++)
            {
                int i = z * cellsWide + x;
                obs.occupancy[i] = occupancyMap.Get(x, z) ? 1 : 0;
                obs.lastVisited[i] = lastVisitedMap.Get(x, z);
            }
        }
    }

    public IEnumerator OnBackOutAction(BackOutAction action)
    {
        Debug.Log("OnBackOutAction");
        yield break;
    }
}
