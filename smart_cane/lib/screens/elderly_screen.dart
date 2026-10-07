import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../screens/role_selection_screen.dart';
import '../screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
class ElderlyScreen extends StatefulWidget {
  const ElderlyScreen({Key? key}) : super(key: key);

  @override
  State<ElderlyScreen> createState() => _ElderlyScreenState();
}

class _ElderlyScreenState extends State<ElderlyScreen> {
  bool _isFalling = false;
  bool _isBleConnected = false;
  bool _isBleEnabled = false;
  bool _isGpsEnabled = false;
  bool _isLoading = true;
  
  LatLng _currentLocation = const LatLng(0, 0);
  LatLng? _destination;
  LatLng? _homeLocation;
  final MapController _mapController = MapController();

  late final StreamSubscription<DatabaseEvent> _roleSubscription;
  StreamSubscription<Map<String, dynamic>?>? _serviceSubscription;

  @override
  void initState() {
    super.initState();
    _listenToRoleChanges();
    
    // Yêu cầu quyền và kết nối Background Service
    _initializeBackgroundListener();

    // Đợi tối đa 3 giây nếu service chưa kịp phản hồi
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    });
  }

  void _initializeBackgroundListener() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
      Permission.phone,
      Permission.sms,
      Permission.notification,
      Permission.ignoreBatteryOptimizations,
      Permission.systemAlertWindow,
    ].request();

    final service = FlutterBackgroundService();
    _serviceSubscription = service.on('updateState').listen((event) {
      if (mounted && event != null) {
        setState(() {
          if (event['isFalling'] != null) _isFalling = event['isFalling'];
          if (event['bleConnected'] != null) _isBleConnected = event['bleConnected'];
          if (event['gpsEnabled'] != null) _isGpsEnabled = event['gpsEnabled'];
          if (event['bleEnabled'] != null) _isBleEnabled = event['bleEnabled'];
          _isLoading = false; // Nhận được state thì tắt loading luôn
        });
      }
    });

    service.invoke('requestState');
  }

  void _listenToRoleChanges() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final myDeviceId = prefs.getString('device_id');

    _roleSubscription = FirebaseDatabase.instance.ref('users/${user.uid}').onValue.listen((event) async {
      if (event.snapshot.value == null) {
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const RoleSelectionScreen()));
        return;
      }
      final data = event.snapshot.value as Map<dynamic, dynamic>;
      
      if (data['elderlyDeviceId'] != myDeviceId) {
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const RoleSelectionScreen()));
        return;
      }

      if (data.containsKey('latitude') && data.containsKey('longitude')) {
        if (mounted) {
           setState(() {
              _currentLocation = LatLng(double.parse(data['latitude'].toString()), double.parse(data['longitude'].toString()));
           });
           try {
             _mapController.move(_currentLocation, 16.0);
           } catch(e) {}
        }
      }

      if (data.containsKey('destination')) {
        final destData = data['destination'] as Map<dynamic, dynamic>;
        if (mounted) {
          setState(() {
             _destination = LatLng(double.parse(destData['lat'].toString()), double.parse(destData['lng'].toString()));
          });
        }
      } else {
        if (mounted) setState(() => _destination = null);
      }

      if (data.containsKey('home_location')) {
        final homeData = data['home_location'] as Map<dynamic, dynamic>;
        if (mounted) {
          setState(() {
             _homeLocation = LatLng(double.parse(homeData['lat'].toString()), double.parse(homeData['lng'].toString()));
          });
        }
      } else {
        if (mounted) setState(() => _homeLocation = null);
      }
    });
  }

  @override
  void dispose() {
    _roleSubscription.cancel();
    _serviceSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _openGoogleMapsApp() async {
    if (_currentLocation.latitude == 0) return;
    final colors = AppTheme.colors(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.cardColor,
        title: Text('Mở Google Maps?', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Bạn có muốn mở ứng dụng Google Maps để xem chi tiết vị trí này không?', style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${_currentLocation.latitude},${_currentLocation.longitude}');
              if (!await launchUrl(url)) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể mở Google Maps!')));
              }
            },
            icon: const Icon(Icons.map, color: Colors.white, size: 18),
            label: const Text('Đồng Ý', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(backgroundColor: colors.primaryGreen),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    FlutterBackgroundService().invoke('stopService');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_email');
    await prefs.remove('cached_password');
    await prefs.remove('my_role');
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);

    if (_isLoading) {
      return Scaffold(backgroundColor: colors.background, body: Center(child: CircularProgressIndicator(color: colors.primaryGreen)));
    }
    
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Nửa trên: Bản Bản đồ hiển thị vị trí thực tế
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  if (_currentLocation.latitude == 0)
                    Container(
                      color: colors.cardColor,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: colors.primaryGreen),
                            const SizedBox(height: 16),
                            Text('Đang lấy vị trí GPS...', style: TextStyle(color: colors.textSecondary)),
                          ],
                        ),
                      ),
                    )
                  else
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentLocation,
                        initialZoom: 16.0,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.smart_cane',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _currentLocation,
                              width: 60,
                              height: 60,
                              rotate: true,
                              child: GestureDetector(
                                onTap: _openGoogleMapsApp,
                                child: Icon(Icons.location_on, color: colors.iconBlue, size: 50),
                              ),
                            ),
                            if (_homeLocation != null)
                              Marker(
                                point: _homeLocation!,
                                width: 60,
                                height: 60,
                                rotate: true,
                                child: Icon(Icons.home, color: colors.primaryGreen, size: 40),
                              ),
                            if (_destination != null)
                              Marker(
                                point: _destination!,
                                width: 60,
                                height: 60,
                                rotate: true,
                                child: Icon(Icons.add_location_alt, color: Colors.blue, size: 40),
                              ),
                          ],
                        ),
                      ],
                    ),
                    
                    // Lớp phủ yêu cầu bật Bluetooth/GPS
                    if (!_isBleEnabled || !_isGpsEnabled)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.8),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    !_isBleEnabled ? Icons.bluetooth_disabled : Icons.location_off,
                                    size: 60,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    !_isBleEnabled 
                                      ? 'Vui lòng BẬT BLUETOOTH\nđể kết nối với Gậy Thông Minh' 
                                      : 'Vui lòng BẬT VỊ TRÍ (GPS)\nđể Giám Hộ có thể theo dõi',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 30),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      if (!_isBleEnabled) {
                                        FlutterBluePlus.turnOn();
                                      } else {
                                        Geolocator.openLocationSettings();
                                      }
                                    },
                                    icon: Icon(!_isBleEnabled ? Icons.bluetooth : Icons.location_on, color: Colors.white),
                                    label: Text(!_isBleEnabled ? 'Bật Bluetooth Ngay' : 'Bật Vị Trí', style: const TextStyle(color: Colors.white)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: colors.primaryGreen,
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                ],
              ),
            ),
            
            // Nửa dưới: Điều khiển và Cảnh báo
            Expanded(
              flex: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: const Offset(0, -5))],
                ),
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Trạng thái Ngã (Chỉ hiện khi bị ngã)
                    if (_isFalling)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: colors.warningRed.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: colors.warningRed, width: 2),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 40, color: colors.warningRed),
                            const SizedBox(width: 16),
                            Text('ĐÃ TÉ NGÃ!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.warningRed)),
                          ],
                        ),
                      ),
                      
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cột trái: Trạng thái kết nối
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Bluetooth status
                              GestureDetector(
                                onTap: () {
                                  if (!_isBleEnabled) {
                                    FlutterBluePlus.turnOn();
                                  } else if (!_isBleConnected) {
                                    FlutterBackgroundService().invoke('manualScan');
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: colors.cardColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: !_isBleEnabled ? colors.warningRed : (_isBleConnected ? colors.primaryGreen : Colors.orange)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        !_isBleEnabled ? Icons.bluetooth_disabled : (_isBleConnected ? Icons.bluetooth_connected : Icons.bluetooth_searching), 
                                        color: !_isBleEnabled ? colors.warningRed : (_isBleConnected ? colors.primaryGreen : Colors.orange), 
                                        size: 20
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          !_isBleEnabled ? 'ĐANG TẮT Bluetooth (BẤM VÀO ĐÂY ĐỂ BẬT)' : (_isBleConnected ? 'Gậy đã kết nối' : 'Đang tìm Gậy...'), 
                                          style: TextStyle(
                                            color: !_isBleEnabled ? colors.warningRed : (_isBleConnected ? colors.primaryGreen : Colors.orange), 
                                            fontWeight: FontWeight.bold, 
                                            fontSize: 13
                                          )
                                        )
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // GPS status
                              GestureDetector(
                                onTap: () {
                                  if (!_isGpsEnabled) {
                                    Geolocator.openLocationSettings();
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: colors.cardColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: _isGpsEnabled ? colors.primaryGreen : colors.warningRed),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(_isGpsEnabled ? Icons.location_on : Icons.location_off, color: _isGpsEnabled ? colors.primaryGreen : colors.warningRed, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _isGpsEnabled ? 'GPS đang bật' : 'ĐANG TẮT GPS (BẤM VÀO ĐÂY ĐỂ BẬT)', 
                                          style: TextStyle(
                                            color: _isGpsEnabled ? colors.primaryGreen : colors.warningRed, 
                                            fontWeight: FontWeight.bold, 
                                            fontSize: 13
                                          )
                                        )
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(width: 12),
                        
                        // Cột phải: Các nút dẫn đường
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_homeLocation != null)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                       final url = Uri.parse('google.navigation:q=${_homeLocation!.latitude},${_homeLocation!.longitude}&mode=w');
                                       if (!await launchUrl(url)) {
                                         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể mở Google Maps!')));
                                       }
                                    },
                                    icon: const Icon(Icons.home, color: Colors.white, size: 18),
                                    label: const Text('VỀ NHÀ', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: colors.primaryGreen,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      elevation: 3,
                                    ),
                                  ),
                                ),
                              if (_destination != null)
                                Container(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                       final url = Uri.parse('google.navigation:q=${_destination!.latitude},${_destination!.longitude}&mode=w');
                                       if (!await launchUrl(url)) {
                                         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể mở Google Maps!')));
                                       }
                                    },
                                    icon: const Icon(Icons.directions_walk, color: Colors.white, size: 18),
                                    label: const Text('ĐIỂM HẸN', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue.shade700,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      elevation: 3,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    // Nút đăng xuất và Tắt chạy ngầm
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            FlutterBackgroundService().invoke('stopService');
                            const MethodChannel('com.example.smart_cane/app_killer').invokeMethod('closeAppAndRemoveFromRecents');
                          },
                          icon: const Icon(Icons.power_settings_new, size: 18, color: Colors.orange),
                          label: const Text('Đóng hoàn toàn', style: TextStyle(color: Colors.orange)),
                        ),
                        TextButton.icon(
                          onPressed: _logout,
                          icon: Icon(Icons.logout, size: 18, color: colors.warningRed),
                          label: Text('Đăng xuất', style: TextStyle(color: colors.warningRed)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
