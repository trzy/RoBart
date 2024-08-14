/*
 * hoverboard.ino
 * RoBart
 *
 * Bart Trzynadlowski, 2024
 *
 * Hoverboard controller for Adafruit Feather nRF52832 board. Listens for commands from iOS via
 * Bluetooth and drives two RioRand 350W BLDC motor controllers.
 */

#include "nRF52_PWM.h"  // nrF52_PWM package
#include "messages.hpp"
#include "cooperative_task.hpp"
#include "bluetooth.hpp"
#include <cmath>


/***************************************************************************************************
 Pins
***************************************************************************************************/

constexpr uint32_t PIN_LEFT_DIR = 2;     // A0
constexpr uint32_t PIN_LEFT_BRAKE = 3;   // A1
constexpr uint32_t PIN_LEFT_STOP = 4;    // A2
constexpr uint32_t PIN_LEFT_PWM = 5;     // A3

constexpr uint32_t PIN_RIGHT_DIR = 11;
constexpr uint32_t PIN_RIGHT_BRAKE = 7;
constexpr uint32_t PIN_RIGHT_STOP = 15;
constexpr uint32_t PIN_RIGHT_PWM = 16;


/***************************************************************************************************
 Motor Control
***************************************************************************************************/

constexpr float PWM_FREQUENCY = 20000.0f;
static nRF52_PWM *s_pwm_left = nullptr;
static nRF52_PWM *s_pwm_right = nullptr;

enum MotorSide
{
  Left,
  Right
};

/*
 * Sets motor speed.
 *
 * Parameters:
 *  motor:      Which motor: Left or Right.
 *  magnitude:  0 (stopped) to 1.0 (full speed in currently-set direction).
 */
static void speed(MotorSide motor, float magnitude)
{
  magnitude = max(0.0f, min(100.0f, magnitude * 100.0f));
  if (motor == Left)
  {
    s_pwm_left->setPWM(PIN_LEFT_PWM, PWM_FREQUENCY, magnitude);
  }
  else
  {
    s_pwm_right->setPWM(PIN_RIGHT_PWM, PWM_FREQUENCY, magnitude);
  }
}

/*
 * Sets motor direction. Forward is the same for both motors. That is, the necessary adjustment is
 * made to the right motor, which is wired such that forward on the RioRand board is actually
 * backwards unless corrected.
 *
 * Parameters:
 *  motor:    Which motor: Left or Right.
 *  forward:  Spin in forward direction if true, otherwise reverse.
 */
static void direction(MotorSide motor, bool forward)
{
  if (motor == Right)
  {
    // Correct right motor orientation
    forward = !forward;
  }

  uint32_t pin = motor == Left ? PIN_LEFT_DIR : PIN_RIGHT_DIR;
  if (forward)
  {
    // Forward
    pinMode(pin, INPUT);
  }
  else
  {
    pinMode(pin, OUTPUT);
    digitalWrite(pin, LOW);
  }
}

/*
 * Brakes the motor (using active braking, which will bring it to a sudden and possibly violent
 * stop). Use with care.
 *
 * Parameters:
 *  motor:  Which motor: Left or Right.
 *  active: True to apply brake.
 */
static void brake(MotorSide motor, bool active)
{
  uint32_t pin = motor == Left ? PIN_LEFT_BRAKE : PIN_RIGHT_BRAKE;
  if (active)
  {
    // Apply brake
    digitalWrite(pin, HIGH);
  }
  else
  {
    digitalWrite(pin, LOW);
  }
}

/*
 * Stops the motor, removing power and letting it coast.
 *
 * Parameters:
 *  motor:  Which motor: Left or right.
 *  active: True to stop.
 */
static void stop(MotorSide motor, bool active)
{
  uint32_t pin = motor == Left ? PIN_LEFT_STOP : PIN_RIGHT_STOP;
  if (active)
  {
    // Stop motor (coast to stop)
    pinMode(pin, OUTPUT);
    digitalWrite(pin, LOW);
  }
  else
  {
    // High impedance state to deassert STOP
    pinMode(pin, INPUT);
  }
}

static void init_motors()
{
  pinMode(PIN_LEFT_PWM, OUTPUT);
  pinMode(PIN_RIGHT_PWM, OUTPUT);
  s_pwm_left = new nRF52_PWM(PIN_LEFT_PWM, PWM_FREQUENCY, 0.0f);    // 0 duty cycle: off
  s_pwm_right = new nRF52_PWM(PIN_RIGHT_PWM, PWM_FREQUENCY, 0.0f);  // 0 duty cycle: off
  speed(Left, 0.0f);
  speed(Right, 0.0f);

  pinMode(PIN_LEFT_DIR, OUTPUT);
  pinMode(PIN_RIGHT_DIR, OUTPUT);
  direction(Left, true);
  direction(Right, true);

  pinMode(PIN_LEFT_BRAKE, OUTPUT);
  pinMode(PIN_RIGHT_BRAKE, OUTPUT);
  brake(Left, false);
  brake(Right, false);

  pinMode(PIN_LEFT_STOP, OUTPUT);
  pinMode(PIN_RIGHT_STOP, OUTPUT);
  stop(Left, false);
  stop(Right, false);
}


/***************************************************************************************************
 Bluetooth Communication
***************************************************************************************************/

static void on_peripheral_connect(uint16_t connection_handle)
{
  BLEConnection *connection = Bluefruit.Connection(connection_handle);
  char central_name[32] = { 0 };
  connection->getPeerName(central_name, sizeof(central_name));
  Serial.printf("Connected to %s\n", central_name);
}

static void on_peripheral_disconnect(uint16_t connection_handle, uint8_t reason)
{
  Serial.printf("Disconnected: code 0x%02x\n", reason);

  // Stop the motors to prevent a runaway RoBart!
  speed(Left, 0.0f);
  speed(Right, 0.0f);
  stop(Left, true);
  stop(Right, true);
}

static void on_received(uint16_t connection_handle, BLECharacteristic *characteristic, uint8_t *data, uint16_t length)
{
  if (length >= 2)
  {
    if (data[0] != length)
    {
      Serial.printf("Error: Received %d bytes but message header says %d bytes\n", length, data[0]);
      return;
    }

    MotorMessageID id = MotorMessageID(data[1]);
    switch (id)
    {
    case MotorMessage:
      if (length == sizeof(motor_message))
      {
        const float epsilon = 1e-3f;
        const motor_message *msg = reinterpret_cast<const motor_message *>(data);
        bool left_forward = msg->left_motor_throttle >= 0;
        float left_magnitude = fabs(msg->left_motor_throttle);
        bool left_stopped = left_magnitude < 1e-3f;
        bool right_forward = msg->right_motor_throttle >= 0;
        float right_magnitude = fabs(msg->right_motor_throttle);
        bool right_stopped = right_magnitude < 1e-3f;

        stop(Left, left_stopped);
        stop(Right, right_stopped);
        direction(Left, left_forward);
        direction(Right, right_forward);
        speed(Left, left_magnitude);
        speed(Right, right_magnitude);
      }
      else
      {
        Serial.printf("Error: motor_message has incorrect length (%d)\n", length);
      }
      break;

    default:
      // Ignore
      break;
    }
  }
}


/***************************************************************************************************
 Entry Point and Main Loop
***************************************************************************************************/

static util::cooperative_task<util::millisecond::resolution> s_led_blinker;

static void blink_led(util::time::duration<util::microsecond::resolution> delta, size_t count)
{
  static const bool sequence[] = { true, false, false };
  bool on = sequence[count % (sizeof(sequence) / sizeof(bool))];
  digitalWrite(LED_BUILTIN, on ? HIGH : LOW);
}

void setup()
{
  init_motors();
  Serial.begin(115200);
  s_led_blinker = util::cooperative_task<util::millisecond::resolution>(util::milliseconds(100), blink_led);
  bluetooth_start(on_peripheral_connect, on_peripheral_disconnect, on_received);
  Serial.println("Setup complete");
}

void loop()
{
  //test_sequence();
  s_led_blinker.tick();
}

// For each side, go from 0 to a maximum speed in steps, then backwards.
static void test_sequence()
{
  for (int side = 0; side < 2; side++)
  {
    MotorSide motor = side == 0 ? Left : Right;
    MotorSide other_motor = side == 0 ? Right : Left;

    stop(motor, false);
    stop(other_motor, true);

    for (int dir = 0; dir < 2; dir++)
    {
      bool forward = dir == 0;

      direction(motor, forward);

      // Ramp up from 0 -> max
      float target_throttle = 0.35f;
      int num_steps = 10;
      for (int i = 0; i < num_steps; i++)
      {
        float throttle = float(i) * (target_throttle / float(num_steps));
        speed(motor, throttle);
        delay(1000);
      }

      // Stop for a while
      stop(motor, true);
      delay(3000);
      stop(motor, false);
    }
  }
}