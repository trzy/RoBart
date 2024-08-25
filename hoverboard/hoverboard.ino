/*
 * hoverboard.ino
 * RoBart
 * Bart Trzynadlowski, 2024
 *
 * Hoverboard controller for Adafruit Feather nRF52832 board. Listens for commands from iOS via
 * Bluetooth and drives two RioRand 350W BLDC motor controllers.
 */

#include "nRF52_PWM.h"  // nrF52_PWM package
#include "messages.hpp"
#include "cooperative_task.hpp"
#include "bluetooth.hpp"
#include <algorithm>
#include <cmath>
#include <limits>


/***************************************************************************************************
 Motor Control
***************************************************************************************************/

constexpr uint32_t PIN_LEFT_DIR = 2;    // pin A0
constexpr uint32_t PIN_LEFT_BRAKE = 3;  // pin A1
constexpr uint32_t PIN_LEFT_STOP = 4;   // pin A2
constexpr uint32_t PIN_LEFT_PWM = 5;    // pin A3

constexpr uint32_t PIN_RIGHT_DIR = 11;  // pin 11
constexpr uint32_t PIN_RIGHT_BRAKE = 7; // pin 7
constexpr uint32_t PIN_RIGHT_STOP = 15; // pin 15
constexpr uint32_t PIN_RIGHT_PWM = 16;  // pin 16

static float s_pwm_frequency = 20000.0f;
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
  // Compute duty cycle ticks: [0%,100%] -> [0,65535] (cannot use setPWM() because it erroneously
  // casts to an integer before remapping, making it impossible to specify < 1%)
  magnitude = max(0.0f, min(1.0f, magnitude));
  const uint16_t duty_cycle = uint16_t(round(magnitude * 65535.0f));

  if (motor == Left)
  {
    s_pwm_left->setPWM_Int(PIN_LEFT_PWM, s_pwm_frequency, duty_cycle);
  }
  else
  {
    s_pwm_right->setPWM_Int(PIN_RIGHT_PWM, s_pwm_frequency, duty_cycle);
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

static void cut_motor_power()
{
  speed(Left, 0.0f);
  speed(Right, 0.0f);
  stop(Left, true);
  stop(Right, true);
  brake(Left, false);
  brake(Right, false);
}

static void init_motors()
{
  pinMode(PIN_LEFT_PWM, OUTPUT);
  pinMode(PIN_RIGHT_PWM, OUTPUT);
  s_pwm_left = new nRF52_PWM(PIN_LEFT_PWM, s_pwm_frequency, 0.0f);    // 0 duty cycle: off
  s_pwm_right = new nRF52_PWM(PIN_RIGHT_PWM, s_pwm_frequency, 0.0f);  // 0 duty cycle: off
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
 Watchdog 

 Cut the motors after a certain period of inactivity (i.e., incoming control messages).
***************************************************************************************************/

static bool s_watchdog_enabled = true;
static unsigned long s_watchdog_milliseconds = 2000;
static unsigned long s_watchdog_last_message_received_at = 0;

/*
 * Indicates to the watchdog that the remote side is still actively controlling the hoverboard.
 * Call this whenever a motor control message is received.
 */
static void reset_watchdog_timeout()
{
  s_watchdog_last_message_received_at = millis();
}

static void update_watchdog_settings(const watchdog_message *msg)
{
  s_watchdog_enabled = msg->watchdog_enabled != 0;
  double max_millis = double(std::numeric_limits<unsigned long>::max());
  double millis = std::min(msg->watchdog_seconds * 1e3, max_millis);  // clamp to max
  s_watchdog_milliseconds = (unsigned long) millis;                   // convert to integer
  reset_watchdog_timeout();
  Serial.printf("Watchdog settings updated: enabled=%d, milliseconds=%d\n", s_watchdog_enabled, s_watchdog_milliseconds);
}

/*
 * Checks for watchdog timeout and cuts motor power if necessary. Call this periodically.
 */
static void watchdog_tick()
{
  if (!s_watchdog_enabled)
  {
    return;
  }

  static bool printed_message = false;
  unsigned long now = millis();
  unsigned long millis_since_last_message = now - s_watchdog_last_message_received_at;
  if (millis_since_last_message >= s_watchdog_milliseconds)
  {
    cut_motor_power();
    if (!printed_message)
    {
      Serial.println("Watchdog has cut motor power");
      printed_message = true;
    }
  }
  else
  {
    printed_message = false;
  }
}


/***************************************************************************************************
 Bluetooth Communication
***************************************************************************************************/

static bool s_connected = false;

static void on_peripheral_connect(uint16_t connection_handle)
{
  BLEConnection *connection = Bluefruit.Connection(connection_handle);
  char central_name[32] = { 0 };
  connection->getPeerName(central_name, sizeof(central_name));
  Serial.printf("Connected to %s\n", central_name);
  s_connected = true;
}

static void on_peripheral_disconnect(uint16_t connection_handle, uint8_t reason)
{
  Serial.printf("Disconnected: code 0x%02x\n", reason);
  cut_motor_power();  // stop the motors to prevent a runaway RoBart!
  s_connected = false;
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

    HoverboardMessageID id = HoverboardMessageID(data[1]);
    switch (id)
    {
    case PingMessage:
      if (length == sizeof(ping_message))
      {
        const ping_message *msg = reinterpret_cast<const ping_message *>(data);
        const pong_message response_msg(msg->timestamp);
        bluetooth_send(reinterpret_cast<const uint8_t *>(&response_msg), sizeof(response_msg));
      }
      else
      {
        Serial.printf("Error: ping_message has incorrect length (%d)\n", length);
      }
      break;

    case WatchdogMessage:
      if (length == sizeof(watchdog_message))
      {
        const watchdog_message *msg = reinterpret_cast<const watchdog_message *>(data);
        update_watchdog_settings(msg);
      }
      else
      {
        Serial.printf("Error: watchdog_message has incorrect length (%d)\n", length);
      }
      break;
    
    case PWMMessage:
      if (length == sizeof(pwm_message))
      {
        const pwm_message *msg = reinterpret_cast<const pwm_message *>(data);
        s_pwm_frequency = float(msg->pwm_frequency);
        Serial.printf("PWM frequency: %d Hz\n", msg->pwm_frequency);
      }
      else
      {
        Serial.printf("Error: pwm_message has incorrect length (%d)\n", length);
      }
      break;

    case MotorMessage:
      if (length == sizeof(motor_message))
      {
        const motor_message *msg = reinterpret_cast<const motor_message *>(data);
        const float epsilon = 1e-3f;
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

        reset_watchdog_timeout();
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
  // Blink when disconnected
  if (s_connected)
  {
    digitalWrite(LED_BUILTIN, LOW);
    return;
  }
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
  watchdog_tick();
  s_led_blinker.tick();
}