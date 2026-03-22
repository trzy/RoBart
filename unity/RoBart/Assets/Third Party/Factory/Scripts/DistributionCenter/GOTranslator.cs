using System.Collections;
using UnityEngine;
using UnityEngine.UI;

namespace DistributionCenter
{
    public class GOTranslator : MonoBehaviour
    {
        public GameObject[] GOTranslator_ARRAY;
        public Slider translationSlider;
        public float minValue = -5f;
        public float maxValue = 5f;

        public enum Axis { X, Y, Z }
        public Axis translationAxis = Axis.Y;
        public bool invertTranslation = false;

        private Vector3[] originalLocalPositions;

        [Header("UI Image Translation")]
        public Image[] ImgTranslator;
        public float imgMinValue = -100f;
        public float imgMaxValue = 100f;
        public Axis imgTranslationAxis = Axis.X;
        public bool invertImgTranslation = false;

        private Vector3[] originalImgPositions;

        [Header("Slider Audio")]
        public AudioSource sliderAudioSource;
        public float fadeDuration = 0.3f;
        public float slideTimeout = 0.15f;
        public float targetVolume = 1f;
        public float minVolume = 0f;

        private float lastSlideTime;
        private bool audioCoroutineRunning = false;
        private Coroutine fadeCoroutine;

        void Start()
        {
            originalLocalPositions = new Vector3[GOTranslator_ARRAY.Length];
            for (int i = 0; i < GOTranslator_ARRAY.Length; i++)
                if (GOTranslator_ARRAY[i] != null)
                    originalLocalPositions[i] = GOTranslator_ARRAY[i].transform.localPosition;

            originalImgPositions = new Vector3[ImgTranslator.Length];
            for (int i = 0; i < ImgTranslator.Length; i++)
                if (ImgTranslator[i] != null)
                    originalImgPositions[i] = ImgTranslator[i].rectTransform.localPosition;

            if (translationSlider != null)
            {
                translationSlider.minValue = minValue;
                translationSlider.maxValue = maxValue;
                translationSlider.onValueChanged.AddListener(UpdateTranslation);
            }
        }

        void UpdateTranslation(float value)
        {
            lastSlideTime = Time.time;

            if (sliderAudioSource != null)
            {
                if (!sliderAudioSource.isPlaying)
                {
                    sliderAudioSource.volume = minVolume;
                    sliderAudioSource.Play();
                    if (fadeCoroutine != null) StopCoroutine(fadeCoroutine);
                    fadeCoroutine = StartCoroutine(FadeAudio(sliderAudioSource, targetVolume));
                }
            }

            if (!audioCoroutineRunning)
                StartCoroutine(HandleAudioStop());

            float offset = invertTranslation ? -value : value;
            float imgNormalized = Mathf.InverseLerp(minValue, maxValue, value);
            float imgOffsetValue = Mathf.Lerp(imgMinValue, imgMaxValue, imgNormalized);
            float imgOffset = invertImgTranslation ? -imgOffsetValue : imgOffsetValue;

            for (int i = 0; i < GOTranslator_ARRAY.Length; i++)
            {
                GameObject obj = GOTranslator_ARRAY[i];
                if (obj != null)
                {
                    Vector3 localPos = originalLocalPositions[i];
                    switch (translationAxis)
                    {
                        case Axis.X: localPos.x += offset; break;
                        case Axis.Y: localPos.y += offset; break;
                        case Axis.Z: localPos.z += offset; break;
                    }
                    obj.transform.localPosition = localPos;
                }
            }

            for (int i = 0; i < ImgTranslator.Length; i++)
            {
                if (ImgTranslator[i] != null)
                {
                    Vector3 localPos = originalImgPositions[i];
                    switch (imgTranslationAxis)
                    {
                        case Axis.X: localPos.x += imgOffset; break;
                        case Axis.Y: localPos.y += imgOffset; break;
                        case Axis.Z: localPos.z += imgOffset; break;
                    }
                    ImgTranslator[i].rectTransform.localPosition = localPos;
                }
            }
        }

        IEnumerator HandleAudioStop()
        {
            audioCoroutineRunning = true;
            while (Time.time - lastSlideTime < slideTimeout)
                yield return null;

            if (sliderAudioSource != null && sliderAudioSource.isPlaying)
            {
                if (fadeCoroutine != null) StopCoroutine(fadeCoroutine);
                fadeCoroutine = StartCoroutine(FadeAudio(sliderAudioSource, minVolume, stopOnZero: true));
            }

            audioCoroutineRunning = false;
        }

        IEnumerator FadeAudio(AudioSource source, float targetVol, bool stopOnZero = false)
        {
            float startVolume = source.volume;
            float elapsed = 0f;

            while (elapsed < fadeDuration)
            {
                elapsed += Time.deltaTime;
                source.volume = Mathf.Lerp(startVolume, targetVol, elapsed / fadeDuration);
                yield return null;
            }

            source.volume = targetVol;

            if (stopOnZero && targetVol <= 0f)
                source.Stop();
        }
    }
}