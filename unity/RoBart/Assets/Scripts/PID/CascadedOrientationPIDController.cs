/*
 * CascadedOrientationController.cs
 * Bart Trzynadlowski, 2024
 * 
 * Orientation PID controller with both an orientation PID controller and angular velocity PID
 * controller in series, analogous to CascadedPIDController (which is for linear motion).
 */

using UnityEngine;

public class CascadedOrientationPIDController : MonoBehaviour
{
    public Transform target;

    [SerializeField]
    private float _maximumAngularAcceleration = 180;

    [SerializeField]
    private float _maximumAngularSpeed = 720;

    [SerializeField]
    private float _controlLoopFrequency = 10;

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

    private float _lastLoopTime = 0;

    private struct PIDState
    {
        public float? prevError;
        public float integralError;
    }

    private Vector3? _lastForward = null;
    private PIDState _orientationControllerState = new PIDState() { prevError = null, integralError = 0 };
    private PIDState _velocityControllerState = new PIDState() { prevError = null, integralError = 0 };

    private float _throttle = 0;
    private float _angularVelocity = 0; // drives the vehicle (but we don't sample it directly in order to be more realistic)

    public float Error
    {
        get { return Mathf.Abs(SignedOrientationError(currentForward: transform.forward, currentPosition: transform.position)); }
    }

    private void OnEnable()
    {
        _lastLoopTime = Time.fixedTime;
        _lastForward = null;
        _orientationControllerState = new PIDState() { prevError = null, integralError = 0 };
        _velocityControllerState = new PIDState() { prevError = null, integralError = 0 };
        _throttle = 0;
        _angularVelocity = 0;
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
            float angularVelocity = SampleAngularVelocity(dt);
            _lastForward = transform.forward;

            // Angular position controller
            float targetAngularVelocity = ControllerStep(name: "AngularPosition", state: ref _orientationControllerState, dt: dt, Kp: _positionKp, Ki: _positionKi, Kd: _positionKd, signedError: SignedOrientationError(currentForward: transform.forward, currentPosition: transform.position));

            // Angular velocity controller
            _throttle = ControllerStep(name: "AngularVelocity", state: ref _velocityControllerState, dt: dt, Kp: _velocityKp, Ki: _velocityKi, Kd: _velocityKd, signedError: targetAngularVelocity - angularVelocity);
        }

        // Simulate moving vehicle
        float angularAcceleration = ThrottleToAngularAcceleration(_throttle);
        _angularVelocity = Mathf.Clamp(_angularVelocity + angularAcceleration * Time.fixedDeltaTime, min: -_maximumAngularSpeed, max: _maximumAngularSpeed);
        transform.Rotate(0, _angularVelocity * Time.fixedDeltaTime, 0);
    }

    private float ControllerStep(string name, ref PIDState state, float dt, float Kp, float Ki, float Kd, float signedError)
    {
        float error = Mathf.Abs(signedError);
        float direction = Mathf.Sign(signedError);

        if (!state.prevError.HasValue)
        {
            state.prevError = error;
        }

        state.integralError = state.integralError + dt * error;
        float derivativeError = (error - state.prevError.Value) / dt;

        float targetAbsoluteSignal = Kp * error + Ki * state.integralError + Kd * derivativeError;

        Debug.Log($"{name}: signal={targetAbsoluteSignal * direction}, error={error}, prevError={state.prevError}, integralError={state.integralError}, derivativeError={derivativeError}");

        state.prevError = error;

        return targetAbsoluteSignal * direction;
    }

    private float SampleAngularVelocity(float dt)
    {
        Vector3 lastForward = _lastForward.HasValue ? _lastForward.Value : transform.forward;
        float deltaAngle = Vector3.SignedAngle(from: lastForward, to: transform.forward, axis: Vector3.up);
        float angularVelocity = deltaAngle / dt;
        return angularVelocity;
    }

    private float SignedOrientationError(Vector3 currentForward, Vector3 currentPosition)
    {
        Vector3 targetForward = (target.position - currentPosition).XZProject().normalized;
        return Vector3.SignedAngle(from: currentForward, to: targetForward, axis: Vector3.up);
    }

    private float ThrottleToAngularAcceleration(float throttle)
    {
        return Mathf.Clamp(throttle, min: -1, max: 1) * _maximumAngularAcceleration;
    }
}