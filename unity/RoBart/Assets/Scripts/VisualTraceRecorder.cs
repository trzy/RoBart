using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;

/// Records a visual trace (image + world position + timestamp) at a configurable rate.
/// Press P to start recording; press P again to stop and send the VisualTraceMessage.
public class VisualTraceRecorder : MessageReceivingBehavior
{
    [SerializeField]
    [Tooltip("Image capture rate in Hz")]
    private float m_captureHz = 2f;

    private Net.Session m_session;
    private bool m_isRecording = false;

    public override void OnConnect(Net.Session session)
    {
        m_session = session;
    }

    public override void OnDisconnect(Net.Session session)
    {
        m_session = null;
    }

    private void Update()
    {
        if (Keyboard.current.pKey.wasPressedThisFrame)
        {
            if (m_isRecording)
            {
                m_isRecording = false;
                Debug.Log("VisualTraceRecorder: stopped");
            }
            else
            {
                m_isRecording = true;
                StartCoroutine(RecordCoroutine());
                Debug.Log("VisualTraceRecorder: started");
            }
        }
    }

    private IEnumerator RecordCoroutine()
    {
        var samples = new List<VisualTraceSample>();

        yield return StartCoroutine(
            VisualTraceCapture.RecordSamples(transform, m_captureHz, samples, () => !m_isRecording)
        );

        if (m_session != null && samples.Count > 0)
        {
            VisualTraceMessage msg = new VisualTraceMessage { entries = samples.ToArray() };
            m_session.Send(ref msg);
            Debug.Log($"VisualTraceRecorder: sent {samples.Count} samples");
        }
    }
}
