/*
 * CascadedPIDController.cs
 * Bart Trzynadlowski, 2024
 * 
 * Two PID controllers in series, the first outputting a target velocity given displacement error
 * and the second outputting a throttle value given velocity error. Our system can measure both
 * velocity and position.
 * 
 * This is effectively the same as PositionPIDController but with two PID controllers in series
 * and an additional option to update the control loop at a different, lower frequency.
 */

using UnityEngine;

public class CascadedPIDController : MonoBehaviour
{
    public Transform target;

    [SerializeField]
    private float _maximumAcceleration = 5;

    [SerializeField]
    private float _maximumSpeed = 3;

    [SerializeField]
    private float _controlLoopFrequency = 50;

    [SerializeField]
    private float _positionKp = 1.0f;

    [SerializeField]
    private float _positionKi = 0.0f;

    [SerializeField]
    private float _positionKd = 0.0f;

    [SerializeField]
    private float _velocityKp = 1.0f;

    [SerializeField]
    private float _velocityKi = 0.0f;

    [SerializeField]
    private float _velocityKd = 0.0f;

    [SerializeField]
    private float _integralEnabledDistance = 5;

    private float _lastLoopTime = 0;

    private struct PIDState
    {
        public float? prevError;
        public float integralError;
    }

    private Vector3? _lastPosition = null;
    private PIDState _positionControllerState = new PIDState() { prevError = null, integralError = 0 };
    private PIDState _velocityControllerState = new PIDState() { prevError = null, integralError = 0 };

    private float _throttle = 0;
    private float _velocity = 0;    // drives the vehicle (but we don't sample it directly in order to be more realistic)

    public float Error
    {
        get { return Mathf.Abs(SignedPositionError(currentPosition: transform.position)); }
    }

    private void OnEnable()
    {
        _lastLoopTime = Time.fixedTime;
        _lastPosition = null;
        _positionControllerState = new PIDState() { prevError = null, integralError = 0 };
        _velocityControllerState = new PIDState() { prevError = null, integralError = 0 };
        _throttle = 0;
        _velocity = 0;
    }

    private void FixedUpdate()
    {
        float controlLoopPeriod = 1.0f / _controlLoopFrequency;
        float timeSinceLastControlLoopUpdate = Time.fixedTime - _lastLoopTime;
        if (Mathf.Abs(timeSinceLastControlLoopUpdate - controlLoopPeriod) < 1e-3)   // because of slight fluctuations in timing causing numerical discrepancies, we check for landing within ~1ms
        {
            _lastLoopTime = Time.fixedTime;

            float dt = timeSinceLastControlLoopUpdate;
            if (dt <= 0)
            {
                return;
            }

            // Sample current state
            float velocity = SampleVelocity(dt);
            _lastPosition = transform.position;

            // Position controller
            float targetVelocity = ControllerStep(name: "Position", state: ref _positionControllerState, dt: dt, Kp: _positionKp, Ki: _positionKi, Kd: _positionKd, signedError: SignedPositionError(currentPosition: transform.position));

            // Velocity controller
            _throttle = ControllerStep(name: "Velocity", state: ref _velocityControllerState, dt: dt, Kp: _velocityKp, Ki: _velocityKi, Kd: _velocityKd, signedError: targetVelocity - velocity);
        }

        // Simulate moving vehicle
        float acceleration = ThrottleToAcceleration(_throttle);
        _velocity = Mathf.Clamp(_velocity + acceleration * Time.fixedDeltaTime, min: -_maximumSpeed, max: _maximumSpeed);
        transform.position = transform.position + transform.forward * _velocity * Time.fixedDeltaTime;
    }

    private float ControllerStep(string name, ref PIDState state, float dt, float Kp, float Ki, float Kd, float signedError)
    {
        float error = Mathf.Abs(signedError);
        float direction = Mathf.Sign(signedError);

        bool integralEnabled = error <= _integralEnabledDistance;

        if (!state.prevError.HasValue)
        {
            state.prevError = error;
        }

        state.integralError = integralEnabled ? (state.integralError + dt * error) : 0;
        float derivativeError = (error - state.prevError.Value) / dt;

        float targetAbsoluteSignal = Kp * error + Ki * state.integralError + Kd * derivativeError;

        Debug.Log($"{name}: signal={targetAbsoluteSignal * direction}, error={error}, prevError={state.prevError}, integralError={state.integralError}, derivativeError={derivativeError}");

        state.prevError = error;

        return targetAbsoluteSignal * direction;
    }

    private float SignedPositionError(Vector3 currentPosition)
    {
        Vector3 position = Vector3.Dot(target.position - transform.position, transform.forward) * transform.forward + transform.position;
        Vector3 delta = position - transform.position;
        float distance = delta.XZProject().magnitude;
        float sign = Mathf.Sign(Vector3.Dot(delta, transform.forward));
        return sign * distance;
    }

    /// <returns>Velocity relative to forward direction.</returns>
    private float SampleVelocity(float dt)
    {
        Vector3 lastPosition = _lastPosition.HasValue ? _lastPosition.Value : transform.position;
        Vector3 velocityVec = (transform.position - lastPosition) / dt;
        float direction = Mathf.Sign(Vector3.Dot(velocityVec, transform.forward));
        return velocityVec.magnitude * direction;
    }

    private float ThrottleToAcceleration(float throttle)
    {
        return Mathf.Clamp(throttle, min: -1, max: 1) * _maximumAcceleration;
    }
}