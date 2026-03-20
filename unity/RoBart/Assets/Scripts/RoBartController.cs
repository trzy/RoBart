using System.Runtime.InteropServices.WindowsRuntime;
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

    private Rigidbody m_rb;
    private GameObject m_positionTarget;
    private GameObject m_orientationTarget;
    private CascadedPIDController m_positionPIDController;
    private CascadedOrientationPIDController m_orientationPIDController;

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

        // Check goal reached
        if (m_positionPIDController.Error < 1e-2)
        {
            m_positionPIDController.enabled = false;
            m_orientationPIDController.enabled = false;
        }
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
        object[] actions = new object[msg.actions.Length];
        for (int i = 0; i < msg.actions.Length; i++)
        {
            actions[i] = ActionDecoder.DecodeAction(msg.actions[i]);
        }
        foreach (object action in actions)
        {
            if (action != null)
            {
                ActionDispatcher.Dispatch(action, this);
            }
        }
    }

    public void OnMoveAction(MoveAction action)
    {
        Debug.Log($"OnMoveAction: distance={action.distance}");

        m_positionTarget.transform.position = transform.position + transform.forward.XZProject().normalized * action.distance;
        m_positionPIDController.enabled = true;
    }

    public void OnMoveToAction(MoveToAction action)
    {
        Debug.Log($"OnMoveToAction: pointNumber={action.pointNumber}");
    }

    public void OnTurnInPlaceAction(TurnInPlaceAction action)
    {
        Debug.Log($"OnTurnInPlaceAction: degrees={action.degrees}");
    }

    public void OnFaceTowardAction(FaceTowardAction action)
    {
        Debug.Log($"OnFaceTowardAction: pointNumber={action.pointNumber}");
    }

    public void OnFaceTowardHeadingAction(FaceTowardHeadingAction action)
    {
        Debug.Log($"OnFaceTowardHeadingAction: headingDegrees={action.headingDegrees}");
    }

    public void OnScan360Action(Scan360Action action)
    {
        Debug.Log("OnScan360Action");
    }

    public void OnTakePhotoAction(TakePhotoAction action)
    {
        Debug.Log("OnTakePhotoAction");
    }

    public void OnBackOutAction(BackOutAction action)
    {
        Debug.Log("OnBackOutAction");
    }
}
