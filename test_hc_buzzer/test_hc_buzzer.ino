#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>

#define BUZZER_PIN 5
#define VIBRATOR_PIN 6
#define I2C_SDA_PIN 8
#define I2C_SCL_PIN 9

Adafruit_MPU6050 mpu;

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("\n\n=========================================");
  Serial.println("BÀI TEST MPU6050 ĐIỀU KHIỂN CÒI & RUNG");
  Serial.println("=========================================");
  
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(VIBRATOR_PIN, OUTPUT);

  // Kêu 1 tiếng bíp ngắn để báo hiệu khởi động
  Serial.println("Đang test còi khởi động...");
  digitalWrite(BUZZER_PIN, HIGH);
  tone(BUZZER_PIN, 2000);
  delay(500);
  digitalWrite(BUZZER_PIN, LOW);
  noTone(BUZZER_PIN);

  // Khởi tạo MPU6050
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  if (!mpu.begin()) {
    Serial.println("❌ LỖI: Không tìm thấy MPU6050!");
    while (1) {
      delay(10);
    }
  }
  Serial.println("✅ MPU6050 đã sẵn sàng!");
  mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
}

void loop() {
  sensors_event_t a, g, temp;
  mpu.getEvent(&a, &g, &temp);

  float totalAccel = sqrt(a.acceleration.x * a.acceleration.x + 
                          a.acceleration.y * a.acceleration.y + 
                          a.acceleration.z * a.acceleration.z);

  Serial.print("📊 Gia tốc hiện tại: ");
  Serial.print(totalAccel);
  Serial.print(" m/s^2 ---> ");

  if (totalAccel > 25.0) {
    Serial.println("🚨 PHÁT HIỆN TÉ NGÃ! KÍCH HOẠT CÒI VÀ RUNG!");
    
    // Bật Rung và Còi
    digitalWrite(VIBRATOR_PIN, HIGH);
    digitalWrite(BUZZER_PIN, HIGH); 
    tone(BUZZER_PIN, 2000);
    
    delay(2000); 
    
    // Tắt Rung và Còi
    digitalWrite(VIBRATOR_PIN, LOW);
    digitalWrite(BUZZER_PIN, LOW);
    noTone(BUZZER_PIN);
    Serial.println("✅ Đã tắt.");
  } else {
    Serial.println("Bình thường");
  }

  delay(500);
}
