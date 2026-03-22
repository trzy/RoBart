using Unity.Cinemachine;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.UI;

namespace DistributionCenter
{
    public class CamInput : MonoBehaviour
    {
        public Transform target;
        public float orbitSpeed = 5.0f;
        public float zoomSpeed = 10.0f;
        public float minZoomDistance = 5.0f;
        public float maxZoomDistance = 20.0f;

        public bool disableCinemachineInput = false;

        private float currentDistance;
        private Vector3 orbitAngles;
        private bool isOrbiting = false;
        private CinemachineInputAxisController cinemachineController;

        public float hotboxWidthAt500 = 150f;
        public float hotboxWidthAt1920 = 300f;
        public float hotboxWidthAt3840 = 600f;
        public Color hotboxColor = Color.black;

        private Canvas canvas;
        private RectTransform leftHotbox;
        private RectTransform rightHotbox;

        void Start()
        {
            if (target == null)
                return;

            currentDistance = Vector3.Distance(transform.position, target.position);
            orbitAngles = transform.eulerAngles;
            cinemachineController = GetComponent<CinemachineInputAxisController>() ?? FindObjectOfType<CinemachineInputAxisController>();

            SetupCanvas();
            SetupHotboxUI(true);
            SetupHotboxUI(false);
        }

        void Update()
        {
            bool isMouseOverLeftHotbox = IsMouseOverHotbox(leftHotbox);
            bool isMouseOverRightHotbox = IsMouseOverHotbox(rightHotbox);

            if (!(isMouseOverLeftHotbox || isMouseOverRightHotbox) && Mouse.current.leftButton.wasPressedThisFrame)
            {
                disableCinemachineInput = false;
                isOrbiting = true;
            }
            else if (Mouse.current.leftButton.wasReleasedThisFrame)
            {
                disableCinemachineInput = true;
                isOrbiting = false;
            }

            if (cinemachineController != null)
                cinemachineController.enabled = !disableCinemachineInput;

            HandleOrbitInput();
            HandleZoomInput();

            UpdateHotboxWidth();
        }

        void HandleOrbitInput()
        {
            if (isOrbiting)
            {
                Vector2 mouseDelta = Mouse.current.delta.ReadValue();
                float horizontal = mouseDelta.x * orbitSpeed;
                float vertical = -mouseDelta.y * orbitSpeed;

                orbitAngles.x = Mathf.Clamp(orbitAngles.x + vertical, -90f, 90f);
                orbitAngles.y += horizontal;

                Quaternion rotation = Quaternion.Euler(orbitAngles.x, orbitAngles.y, 0);
                transform.rotation = rotation;

                Vector3 direction = rotation * Vector3.forward;
                transform.position = target.position - direction * currentDistance;
            }
        }

        void HandleZoomInput()
        {
            float scrollInput = Mouse.current.scroll.ReadValue().y;
            currentDistance = Mathf.Clamp(currentDistance - scrollInput * zoomSpeed, minZoomDistance, maxZoomDistance);

            Vector3 direction = transform.rotation * Vector3.forward;
            transform.position = target.position - direction * currentDistance;
        }

        void SetupCanvas()
        {
            canvas = FindObjectOfType<Canvas>();
            if (canvas == null)
            {
                GameObject canvasObject = new GameObject("Canvas");
                canvas = canvasObject.AddComponent<Canvas>();
                canvas.renderMode = RenderMode.ScreenSpaceOverlay;
                canvas.gameObject.AddComponent<CanvasScaler>();
                canvas.gameObject.AddComponent<GraphicRaycaster>();
            }
        }

        void SetupHotboxUI(bool isLeft)
        {
            GameObject panel = new GameObject(isLeft ? "LeftHotboxPanel" : "RightHotboxPanel");
            panel.transform.SetParent(canvas.transform, false);

            RectTransform hotbox = panel.AddComponent<RectTransform>();
            hotbox.anchorMin = isLeft ? new Vector2(0, 0) : new Vector2(1, 0);
            hotbox.anchorMax = isLeft ? new Vector2(0, 1) : new Vector2(1, 1);
            hotbox.pivot = isLeft ? new Vector2(0, 0.5f) : new Vector2(1, 0.5f);
            hotbox.anchoredPosition = new Vector2(0, 0);

            Image image = panel.AddComponent<Image>();
            image.color = hotboxColor;

            panel.transform.SetAsFirstSibling();

            if (isLeft)
                leftHotbox = hotbox;
            else
                rightHotbox = hotbox;
        }

        void UpdateHotboxWidth()
        {
            if (leftHotbox == null || rightHotbox == null) return;

            float hotboxWidth;
            if (Screen.width <= 1920)
            {
                float t = Mathf.InverseLerp(500, 1920, Screen.width);
                hotboxWidth = Mathf.Lerp(hotboxWidthAt500, hotboxWidthAt1920, t);
            }
            else
            {
                float t = Mathf.InverseLerp(1920, 3840, Screen.width);
                hotboxWidth = Mathf.Lerp(hotboxWidthAt1920, hotboxWidthAt3840, t);
            }

            leftHotbox.sizeDelta = new Vector2(hotboxWidth, canvas.pixelRect.height);
            rightHotbox.sizeDelta = new Vector2(hotboxWidth, canvas.pixelRect.height);
        }

        bool IsMouseOverHotbox(RectTransform hotbox)
        {
            if (hotbox == null)
                return false;

            Vector2 mousePosition = Mouse.current.position.ReadValue();
            Vector2 localMousePosition = hotbox.InverseTransformPoint(mousePosition);
            return hotbox.rect.Contains(localMousePosition);
        }
    }
}