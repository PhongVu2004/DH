import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/role_selection_screen.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:background_sms/background_sms.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  await initializeService();

  final prefs = await SharedPreferences.getInstance();
  final isDarkMode = prefs.getBool('isDarkMode') ?? true;
  themeNotifier.value = isDarkMode ? ThemeMode.dark : ThemeMode.light;

  runApp(const SmartCaneApp());
}

class SmartCaneApp extends StatelessWidget {
  const SmartCaneApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'Gậy Thông Minh',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          home: const AuthWrapper(),
        );
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.colors(context).primaryGreen)));
        }
        
        if (snapshot.hasData && snapshot.data != null) {
          // Đã đăng nhập -> Bắt buộc vào Lobby để check 2 thiết bị
          return const RoleSelectionScreen();
        }
        
        // Chưa đăng nhập -> Hiện Login
        return const LoginScreen();
      },
    );
  }
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'my_foreground_silent', 
    'Cảnh Báo Té Ngã', 
    description: 'Kênh thông báo cho chức năng Giám hộ', 
    importance: Importance.max, // Bắt buộc để hiện pop-up
    playSound: false,
    enableVibration: false,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'my_foreground_silent',
      initialNotificationTitle: 'Smart Cane',
      initialNotificationContent: 'Đang bảo vệ ngầm...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('stopAlarm').listen((event) {
    FlutterRingtonePlayer().stop();
  });

  // Phân luồng chạy ngầm theo vai trò
  final prefs = await SharedPreferences.getInstance();
  final role = prefs.getString('my_role');
  
  if (role == 'elderly') {
    _startElderlyBackgroundLogic(service, flutterLocalNotificationsPlugin);
  } else if (role == 'guardian') {
    _startGuardianBackgroundLogic(service, flutterLocalNotificationsPlugin);
  }
}

void _startElderlyBackgroundLogic(ServiceInstance service, FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin) {
  bool isFalling = false;
  Timer? emergencyTimer;
  String guardianPhone = '';
  BluetoothDevice? caneDevice;
  bool isBleConnected = false;
  LatLng currentLocation = const LatLng(0, 0);

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  void _updateBleStatus(bool status) {
    isBleConnected = status;
    service.invoke('updateState', {'bleConnected': status});
    FirebaseDatabase.instance.ref('users/${user.uid}').update({
      'ble_connected': status,
    });
  }

  // Lắng nghe Firebase để cập nhật số điện thoại và trạng thái ngã (do Giám hộ tắt)
  FirebaseDatabase.instance.ref('users/${user.uid}').onValue.listen((event) {
    if (event.snapshot.value == null) return;
    final data = event.snapshot.value as Map<dynamic, dynamic>;
    if (data.containsKey('guardianPhone')) {
      guardianPhone = data['guardianPhone'].toString();
    }
    if (data.containsKey('is_falling')) {
      bool fbIsFalling = data['is_falling'] == true;
      if (!fbIsFalling && isFalling) {
        isFalling = false;
        emergencyTimer?.cancel();
        service.invoke('updateState', {'isFalling': false});
      }
    }
  });

  // Đăng ký trạng thái Online/Offline (Mạng Internet) chuẩn xác với Firebase Presence
  FirebaseDatabase.instance.ref('.info/connected').onValue.listen((event) {
    final connected = event.snapshot.value as bool? ?? false;
    final onlineRef = FirebaseDatabase.instance.ref('users/${user.uid}/is_online');
    if (connected) {
      onlineRef.onDisconnect().set(false);
      onlineRef.set(true);
    }
  });

  // Theo dõi trạng thái bật/tắt Bluetooth của điện thoại
  FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
    bool isBleOn = (state == BluetoothAdapterState.on);
    service.invoke('updateState', {'bleEnabled': isBleOn});
    FirebaseDatabase.instance.ref('users/${user.uid}').update({'ble_enabled': isBleOn});
  });

  // Theo dõi trạng thái bật/tắt GPS và đẩy lên Firebase
  Geolocator.isLocationServiceEnabled().then((isGpsOn) {
    service.invoke('updateState', {'gpsEnabled': isGpsOn});
    FirebaseDatabase.instance.ref('users/${user.uid}').update({'gps_enabled': isGpsOn});
  });
  Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
    bool isGpsOn = (status == ServiceStatus.enabled);
    service.invoke('updateState', {'gpsEnabled': isGpsOn});
    FirebaseDatabase.instance.ref('users/${user.uid}').update({'gps_enabled': isGpsOn});
  });

  // Lấy vị trí cất giữ cuối cùng (Last Known Location) để tránh lỗi (0,0) ở Bắc Đại Tây Dương
  Geolocator.getLastKnownPosition().then((pos) {
    if (pos != null && currentLocation.latitude == 0) {
      currentLocation = LatLng(pos.latitude, pos.longitude);
      FirebaseDatabase.instance.ref('users/${user.uid}').update({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
      });
    }
  });

  // Lấy vị trí liên tục và cập nhật lên Firebase
  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5)
  ).listen((Position position) {
    currentLocation = LatLng(position.latitude, position.longitude);
    FirebaseDatabase.instance.ref('users/${user.uid}').update({
      'latitude': position.latitude,
      'longitude': position.longitude,
      'ble_connected': isBleConnected,
      'last_update': ServerValue.timestamp,
    });
  });

  void callGuardian() async {
    print("⏳ [BACKGROUND] Đã đếm xong 15s! Tiến hành gọi cho số: $guardianPhone");
    if (guardianPhone.isNotEmpty) {
      try {
        print("✉️ [BACKGROUND] Đang gửi tin nhắn SMS khẩn cấp tới Giám Hộ...");
        final mapLink = 'https://maps.google.com/?q=${currentLocation.latitude},${currentLocation.longitude}';
        final message = "Nguoi gia bi nga! Vi tri: $mapLink";
        SmsStatus smsResult = await BackgroundSms.sendMessage(
          phoneNumber: guardianPhone,
          message: message,
          simSlot: 1, // Thử SIM 1 trước
        );
        
        if (smsResult != SmsStatus.sent) {
          smsResult = await BackgroundSms.sendMessage(
            phoneNumber: guardianPhone,
            message: message,
            simSlot: 2, // Thử SIM 2 nếu SIM 1 lỗi
          );
        }

        if (smsResult != SmsStatus.sent) {
          smsResult = await BackgroundSms.sendMessage(
            phoneNumber: guardianPhone,
            message: message, // Thử Default nếu cả 2 SIM lỗi
          );
        }

        if (smsResult == SmsStatus.sent) {
          print("✅ [BACKGROUND] Đã gửi SMS khẩn cấp thành công!");
        } else {
          print("⚠️ [BACKGROUND] Gửi SMS thất bại sau mọi nỗ lực! Trạng thái: $smsResult");
        }
      } catch (e) {
        print("❌ [BACKGROUND] Lỗi khi gửi SMS ngầm: $e");
      }

      isFalling = false;
      emergencyTimer?.cancel();
      FirebaseDatabase.instance.ref('users/${user.uid}').update({'is_falling': false});
      service.invoke('updateState', {'isFalling': false});
    } else {
      print("⚠️ [BACKGROUND] Không gửi được vì số điện thoại giám hộ đang TRỐNG!");
    }
  }

  void handleFallDetected() async {
    if (isFalling) return; // Đã báo ngã rồi thì không reset timer
    isFalling = true;
    service.invoke('updateState', {'isFalling': true});
    
    // Nếu rớt mạng và chưa có tọa độ GPS nào, ráng nặn ra 1 cái tọa độ khẩn cấp (cho 3 giây)
    if (currentLocation.latitude == 0) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          timeLimit: const Duration(seconds: 3),
          desiredAccuracy: LocationAccuracy.medium
        );
        currentLocation = LatLng(pos.latitude, pos.longitude);
      } catch (e) {
        print("⚠️ [BACKGROUND] Không ép được GPS khẩn cấp: $e");
      }
    }

    final url = 'https://maps.google.com/?q=${currentLocation.latitude},${currentLocation.longitude}';
    final localTime = DateTime.now().millisecondsSinceEpoch;
    FirebaseDatabase.instance.ref('users/${user.uid}').update({
      'is_falling': true,
      'timestamp': ServerValue.timestamp, // Giữ nguyên để tra cứu server time
      'local_fall_timestamp': localTime,  // Dùng để đo đếm độ trễ do Offline
      'fall_location_url': url,
    });

    emergencyTimer?.cancel();
    emergencyTimer = Timer(const Duration(seconds: 15), () {
      if (isFalling) {
        callGuardian();
      }
    });
  }

  StreamSubscription<List<ScanResult>>? scanSubscription;
  StreamSubscription<List<int>>? characteristicSubscription;

  void startAutoConnect(String macId) async {
    BluetoothDevice device = BluetoothDevice.fromId(macId);
    caneDevice = device;
    
    // Lắng nghe trạng thái kết nối
    device.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.connected) {
        print("✅ [BACKGROUND] Đã AUTO-CONNECT thành công!");
        _updateBleStatus(true);
        
        try {
          List<BluetoothService> services = await device.discoverServices();
          for (BluetoothService s in services) {
            if (s.uuid.toString() == "4fafc201-1fb5-459e-8fcc-c5c9c331914b") {
              for (BluetoothCharacteristic c in s.characteristics) {
                if (c.uuid.toString() == "beb5483e-36e1-4688-b7f5-ea07361b26a9") {
                  print("✅ [BACKGROUND] Đã đăng ký lắng nghe Té Ngã!");
                  await c.setNotifyValue(true);
                  
                  // Xóa listener cũ tránh rác bộ nhớ sau nhiều lần kết nối
                  characteristicSubscription?.cancel();
                  characteristicSubscription = c.lastValueStream.listen((value) {
                    if (value.isNotEmpty && String.fromCharCodes(value) == "1") {
                      handleFallDetected();
                    }
                  });
                }
              }
            }
          }
        } catch (e) {
          print("❌ [BACKGROUND] Lỗi khi discoverServices: $e");
        }
      } else if (state == BluetoothConnectionState.disconnected) {
        print("⚠️ [BACKGROUND] Gậy ngắt kết nối (Sẽ tự động thử kết nối lại...)");
        _updateBleStatus(false);
      }
    });

    // Vòng lặp vĩnh cửu: Chủ động kết nối (Direct Connect)
    // Không dùng autoConnect:true vì Android sẽ tự xóa lệnh sau 15p Doze mode
    while (true) {
      if (!isBleConnected && FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
        try {
          // Kết nối trực tiếp, timeout sau 10s nếu gậy không ở gần
          print("🔄 [BACKGROUND] Đang chủ động gửi lệnh kết nối trực tiếp...");
          await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));
        } catch (e) {
          // Timeout hoặc lỗi, kệ nó, vòng lặp sẽ ngủ 5s rồi thử lại
          print("⚠️ [BACKGROUND] Thử kết nối thất bại, đợi 5s thử lại...");
        }
      }
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  void scanAndConnect() async {
    if (isBleConnected) return;
    
    // Đợi đến khi Bluetooth thực sự BẬT (tránh lỗi ngáo khi service vừa khởi động lại)
    await FlutterBluePlus.adapterState.where((s) => s == BluetoothAdapterState.on).first;

    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    } catch (e) {}
    
    scanSubscription?.cancel();

    print("🔍 [BACKGROUND] Bắt đầu quét tìm gậy...");
    
    scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        String pName = r.device.platformName;
        String aName = r.device.advName ?? r.advertisementData.advName;
        
        if (pName.contains("SmartCan") || aName.contains("SmartCan") || pName.contains("Smart Can") || aName.contains("Smart Can")) {
          print("🎯 [BACKGROUND] ĐÃ TÌM THẤY GẬY! Lưu MAC Address và chuyển sang AutoConnect...");
          scanSubscription?.cancel();
          try {
            await FlutterBluePlus.stopScan();
          } catch(e) {}
          
          caneDevice = r.device;
          
          // Lưu MAC Address
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cane_mac_address', r.device.remoteId.str);
          
          // Chuyển sang cơ chế AutoConnect
          startAutoConnect(r.device.remoteId.str);
          
          break; // Đã tìm thấy gậy
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      
      // Hết 15s mà không thấy thiết bị và chưa kết nối thì quét lại
      if (!isBleConnected) {
        await Future.delayed(const Duration(seconds: 2));
        scanAndConnect();
      }
    } catch (e) {
      print("❌ [BACKGROUND] Lỗi khi startScan: $e");
      await Future.delayed(const Duration(seconds: 2));
      scanAndConnect();
    }
  }

  // Khởi động bằng cách kiểm tra xem đã có MAC Address lưu chưa
  SharedPreferences.getInstance().then((prefs) {
    String? savedMac = prefs.getString('cane_mac_address');
    if (savedMac != null && savedMac.isNotEmpty) {
      print("🔄 [BACKGROUND] Tìm thấy MAC Address cũ ($savedMac), Bắt đầu AutoConnect...");
      startAutoConnect(savedMac);
    } else {
      print("🔍 [BACKGROUND] Lần đầu chạy, tiến hành quét...");
      scanAndConnect();
    }
  });

  // Cho phép UI bề mặt kết nối thủ công (Force Rescan)
  service.on('manualScan').listen((event) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cane_mac_address'); // Xóa MAC cũ
    if (caneDevice != null) {
      await caneDevice!.disconnect();
    }
    _updateBleStatus(false);
    scanAndConnect();
  });

  // Trả lời UI bề mặt khi UI vừa được mở lên
    service.on('requestState').listen((event) async {
      final isGpsOn = await Geolocator.isLocationServiceEnabled();
      final isBleOn = FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;
      service.invoke('updateState', {
        'isFalling': isFalling,
        'bleConnected': isBleConnected,
        'gpsEnabled': isGpsOn,
        'bleEnabled': isBleOn,
      });
    });

  // Yêu cầu gọi khẩn cấp bằng tay từ UI
  service.on('manualCall').listen((event) {
     callGuardian();
  });

  // Bắt đầu quét ngay khi khởi động service
  scanAndConnect();
}

void _startGuardianBackgroundLogic(ServiceInstance service, FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin) {
  Timer.periodic(const Duration(seconds: 3), (timer) async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('my_role');
    
    if (role == 'guardian') {
       final user = FirebaseAuth.instance.currentUser;
       if (user != null) {
          final snapshot = await FirebaseDatabase.instance.ref('users/${user.uid}/is_falling').get();
          if (snapshot.exists && snapshot.value == true) {
             final lastNotif = prefs.getInt('last_notif_time') ?? 0;
             final now = DateTime.now().millisecondsSinceEpoch;
             if (now - lastNotif > 15000) { 
                await prefs.reload(); 
                prefs.setInt('last_notif_time', now);
                 var ringtone = prefs.getString('alarm_ringtone') ?? 'alarm';
                 if (ringtone != 'alarm' && ringtone != 'ringtone') {
                   ringtone = 'alarm';
                 }
                 
                 if (ringtone == 'alarm') {
                   FlutterRingtonePlayer().playAlarm();
                 } else {
                   FlutterRingtonePlayer().playRingtone();
                 }

                 flutterLocalNotificationsPlugin.show(
                   999,
                   '🚨 PHÁT HIỆN TÉ NGÃ! 🚨',
                   'Ông/Bà vừa bị ngã! Mở app ngay để xem vị trí!',
                   const NotificationDetails(
                     android: AndroidNotificationDetails(
                       'my_foreground_silent',
                       'Cảnh Báo Té Ngã',
                       icon: '@mipmap/ic_launcher',
                       importance: Importance.max,
                       priority: Priority.high,
                       fullScreenIntent: true,
                       enableVibration: false,
                       playSound: false,
                     ),
                   ),
                 );
              }
           }
       }
    }
  });
}
