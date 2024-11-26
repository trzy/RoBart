/*
 * bluetooth.hpp
 * RoBart
 * Bart Trzynadlowski, 2024
 *
 * Header for Bluetooth (BLE) communication.
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
#ifndef INCLUDED_BLUETOOTH_HPP
#define INCLUDED_BLUETOOTH_HPP

#include <bluefruit.h>

extern void bluetooth_start(ble_connect_callback_t on_connect, ble_disconnect_callback_t on_disconnect, BLECharacteristic::write_cb_t on_received);
extern bool bluetooth_is_connected();
extern bool bluetooth_send(const uint8_t *buffer, uint16_t num_bytes);
extern bool bluetooth_send(const char *str);

#endif  // INCLUDED_BLUETOOTH_HPP