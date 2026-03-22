using UnityEngine;
using UnityEngine.Rendering.Universal;
using UnityEngine.UI;

namespace DistributionCenter
{
    public class URPRenderScaleController : MonoBehaviour
    {
        public Slider renderScaleSlider;
        public UniversalRenderPipelineAsset urpAsset;
        public float defaultRenderScale = 1f;
        public Text renderScaleText;
        public Text qualityText;
        public GameObject rotatorImage;
        public float rotationMin = 0f;
        public float rotationMax = -270f;
        public float snapThreshold = 0.05f;

        [Range(0f, 2f)] public float minValue = 0f;
        [Range(0f, 2f)] public float maxValue = 2f;

        public Button high_BTN;
        public Button medium_BTN;
        public Button low_BTN;
        public AudioSource snapAudio;

        private float lastSnappedValue = -1f;
        private bool suppressSliderCallback = false;

        void Start()
        {
            if (snapAudio != null)
            {
                snapAudio.playOnAwake = false;
                snapAudio.dopplerLevel = 0f;
                snapAudio.spatialBlend = 0f;
            }

            renderScaleSlider.minValue = minValue;
            renderScaleSlider.maxValue = maxValue;

            float clampedDefault = Mathf.Clamp(defaultRenderScale, minValue, maxValue);
            urpAsset.renderScale = clampedDefault;
            renderScaleSlider.value = clampedDefault;
            lastSnappedValue = clampedDefault;
            UpdateRenderScaleText(clampedDefault);
            UpdateRotator(clampedDefault);

            renderScaleSlider.onValueChanged.AddListener(OnRenderScaleChanged);

            if (high_BTN) high_BTN.onClick.AddListener(() => SnapToValue(2.0f));
            if (medium_BTN) medium_BTN.onClick.AddListener(() => SnapToValue(1.0f));
            if (low_BTN) low_BTN.onClick.AddListener(() => SnapToValue(0.1f));
        }

        void OnRenderScaleChanged(float newValue)
        {
            float snappedValue = Mathf.Round(newValue / 0.10f) * 0.10f;

            if (Mathf.Abs(newValue - snappedValue) <= snapThreshold)
            {
                if (!Mathf.Approximately(snappedValue, lastSnappedValue))
                {
                    lastSnappedValue = snappedValue;

                    if (snapAudio != null)
                    {
                        snapAudio.Stop();
                        snapAudio.time = 0f;
                        snapAudio.Play();
                    }
                }

                suppressSliderCallback = true;
                renderScaleSlider.value = snappedValue;
                suppressSliderCallback = false;

                SetRenderScale(snappedValue);
                return;
            }

            SetRenderScale(newValue);
        }

        void SnapToValue(float targetValue)
        {
            float snappedValue = Mathf.Round(targetValue / 0.10f) * 0.10f;

            if (!Mathf.Approximately(snappedValue, lastSnappedValue))
            {
                lastSnappedValue = snappedValue;

                if (snapAudio != null)
                {
                    snapAudio.Stop();
                    snapAudio.time = 0f;
                    snapAudio.Play();
                }
            }

            suppressSliderCallback = true;
            renderScaleSlider.value = snappedValue;
            suppressSliderCallback = false;

            SetRenderScale(snappedValue);
        }

        void SetRenderScale(float value)
        {
            float clampedValue = Mathf.Clamp(value, minValue, maxValue);
            urpAsset.renderScale = clampedValue;
            UpdateRenderScaleText(clampedValue);
            UpdateRotator(clampedValue);
        }

        void UpdateRenderScaleText(float value)
        {
            renderScaleText.text = value.ToString("F2");
            qualityText.text = "Upscaling Value: <color=#000000>" + value.ToString("F2") + "</color>";
        }

        void UpdateRotator(float value)
        {
            if (rotatorImage != null)
            {
                float t = Mathf.InverseLerp(minValue, maxValue, value);
                float rotationZ = Mathf.Lerp(rotationMin, rotationMax, t);
                rotatorImage.transform.localEulerAngles = new Vector3(0f, 0f, rotationZ);
            }
        }
    }
}