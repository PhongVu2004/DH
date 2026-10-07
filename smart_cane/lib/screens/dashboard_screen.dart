import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../screens/role_selection_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isFallen = false;
  bool _isCaneConnected = true;
  bool? _lastIsElderlyOnline;
  bool? _lastIsElderlyGpsEnabled;
  bool? _lastIsElderlyBleEnabled;
  bool? _lastIsCaneConnected;
  bool _isElderlyGpsEnabled = true;
  bool _isElderlyBleEnabled = true;
  bool _isElderlyOnline = true;
  String? _selectingLocationType;
  LatLng? _destinationLocation;
  LatLng? _homeLocation;
  LatLng _currentLocation = const LatLng(0, 0);
  
  List<String> _alertHistory = [];
  bool _isLoading = true;
  late final StreamSubscription<DatabaseEvent> _roleSubscription;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _listenToFirebase();
    
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _requestPermissions() async {
    // Xin quyền Thông Báo, Tắt Tối Ưu Hóa Pin và Hiển thị trên ứng dụng khác
    await [
      Permission.notification,
      Permission.ignoreBatteryOptimizations,
      Permission.systemAlertWindow,
    ].request();
  }



  void _listenToFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final myDeviceId = prefs.getString('device_id');
    bool wasFallen = false;

    _roleSubscription = FirebaseDatabase.instance.ref('users/${user.uid}').onValue.listen((event) {
      if (event.snapshot.value == null) {
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const RoleSelectionScreen()));
        return;
      }

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      if (data['guardianDeviceId'] != myDeviceId) {
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const RoleSelectionScreen()));
        return;
      }

      setState(() {
        if (data.containsKey('destination')) {
          final destData = data['destination'] as Map<dynamic, dynamic>;
          _destinationLocation = LatLng(double.parse(destData['lat'].toString()), double.parse(destData['lng'].toString()));
        } else {
          _destinationLocation = null;
        }

        if (data.containsKey('home_location')) {
          final homeData = data['home_location'] as Map<dynamic, dynamic>;
          _homeLocation = LatLng(double.parse(homeData['lat'].toString()), double.parse(homeData['lng'].toString()));
        } else {
          _homeLocation = null;
        }
        
        // Đồng bộ lịch sử từ Firebase
        if (data.containsKey('alert_history')) {
          final historyMap = data['alert_history'] as Map<dynamic, dynamic>;
          final list = historyMap.values.toList();
          list.sort((a, b) => (b['timestamp'] as num).compareTo(a['timestamp'] as num));
          _alertHistory = list.map((e) => jsonEncode(e)).toList();
        } else {
          _alertHistory = [];
        }

        if (data.containsKey('gps_enabled')) {
          final currentGps = data['gps_enabled'] == true;
          if (_lastIsElderlyGpsEnabled != null && _lastIsElderlyGpsEnabled != currentGps) {
            _addAlertToFirebase(currentGps ? 'Thông tin: Người Già ĐÃ BẬT lại GPS' : 'Cảnh báo: Người Già ĐÃ TẮT GPS');
          }
          _lastIsElderlyGpsEnabled = currentGps;
          _isElderlyGpsEnabled = currentGps;
        } else {
          _isElderlyGpsEnabled = true; 
        }

        if (data.containsKey('is_online')) {
          final currentOnline = data['is_online'] == true;
          if (_lastIsElderlyOnline != null && _lastIsElderlyOnline != currentOnline) {
            if (!currentOnline) {
              _addAlertToFirebase('Cảnh báo: Người Già ĐÃ MẤT KẾT NỐI Mạng (WiFi/4G)');
            } else {
              _resolveLastWifiLoss();
            }
          }
          _lastIsElderlyOnline = currentOnline;
          _isElderlyOnline = currentOnline;
        } else {
          _isElderlyOnline = true; 
        }

        if (data.containsKey('ble_enabled')) {
          final currentBleEnabled = data['ble_enabled'] == true;
          if (_lastIsElderlyBleEnabled != null && _lastIsElderlyBleEnabled != currentBleEnabled) {
            _addAlertToFirebase(currentBleEnabled ? 'Thông tin: Người Già ĐÃ BẬT lại Bluetooth' : 'Cảnh báo: Người Già ĐÃ TẮT Bluetooth!');
          }
          _lastIsElderlyBleEnabled = currentBleEnabled;
          _isElderlyBleEnabled = currentBleEnabled;
        } else {
          _isElderlyBleEnabled = true;
        }

        if (data.containsKey('ble_connected')) {
          final currentBle = data['ble_connected'] == true;
          if (_lastIsCaneConnected != null && _lastIsCaneConnected != currentBle) {
            _addAlertToFirebase(currentBle ? 'Thông tin: Gậy ĐÃ KẾT NỐI lại với điện thoại' : 'Cảnh báo: Gậy ĐÃ MẤT KẾT NỐI Bluetooth');
          }
          _lastIsCaneConnected = currentBle;
          _isCaneConnected = currentBle;
        } else {
          _isCaneConnected = false;
        }

        if (data.containsKey('latitude') && data.containsKey('longitude')) {
          _currentLocation = LatLng((data['latitude'] as num).toDouble(), (data['longitude'] as num).toDouble());
          if (_currentLocation.latitude != 0 && _isLoading == false) {
             _mapController.move(_currentLocation, 16.0);
          }
        }

        if (data.containsKey('is_falling')) {
          _isFallen = data['is_falling'] == true;
          if (_isFallen && !wasFallen) {
            final fallTime = data['local_fall_timestamp'] ?? 0;
            final now = DateTime.now().millisecondsSinceEpoch;
            
            // Nếu thời gian ngã thực tế (local time của máy già) đã trôi qua hơn 1 phút 
            // (Thường là do máy già bị mất mạng, giờ mới kết nối lại và đồng bộ bù)
            if (fallTime > 0 && (now - fallTime) > 60000) {
               _addAlertToFirebase('Người Già đã ngã (trong lúc mất mạng)');
               if (mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                   content: Text('Cập nhật: Có 1 sự cố té ngã xảy ra trong lúc Người Già mất kết nối mạng!'),
                   backgroundColor: Colors.orange,
                   duration: Duration(seconds: 10),
                 ));
               }
            } else {
               _addAlertToFirebase('PHÁT HIỆN TÉ NGÃ KHẨN CẤP!');
               _playAlarmAndShowDialog();
            }
          } else if (!_isFallen && wasFallen) {
             FlutterRingtonePlayer().stop(); // Ngừng báo động khi ông/bà đã an toàn
          }
          wasFallen = _isFallen;
        }
      });
    });
  }

  Future<void> _addAlertToFirebase(String message) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    // Ngăn chặn việc gửi 2 thông báo y hệt nhau trong vòng 1 phút
    final lastAlerts = _alertHistory.take(3).toList();
    for (final jsonStr in lastAlerts) {
       try {
         final map = jsonDecode(jsonStr);
         if (map['message'] == message) {
             final timeDiff = timestamp - (map['timestamp'] as num).toInt();
             if (timeDiff < 60000) return; // Bỏ qua nếu tin nhắn y hệt vừa được gửi trong 60 giây qua
         }
       } catch (e) {}
    }

    final timeStr = DateFormat('HH:mm - dd/MM/yyyy').format(DateTime.now());
    
    final alertData = {
      'message': message,
      'time': timeStr,
      'lat': _currentLocation.latitude,
      'lng': _currentLocation.longitude,
      'timestamp': timestamp,
      'map_url': 'https://www.google.com/maps/search/?api=1&query=${_currentLocation.latitude},${_currentLocation.longitude}',
    };
    
    final ref = FirebaseDatabase.instance.ref('users/${user.uid}/alert_history');
    await ref.push().set(alertData);
    
    // Giới hạn 50 cái (Xóa bớt nếu vượt quá 50 để lưu được nhiều sự kiện hệ thống hơn)
    final snapshot = await ref.orderByChild('timestamp').get();
    if (snapshot.children.length > 50) {
      final oldestKey = snapshot.children.first.key;
      if (oldestKey != null) {
        await ref.child(oldestKey).remove();
      }
    }
  }

  Future<void> _resolveLastWifiLoss() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final ref = FirebaseDatabase.instance.ref('users/${user.uid}/alert_history');
      final snapshot = await ref.get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        String? targetKey;
        int maxTimestamp = 0;
        
        data.forEach((key, value) {
          final map = value as Map<dynamic, dynamic>;
          if (map['message'].toString().contains('MẤT KẾT NỐI Mạng') && !map.containsKey('resolved_time')) {
            final ts = (map['timestamp'] as num).toInt();
            if (ts > maxTimestamp) {
              maxTimestamp = ts;
              targetKey = key.toString();
            }
          }
        });

        if (targetKey != null) {
          final nowFormat = DateFormat('HH:mm - dd/MM/yyyy').format(DateTime.now());
          await ref.child(targetKey!).update({
            'resolved_time': nowFormat,
            'message': 'Sự cố Mạng (Đã kết nối lại)',
          });
        }
      }
    } catch (e) {
      debugPrint('Error resolving wifi loss: $e');
    }
  }
  
  void _playAlarmAndShowDialog() async {
    
    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      // Rung dồn dập trong đúng 15 giây (Mỗi chu kỳ nghỉ 0.5s, rung 1s, lặp 10 lần = 15s)
      Vibration.vibrate(pattern: List.generate(20, (index) => index % 2 == 0 ? 500 : 1000));
    }
    
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.colors(context).cardColor,
          title: const Text('🚨 BÁO ĐỘNG TÉ NGÃ 🚨', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          content: const Text('Phát hiện ông/bà vừa té ngã. Bản đồ đã cập nhật vị trí mới nhất!'),
          actions: [
            TextButton(
              onPressed: () {
                FlutterRingtonePlayer().stop();
                FlutterBackgroundService().invoke("stopAlarm");
                Vibration.cancel();
                _resetFallStatus();
                Navigator.pop(context);
              },
              child: const Text('Đã Rõ', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                FlutterRingtonePlayer().stop();
                FlutterBackgroundService().invoke("stopAlarm");
                Vibration.cancel();
                _resetFallStatus();
                Navigator.pop(context);
                _openGoogleMapsApp(); // Mở app ngoài nếu cần
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Chỉ Đường (Google Maps)', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _resetFallStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseDatabase.instance.ref('users/${user.uid}').update({
        'is_falling': false,
      });
    }
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

  void _showDetails(Map<String, dynamic> data) {
    final colors = AppTheme.colors(context);
    final msg = data['message'].toString();
    final isFall = msg.toLowerCase().contains('ngã');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.cardColor,
        title: Text(isFall ? 'Chi tiết Báo Động' : 'Chi tiết Sự Kiện', style: TextStyle(color: isFall ? Colors.red : colors.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data.containsKey('resolved_time') ? 'Mất mạng lúc: ${data['time']}' : 'Thời gian: ${data['time']}', style: TextStyle(color: colors.textPrimary, fontSize: 16)),
            if (data.containsKey('resolved_time')) ...[
              const SizedBox(height: 5),
              Text('Khôi phục lúc: ${data['resolved_time']}', style: TextStyle(color: colors.primaryGreen, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
            const SizedBox(height: 10),
            Text(isFall ? 'Đã phát hiện người dùng bị ngã tại vị trí này.' : (data.containsKey('resolved_time') ? 'Máy người già đã tự động kết nối lại mạng thành công.' : msg), style: TextStyle(color: colors.textSecondary)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng', style: TextStyle(color: Colors.grey)),
          ),
          if (isFall)
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${data['lat']},${data['lng']}');
                if (!await launchUrl(url)) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể mở Google Maps!')));
                }
              },
              icon: const Icon(Icons.directions, color: Colors.white, size: 18),
              label: const Text('Chỉ Đường', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            ),
        ],
      ),
    );
  }

  IconData _getIconForMessage(String msg) {
    final lowerMsg = msg.toLowerCase();
    if (lowerMsg.contains('ngã')) return Icons.personal_injury;
    if (lowerMsg.contains('bluetooth') || lowerMsg.contains('gậy')) {
      return lowerMsg.contains('mất') ? Icons.bluetooth_disabled : Icons.bluetooth;
    }
    if (lowerMsg.contains('gps')) {
      return lowerMsg.contains('tắt') ? Icons.location_off : Icons.location_on;
    }
    if (lowerMsg.contains('mạng') || lowerMsg.contains('wifi')) {
      return lowerMsg.contains('mất') ? Icons.wifi_off : Icons.wifi;
    }
    return Icons.info_outline;
  }

  Color _getColorForMessage(String msg, AppThemeColors colors) {
    final lowerMsg = msg.toLowerCase();
    if (lowerMsg.contains('ngã')) return colors.warningRed;
    if (lowerMsg.contains('mất') || lowerMsg.contains('tắt')) return Colors.orange;
    return colors.primaryGreen; 
  }

  @override
  void dispose() {
    _roleSubscription.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _handleManageDestination() {
    if (_destinationLocation != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Quản lý Điểm Hẹn'),
          content: const Text('Điểm hẹn đã được thiết lập. Bạn muốn thay đổi vị trí mới hay xóa điểm hẹn hiện tại?'),
          actions: [
            TextButton(onPressed: () { Navigator.pop(context); _clearLocation('destination'); }, child: const Text('Xóa', style: TextStyle(color: Colors.red))),
            TextButton(onPressed: () { Navigator.pop(context); setState(() => _selectingLocationType = 'destination'); }, child: const Text('Thay Đổi')),
          ]
        )
      );
    } else {
      setState(() => _selectingLocationType = 'destination');
    }
  }

  void _handleManageHome() {
    if (_homeLocation != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Quản lý Địa chỉ Nhà'),
          content: const Text('Địa chỉ nhà đã được thiết lập. Bạn muốn thay đổi vị trí mới hay xóa vị trí hiện tại?'),
          actions: [
            TextButton(onPressed: () { Navigator.pop(context); _clearLocation('home_location'); }, child: const Text('Xóa', style: TextStyle(color: Colors.red))),
            TextButton(onPressed: () { Navigator.pop(context); setState(() => _selectingLocationType = 'home_location'); }, child: const Text('Thay Đổi')),
          ]
        )
      );
    } else {
      setState(() => _selectingLocationType = 'home_location');
    }
  }

  Future<void> _saveLocation() async {
    final type = _selectingLocationType;
    if (type == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final center = _mapController.camera.center;
    await FirebaseDatabase.instance.ref('users/${user.uid}/$type').set({
      'lat': center.latitude,
      'lng': center.longitude,
    });
    
    // Đẩy thông báo lên alert_history (base)
    final message = type == 'home_location' ? 'Thông tin: Giám hộ đã cài đặt Địa chỉ Nhà mới' : 'Thông tin: Giám hộ đã thiết lập Điểm Hẹn mới';
    _addAlertToFirebase(message);

    setState(() => _selectingLocationType = null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(type == 'home_location' ? 'Đã lưu địa chỉ nhà!' : 'Đã lưu điểm hẹn thành công!')));
    }
  }

  Future<void> _clearLocation(String type) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseDatabase.instance.ref('users/${user.uid}/$type').remove();
    
    // Đẩy thông báo lên alert_history (base)
    final message = type == 'home_location' ? 'Thông tin: Giám hộ đã XOÁ Địa chỉ Nhà' : 'Thông tin: Giám hộ đã XOÁ Điểm Hẹn';
    _addAlertToFirebase(message);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(type == 'home_location' ? 'Đã xóa địa chỉ nhà!' : 'Đã xóa điểm hẹn!')));
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
      appBar: AppBar(title: const Text('Giám Sát Vị Trí'), centerTitle: true),
      drawer: AppDrawer(
        roleName: 'Người Giám Hộ', 
        onManageDestination: _handleManageDestination,
        onManageHome: _handleManageHome,
      ),
      body: Column(
        children: [
          // Khu vực Bản đồ nhúng
          Expanded(
            flex: 6,
            child: Stack(
              children: [
                if (_currentLocation.latitude == 0)
                  Container(
                    color: colors.cardColor,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_off, size: 50, color: colors.textSecondary),
                          const SizedBox(height: 16),
                          Text('Chưa nhận được vị trí từ Người Già', style: TextStyle(color: colors.textSecondary)),
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
                            rotate: true, // Luôn đứng thẳng so với màn hình
                            child: GestureDetector(
                              onTap: _openGoogleMapsApp,
                              child: Icon(
                                Icons.location_on, 
                                color: _isFallen 
                                    ? colors.warningRed 
                                    : (_isCaneConnected ? colors.primaryGreen : Colors.grey), 
                                size: 50,
                              ),
                            ),
                          ),
                          if (_homeLocation != null)
                            Marker(
                              point: _homeLocation!,
                              width: 60,
                              height: 60,
                              rotate: true,
                              child: GestureDetector(
                                onTap: _handleManageHome,
                                child: Icon(Icons.home, color: colors.primaryGreen, size: 40),
                              ),
                            ),
                          if (_destinationLocation != null)
                            Marker(
                              point: _destinationLocation!,
                              width: 60,
                              height: 60,
                              rotate: true,
                              child: GestureDetector(
                                onTap: _handleManageDestination,
                                child: Icon(Icons.add_location_alt, color: Colors.blue, size: 40),
                              ),
                            ),
                        ],
                      ),
                      ],
                    ),

                  if (_selectingLocationType != null) ...[
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 25), // Bù khoảng cách tâm của icon
                        child: Icon(Icons.add_location_alt, size: 50, color: Colors.blue),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_selectingLocationType == 'home_location' ? 'Kéo bản đồ để chọn Địa Chỉ Nhà' : 'Kéo bản đồ để chọn Điểm Hẹn', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                                    onPressed: () => setState(() => _selectingLocationType = null),
                                    child: const Text('Hủy', style: TextStyle(color: Colors.white)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                                    onPressed: _saveLocation,
                                    child: const Text('Lưu', style: TextStyle(color: Colors.white)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                // Cảnh báo Mất Kết Nối với Gậy
                // Cảnh báo Mất Kết Nối với Gậy
                if (!_isCaneConnected && _currentLocation.latitude != 0)
                  Positioned(
                    top: !_isElderlyOnline ? 90 : 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: !_isElderlyBleEnabled ? Colors.red.shade800.withOpacity(0.9) : Colors.orange.shade800.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)],
                      ),
                      child: Row(
                        children: [
                          Icon(!_isElderlyBleEnabled ? Icons.bluetooth_disabled : Icons.bluetooth_searching, color: Colors.white, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              !_isElderlyBleEnabled 
                                ? 'Cảnh báo: Người Già đang TẮT Bluetooth trên điện thoại!'
                                : 'Đã mất kết nối với Gậy!\n(Đây là vị trí cuối cùng)',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Cảnh báo Mất Kết Nối Mạng (WiFi/4G)
                if (!_isElderlyOnline)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade900.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)],
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.wifi_off, color: Colors.white, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Người Già MẤT KẾT NỐI MẠNG (WiFi/4G)!\n(Dữ liệu bên dưới có thể bị cũ)',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Cảnh báo Người Già tắt GPS
                if (!_isElderlyGpsEnabled && _currentLocation.latitude != 0)
                  Positioned(
                    top: (!_isCaneConnected && !_isElderlyOnline) ? 164 : ((!_isCaneConnected || !_isElderlyOnline) ? 90 : 16),
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade800.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)],
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.location_off, color: Colors.white, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Người Già ĐANG TẮT VỊ TRÍ (GPS)!\n(Đây là vị trí cũ trước khi tắt)',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Lớp phủ Trạng thái Ngã
                if (_isFallen)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: colors.warningRed,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                          SizedBox(width: 8),
                          Text(
                            'PHÁT HIỆN TÉ NGÃ KHẨN CẤP!',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // Khu vực thông tin và lịch sử
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: colors.background,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -5))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Lịch Sử Cảnh Báo', style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                      if (_currentLocation.latitude != 0)
                        TextButton.icon(
                          onPressed: _openGoogleMapsApp,
                          icon: Icon(Icons.map, color: colors.primaryGreen, size: 18),
                          label: Text('Mở GG Maps', style: TextStyle(color: colors.primaryGreen)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _alertHistory.isEmpty 
                      ? Center(child: Text('Chưa có cảnh báo nào', style: TextStyle(color: colors.textSecondary)))
                      : Container(
                          decoration: BoxDecoration(color: colors.cardColor, borderRadius: BorderRadius.circular(16)),
                          child: ListView.separated(
                            padding: const EdgeInsets.all(8),
                            itemCount: _alertHistory.length > 3 ? 3 : _alertHistory.length, // Chỉ hiện 3 cái
                            separatorBuilder: (context, index) => Divider(color: colors.textSecondary.withOpacity(0.2), height: 1),
                            itemBuilder: (context, index) {
                              try {
                                final data = jsonDecode(_alertHistory[index]) as Map<String, dynamic>;
                                final msg = data['message'].toString();
                                final isFall = msg.toLowerCase().contains('ngã');
                                final color = _getColorForMessage(msg, colors);
                                final icon = _getIconForMessage(msg);
                                
                                return ListTile(
                                  leading: Icon(icon, color: color),
                                  title: Text(msg, style: TextStyle(color: color, fontWeight: isFall ? FontWeight.bold : FontWeight.normal)),
                                  subtitle: Text(data['time'] ?? '', style: TextStyle(color: colors.textSecondary)),
                                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                                  onTap: () => _showDetails(data),
                                );
                              } catch (e) {
                                return const SizedBox.shrink(); // Bỏ qua dữ liệu cũ chưa có format JSON
                              }
                            },
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
