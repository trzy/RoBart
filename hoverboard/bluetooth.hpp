/*
 * bluetooth.hpp
 * RoBart
 *
 * Bart Trzynadlowski, 2024
 *
 * Header for Bluetooth (BLE) communication.
 */

#pragma once
#ifndef INCLUDED_BLUETOOTH_HPP
#define INCLUDED_BLUETOOTH_HPP

#include <bluefruit.h>

extern void bluetooth_start(ble_connect_callback_t on_connect, ble_disconnect_callback_t on_disconnect, BLECharacteristic::write_cb_t on_received);
extern bool bluetooth_is_connected();
extern bool bluetooth_send(const uint8_t *buffer, uint16_t num_bytes);
extern bool bluetooth_send(const char *str);

#endif  // INCLUDED_BLUETOOTH_HPP