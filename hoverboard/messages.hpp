/*
 * messages.hpp
 * RoBart
 * Bart Trzynadlowski, 2024
 *
 * Defines messages exchanged with iOS. Must be kept in sync with iOS project.
 *
 * This file is part of RoBart.
 *
 * RoBart is free software: you can redistribute it and/or modify it under the
 * terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version.
 *
 * RoBart is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with RoBart. If not, see <http://www.gnu.org/licenses/>.
 */

#pragma once
#ifndef INCLUDED_MESSAGES_HPP
#define INCLUDED_MESSAGES_HPP

#include <algorithm>
#include <cstdint>
#include <cstring>

#pragma pack(push, 1)

// We limit messages to 256 bytes over Bluetooth
#define VALIDATE_MESSAGE_SIZE(message) static_assert(sizeof(message) <= 256)

// Add new messages to end. Do not reorder. Leave deprecated messages in place but rename them.
enum HoverboardMessageID: uint32_t
{
  PingMessage = 0x01,     // ping with sender timestamp
  PongMessage = 0x02,     // pong message with timestamp from ping
  WatchdogMessage = 0x03, // watchdog settings
  PWMMessage = 0x04,      // PWM settings
  MotorMessage = 0x10     // direct motor control
};

struct message_header
{
  const uint32_t num_bytes;
  const HoverboardMessageID id;
  
  message_header(HoverboardMessageID id, uint8_t num_bytes)
    : num_bytes(num_bytes),
      id(id)
  {
  }
};

struct ping_message: public message_header
{
  const double timestamp;

  ping_message(double timestamp)
    : message_header(HoverboardMessageID::PingMessage, uint8_t(sizeof(*this))),
      timestamp(timestamp)
  {
  }
};

VALIDATE_MESSAGE_SIZE(ping_message);

struct pong_message: public message_header
{
  const double timestamp;

  pong_message(double timestamp)
    : message_header(HoverboardMessageID::PongMessage, uint8_t(sizeof(*this))),
      timestamp(timestamp)
  {
  }
};

VALIDATE_MESSAGE_SIZE(pong_message);

struct watchdog_message: public message_header
{
  const uint8_t watchdog_enabled;
  const double watchdog_seconds;

  watchdog_message(uint8_t watchdog_enabled, double watchdog_seconds)
    : message_header(HoverboardMessageID::WatchdogMessage, uint8_t(sizeof(*this))),
      watchdog_enabled(watchdog_enabled),
      watchdog_seconds(watchdog_seconds)
  {
  }
};

VALIDATE_MESSAGE_SIZE(watchdog_message);

struct pwm_message: public message_header
{
  const uint16_t pwm_frequency;

  pwm_message(uint16_t pwm_frequency)
    : message_header(HoverboardMessageID::PWMMessage, uint8_t(sizeof(*this))),
      pwm_frequency(pwm_frequency)
  {
  }
};

VALIDATE_MESSAGE_SIZE(pwm_message);

struct motor_message: public message_header
{
  const float left_motor_throttle;  // [-1,1]
  const float right_motor_throttle; // [-1,1]

  motor_message(float left, float right)
    : message_header(HoverboardMessageID::MotorMessage, uint8_t(sizeof(*this))),
      left_motor_throttle(left),
      right_motor_throttle(right)
  {
  }
};

VALIDATE_MESSAGE_SIZE(motor_message);

#pragma pack(pop)

#endif  // INCLUDED_MESSAGES_HPP