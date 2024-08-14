/*
 * messages.hpp
 * RoBart
 *
 * Bart Trzynadlowski, 2024
 *
 * Defines messages exchanged with iOS. Must be kept in sync with iOS project.
 */

#pragma once
#ifndef INCLUDED_MESSAGES_HPP
#define INCLUDED_MESSAGES_HPP

#include <algorithm>
#include <cstdint>
#include <cstring>

#pragma pack(push, 1)

#define VALIDATE_MESSAGE_SIZE(message) static_assert(sizeof(message) <= 256)

// Add new messages to end. Do not reorder. Leave deprecated messages in place but rename them.
enum MotorMessageID: uint8_t
{
  MotorMessage = 0x10 // direct motor control
};

struct message_header
{
  const uint8_t num_bytes;
  const MotorMessageID id;
  
  message_header(MotorMessageID id, uint8_t num_bytes)
    : num_bytes(num_bytes),
      id(id)
  {
  }
};

struct motor_message: public message_header
{
  const float left_motor_throttle;  // [-1,1]
  const float right_motor_throttle; // [-1,1]

  motor_message(float left, float right)
    : message_header(MotorMessageID::MotorMessage, uint8_t(sizeof(*this))),
      left_motor_throttle(left),
      right_motor_throttle(right)
  {
  }
};

VALIDATE_MESSAGE_SIZE(motor_message);

#pragma pack(pop)

#endif  // INCLUDED_MESSAGES_HPP