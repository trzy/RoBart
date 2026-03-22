using System;
using UnityEngine;

/// Suspends a coroutine until the condition returns true or the timeout elapses.
/// Check TimedOut after yielding to determine which occurred.
public class WaitUntilOrTimeout : CustomYieldInstruction
{
    private readonly Func<bool> m_condition;
    private readonly float m_endTime;

    public bool TimedOut { get; private set; }

    public WaitUntilOrTimeout(Func<bool> condition, float timeoutSeconds)
    {
        m_condition = condition;
        m_endTime = Time.time + timeoutSeconds;
    }

    public override bool keepWaiting
    {
        get
        {
            if (m_condition())
            {
                TimedOut = false;
                return false;
            }
            if (Time.time >= m_endTime)
            {
                TimedOut = true;
                return false;
            }
            return true;
        }
    }
}
