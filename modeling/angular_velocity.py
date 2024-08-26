#
# angular_velocity.py
# Bart Trzynadlowski, 2024
#
# Plot measured angular velocities vs. steering input and interpolate steering input for a given
# desired velocity. Steering input is motor PWM duty cycle percentage expressed as a scalar signed
# value. The sign indicates the turn direction: counter-clockwise if positive, clockwise if
# negative. The same value is used to drive both motors but in opposite directions (e.g., to turn
# clockwise with steering=-0.01, the left motor is driven at 0.01 forward and the right motor is
# driven at 0.01 backwards).
#
# The input data was measured using the 'measure_angvel' command using the debug server. First,
# disable the watchdog or set it to a large value (e.g. > 5 seconds), then measure:
#
#   >>watchdog 0
#   >>measure_angvel 0.015 5
#

import argparse
from typing import Tuple

import matplotlib.pyplot as plt
import numpy as np
from scipy import interpolate


def load_data(filename: str) -> Tuple[np.ndarray, np.ndarray]:
    steering = []
    velocity = []
    with open(filename, 'r') as file:
        for line in file:
            t, v = map(float, line.strip().split())
            steering.append(t)
            velocity.append(v)
    return np.array(steering), np.array(velocity)

def plot_data(steering: np.ndarray, velocity: np.ndarray):
    plt.figure(figsize=(10, 6))
    plt.scatter(steering, velocity, color='blue', label='Data points')
    plt.xlabel('Steering (PWM Duty Cycle %)')
    plt.ylabel('Angular Velocity (deg/sec)')
    plt.title('Steering vs. Angular Velocity')
    plt.legend()
    plt.grid(True)
    plt.show()

def get_steering_from_velocity(velocity_value: float, steering: np.ndarray, velocity: np.ndarray) -> float:
    interp_func = interpolate.interp1d(velocity, steering, kind='linear', fill_value='extrapolate')
    return float(interp_func(velocity_value))

def get_velocity_from_steering(steering_value: float, steering: np.ndarray, velocity: np.ndarray) -> float:
    interp_func = interpolate.interp1d(steering, velocity, kind='linear', fill_value='extrapolate')
    return float(interp_func(steering_value))

if __name__ == "__main__":
    parser = argparse.ArgumentParser("angular_velocity")
    parser.add_argument("file", nargs="+", help="Text file containing steering values and angular velocities")
    parser.add_argument("--velocity", metavar="degrees_per_second", action="store", type=float, help="Given an angular velocity, estimate the required steering value")
    parser.add_argument("--steering", metavar="value", action="store", type=float, help="Given a steering value, estimate the resultant angular velocity")
    options = parser.parse_args()

    steering, velocity = load_data(filename=options.file[0])
    if options.velocity is not None:
        steering_estimate = get_steering_from_velocity(velocity_value=options.velocity, steering=steering, velocity=velocity)
        print(f"{options.velocity:.2f} deg/sec -> {steering_estimate:.4f}")
    if options.steering is not None:
        velocity_estimate = get_velocity_from_steering(steering_value=options.steering, steering=steering, velocity=velocity)
        print(f"{options.steering:.4f} -> {velocity_estimate:.2f} deg/sec")
    plot_data(steering=steering, velocity=velocity)

