#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#include "config.h"

Adafruit_MPU6050 mpu;

// Biến Bluetooth
BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristicFall = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Trạng thái còi & rung
bool isAlarmActive = false;
unsigned long alarmStartTime = 0;

// Callbacks để bắt sự kiện kết nối BLE
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("📱 APP ĐÃ KẾT NỐI BLUETOOTH!");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("📱 APP ĐÃ NGẮT KẾT NỐI!");
    }
};

void setup() {
  Serial.begin(115200);
  Serial.println("=========================================");
  Serial.println("KHỞI ĐỘNG GẬY THÔNG MINH (BLE + MPU6050)");
  Serial.println("=========================================");
  
  // 1. Cài đặt I/O
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(VIBRATOR_PIN, OUTPUT);

  // 2. Khởi tạo MPU6050
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN); 
  if (!mpu.begin()) {
    Serial.println("❌ LỖI: Không tìm thấy MPU6050!");
  } else {
    Serial.println("✅ MPU6050 đã kết nối thành công!");
    mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
  }

  // 3. Khởi tạo Bluetooth BLE
  BLEDevice::init(BLE_DEVICE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(BLE_SERVICE_UUID);

  // Đặc tính (Characteristic) báo té ngã
  pCharacteristicFall = pService->createCharacteristic(
                      BLE_CHARACTERISTIC_FALL,
                      BLECharacteristic::PROPERTY_READ   |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );
  pCharacteristicFall->addDescriptor(new BLE2902());
  // Mặc định là 0 (Bình thường)
  pCharacteristicFall->setValue("0");

  pService->start();
  
  // Phát sóng BLE
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(BLE_SERVICE_UUID);
  pAdvertising->setScanResponse(false);
  pAdvertising->setMinPreferred(0x0);
  BLEDevice::startAdvertising();
  
  Serial.println("✅ Bluetooth đang phát sóng! Đợi App kết nối...");
}

void loop() {
  // Quản lý trạng thái kết nối Bluetooth
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); 
      pServer->startAdvertising(); 
      Serial.println("🔄 Bắt đầu phát sóng lại Bluetooth...");
      oldDeviceConnected = deviceConnected;
  }
  if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
  }

  // Đọc cảm biến té ngã
  sensors_event_t a, g, temp;
  mpu.getEvent(&a, &g, &temp);
  float totalAccel = sqrt(a.acceleration.x * a.acceleration.x + 
                          a.acceleration.y * a.acceleration.y + 
                          a.acceleration.z * a.acceleration.z);

  // Xử lý té ngã (Gia tốc > 25)
  if (totalAccel > 25.0 && !isAlarmActive) {
    Serial.println("🚨 PHÁT HIỆN TÉ NGÃ!");
    
    // 1. Kích hoạt Còi và Rung
    digitalWrite(VIBRATOR_PIN, HIGH);
    digitalWrite(BUZZER_PIN, HIGH); 
    tone(BUZZER_PIN, 2000);
    
    isAlarmActive = true;
    alarmStartTime = millis();

    // 2. Gửi tín hiệu "1" qua Bluetooth cho App
    if (deviceConnected) {
      pCharacteristicFall->setValue("1");
      pCharacteristicFall->notify();
      Serial.println("📡 Đã bắn tín hiệu NGÃ lên App!");
    }
  }

  // Tắt báo động sau 3 giây
  if (isAlarmActive && (millis() - alarmStartTime > 3000)) {
    digitalWrite(VIBRATOR_PIN, LOW);
    digitalWrite(BUZZER_PIN, LOW);
    noTone(BUZZER_PIN);
    isAlarmActive = false;
    
    // Gửi tín hiệu "0" qua Bluetooth cho App để reset
    if (deviceConnected) {
      pCharacteristicFall->setValue("0");
      pCharacteristicFall->notify();
    }
    Serial.println("✅ Đã tắt báo động phần cứng.");
  }

  delay(200); // Tốc độ quét 5 lần/giây
}
