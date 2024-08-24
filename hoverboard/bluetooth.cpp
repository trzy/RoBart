/*
 * bluetooth.cpp
 * RoBart
 * Bart Trzynadlowski, 2024
 *
 * Bluetooth (BLE) communication with iOS.
 */

 #include "bluetooth.hpp"

static const BLEUuid s_service_id = BLEUuid("df72a6f9-a217-11ee-a726-a4b1c10ba08a");
static const BLEUuid s_rx_id = BLEUuid("76b6bf48-a21a-11ee-8cae-a4b1c10ba08a");
static const BLEUuid s_tx_id = BLEUuid("9472ed74-a21a-11ee-91d6-a4b1c10ba08a");
static BLEService s_service = BLEService(s_service_id);
static BLECharacteristic s_rx = BLECharacteristic(s_rx_id);
static BLECharacteristic s_tx = BLECharacteristic(s_tx_id);
static BLEDis s_device_info;
static uint8_t s_receive_buffer[256];
static uint8_t s_send_buffer[256];

void bluetooth_start(ble_connect_callback_t on_connect, ble_disconnect_callback_t on_disconnect, BLECharacteristic::write_cb_t on_received)
{
  Serial.println("Initializing Bluefruit nRF52 module...");
  Bluefruit.begin();
  Bluefruit.Periph.setConnInterval(9, 24); // min = 9*1.25=11.25 ms, max = 23*1.25=30ms (Adafruit example seems to recommend this for iOS)
  Bluefruit.Periph.setConnectCallback(on_connect);
  Bluefruit.Periph.setDisconnectCallback(on_disconnect);

  s_service.begin();  // must be called before any characteristics' begin()
  
  s_rx.setProperties(CHR_PROPS_READ | CHR_PROPS_WRITE_WO_RESP);
  s_rx.setPermission(SECMODE_NO_ACCESS, SECMODE_OPEN);
  s_rx.setBuffer(s_receive_buffer, sizeof(s_receive_buffer));
  s_rx.setWriteCallback(on_received);
  s_rx.begin();

  s_tx.setProperties(CHR_PROPS_NOTIFY);
  s_tx.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
  s_tx.setBuffer(s_send_buffer, sizeof(s_send_buffer));
  s_tx.begin();

  s_device_info.setManufacturer("Bart Trzynadlowski");
  s_device_info.setModel("iPhone Robot Motor Control Board / nRF52832 Bluefruit Feather");
  s_device_info.begin();

  Serial.println("Starting to advertise...");
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addService(s_service);
  Bluefruit.Advertising.addName();
  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(32, 244); // in unit of 0.625 ms
  Bluefruit.Advertising.setFastTimeout(30);   // number of seconds in fast mode
  Bluefruit.Advertising.start(0);             // 0 = don't stop advertising after N seconds
}

bool bluetooth_is_connected()
{
  return Bluefruit.connected();
}

bool bluetooth_send(const uint8_t *buffer, uint16_t num_bytes)
{
  return s_tx.notify((const void *) buffer, num_bytes);
}

bool bluetooth_send(const char *str)
{
  return s_tx.notify(str);
}