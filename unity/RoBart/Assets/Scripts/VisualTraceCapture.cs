using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

/// Static utility for recording visual trace samples (screenshot + pose + timestamp)
/// at a configurable rate. Can be driven by any MonoBehaviour via StartCoroutine.
public static class VisualTraceCapture
{
    public static IEnumerator RecordSamples(
        Transform robotTransform,
        float captureHz,
        List<VisualTraceSample> outSamples,
        Func<bool> shouldStop)
    {
        float startTime = Time.time;
        float interval = 1f / captureHz;

        while (!shouldStop())
        {
            yield return new WaitForEndOfFrame();

            Texture2D screenshot = ScreenCapture.CaptureScreenshotAsTexture();
            byte[] jpegBytes = screenshot.EncodeToJPG();
            UnityEngine.Object.Destroy(screenshot);

            Vector3 fwd = robotTransform.forward.XZProject().normalized;
            outSamples.Add(new VisualTraceSample
            {
                imageJpegBase64 = Convert.ToBase64String(jpegBytes),
                worldPosition = new VectorXZ { x = robotTransform.position.x, z = robotTransform.position.z },
                worldForward  = new VectorXZ { x = fwd.x, z = fwd.z },
                timestampSeconds = Time.time - startTime
            });

            yield return new WaitForSeconds(interval);
        }
    }
}
