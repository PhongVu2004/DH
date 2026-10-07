import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../screens/login_screen.dart';
import '../screens/role_selection_screen.dart';
import '../main.dart'; // Import themeNotifier
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';
import '../screens/profile_screen.dart';
import '../screens/alert_history_screen.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/services.dart';

class AppDrawer extends StatelessWidget {
  final String roleName;
  final VoidCallback? onManageDestination;
  final VoidCallback? onManageHome;

  const AppDrawer({Key? key, required this.roleName, this.onManageDestination, this.onManageHome}) : super(key: key);

  void _logout(BuildContext context) async {
    // Hiển thị hộp thoại xác nhận
    final colors = AppTheme.colors(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.cardColor,
        title: Text('Đăng Xuất', style: TextStyle(color: colors.textPrimary)),
        content: Text('Bạn có chắc chắn muốn đăng xuất khỏi tài khoản này?', style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Hủy', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colors.warningRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đăng Xuất', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_email');
      await prefs.remove('cached_password');
      if (context.mounted) {
        // Đẩy về màn hình đăng nhập và xóa toàn bộ lịch sử trang
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (Route<dynamic> route) => false,
        );
      }
    }
  }

  void _changeRole(BuildContext context, User? user) async {
    final colors = AppTheme.colors(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.cardColor,
        title: Text('Đổi Vai Trò', style: TextStyle(color: colors.textPrimary)),
        content: Text('Bạn có chắc chắn muốn HỦY kết nối của cả 2 máy để chọn lại vai trò không?', style: TextStyle(color: colors.textSecondary, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Hủy', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colors.primaryGreen),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Chắc chắn', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && user != null) {
      Navigator.pop(context); // Đóng Drawer
      // Reset Firebase
      await FirebaseDatabase.instance.ref('users/${user.uid}').update({
        'guardianDeviceId': null,
        'elderlyDeviceId': null,
      });
      // Không cần gọi pushReplacement ở đây vì Listener ở DashboardScreen sẽ tự văng ra!
    }
  }

  void _configPhone(BuildContext context, User? user) async {
    final colors = AppTheme.colors(context);
    final phoneController = TextEditingController();

    if (user != null) {
      final snapshot = await FirebaseDatabase.instance.ref('users/${user.uid}/guardianPhone').get();
      if (snapshot.value != null) {
        phoneController.text = snapshot.value.toString();
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.cardColor,
        title: Text('Cài đặt Cuộc gọi Khẩn cấp', style: TextStyle(color: colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Nhập số điện thoại của bạn để App Người Già tự động gọi khi phát hiện té ngã:', style: TextStyle(color: colors.textSecondary, height: 1.5)),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'VD: 0912345678',
                hintStyle: TextStyle(color: colors.textSecondary),
                prefixIcon: Icon(Icons.phone, color: colors.primaryGreen),
                filled: true,
                fillColor: colors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Hủy', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colors.primaryGreen),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lưu số', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && user != null && phoneController.text.trim().isNotEmpty) {
      await FirebaseDatabase.instance.ref('users/${user.uid}').update({
        'guardianPhone': phoneController.text.trim(),
      });
      if (context.mounted) {
        Navigator.pop(context); // Đóng Drawer

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: colors.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: colors.primaryGreen, size: 60),
                const SizedBox(height: 16),
                Text(
                  'Lưu Thành Công!',
                  style: TextStyle(color: colors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'App Người Già sẽ tự động gọi vào số này khi phát hiện té ngã.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('ĐÃ HIỂU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  void _configRingtone(BuildContext context) async {
    final colors = AppTheme.colors(context);
    final prefs = await SharedPreferences.getInstance();
    String selectedRingtone = prefs.getString('alarm_ringtone') ?? 'alarm';
    
    // Nếu giá trị cũ là 'notification' (đã bị xóa) thì ép về 'alarm'
    if (selectedRingtone != 'alarm' && selectedRingtone != 'ringtone') {
      selectedRingtone = 'alarm';
    }

    final ringtones = [
      {'name': 'Chuông Báo Thức To', 'file': 'alarm'},
      {'name': 'Chuông Cuộc Gọi', 'file': 'ringtone'},
    ];

    if (!context.mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: colors.cardColor,
            title: Text('Cài đặt Chuông Báo Động', style: TextStyle(color: colors.textPrimary)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: ringtones.map((ringtone) {
                return RadioListTile<String>(
                  title: Text(ringtone['name']!, style: TextStyle(color: colors.textPrimary)),
                  value: ringtone['file']!,
                  groupValue: selectedRingtone,
                  activeColor: colors.primaryGreen,
                  onChanged: (value) async {
                    if (value != null) {
                      setState(() => selectedRingtone = value);
                      FlutterRingtonePlayer().stop();
                      
                      if (value == 'alarm') {
                        FlutterRingtonePlayer().playAlarm();
                      } else {
                        FlutterRingtonePlayer().playRingtone();
                      }
                    }
                  },
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  FlutterRingtonePlayer().stop();
                  Navigator.pop(context, false);
                },
                child: Text('Hủy', style: TextStyle(color: colors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: colors.primaryGreen),
                onPressed: () {
                  FlutterRingtonePlayer().stop();
                  Navigator.pop(context, true);
                },
                child: const Text('Lưu', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );

    if (confirm == true) {
      await prefs.setString('alarm_ringtone', selectedRingtone);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu chuông báo động!')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'Người dùng Ẩn danh';

    return Drawer(
      backgroundColor: colors.background,
      child: Column(
        children: [
          // Custom Header chuyên nghiệp
          Container(
            padding: const EdgeInsets.only(top: 60, bottom: 30, left: 20, right: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.primaryGreen.withOpacity(0.8), colors.iconBlue.withOpacity(0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 35,
                  backgroundColor: Colors.white,
                  child: Icon(
                    roleName == 'Người Giám Hộ' ? Icons.security : Icons.elderly,
                    size: 35,
                    color: colors.primaryGreen,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: StreamBuilder<User?>(
                    stream: FirebaseAuth.instance.userChanges(),
                    builder: (context, snapshot) {
                      final currentUser = snapshot.data ?? user;
                      final displayName = currentUser?.displayName;
                      final showName = (displayName != null && displayName.isNotEmpty) ? displayName : roleName;
                      final emailText = currentUser?.email ?? 'Người dùng Ẩn danh';

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            showName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            emailText,
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      );
                    }
                  ),
                ),
              ],
            ),
          ),
          
          ListTile(
            leading: Icon(Icons.person_outline, color: colors.iconBlue),
            title: Text('Hồ sơ của tôi', style: TextStyle(color: colors.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()));
            },
          ),
          
          if (roleName == 'Người Giám Hộ') ...[
            ListTile(
              leading: Icon(Icons.home, color: colors.iconBlue),
              title: Text('🏠 Cài Đặt Địa Chỉ Nhà', style: TextStyle(color: colors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                if (onManageHome != null) onManageHome!();
              },
            ),
            ListTile(
              leading: Icon(Icons.add_location_alt, color: colors.primaryGreen),
              title: Text('📍 Quản lý Điểm Hẹn', style: TextStyle(color: colors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                if (onManageDestination != null) onManageDestination!();
              },
            ),
          ],
          
          ListTile(
            leading: Icon(Icons.history, color: colors.iconBlue),
            title: Text('Lịch Sử Cảnh Báo', style: TextStyle(color: colors.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AlertHistoryScreen()));
            },
          ),
          ListTile(
            leading: Icon(Icons.menu_book, color: colors.iconBlue),
            title: Text('Hướng dẫn sử dụng', style: TextStyle(color: colors.textPrimary)),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          const Spacer(),
          const Divider(color: Colors.grey, height: 1),
          
          // Nút chuyển Theme
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, currentMode, _) {
              final isDark = currentMode == ThemeMode.dark;
              return SwitchListTile(
                title: Text(isDark ? 'Chế độ Tối' : 'Chế độ Sáng', style: TextStyle(color: colors.textPrimary)),
                secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: colors.textPrimary),
                value: isDark,
                activeColor: colors.primaryGreen,
                onChanged: (value) async {
                  final newMode = value ? ThemeMode.dark : ThemeMode.light;
                  themeNotifier.value = newMode;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('isDarkMode', value);
                },
              );
            },
          ),

          if (roleName == 'Người Giám Hộ') ...[
            ListTile(
              leading: Icon(Icons.phone_in_talk, color: colors.iconBlue),
              title: Text('SĐT Gọi Khẩn Cấp', style: TextStyle(color: colors.textPrimary)),
              onTap: () => _configPhone(context, user),
            ),
            ListTile(
              leading: Icon(Icons.notifications_active, color: colors.iconBlue),
              title: Text('Cài Đặt Chuông Báo', style: TextStyle(color: colors.textPrimary)),
              onTap: () {
                Navigator.pop(context); // Đóng Drawer
                _configRingtone(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.swap_horiz, color: colors.primaryGreen),
              title: Text('Đổi Vai Trò (Hủy kết nối)', style: TextStyle(color: colors.primaryGreen, fontWeight: FontWeight.bold)),
              onTap: () => _changeRole(context, user),
            ),
          ],
          ListTile(
            leading: Icon(Icons.power_settings_new, color: Colors.orange),
            title: Text('Đóng Hoàn Toàn Ứng Dụng', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
            onTap: () {
              FlutterBackgroundService().invoke('stopService');
              const MethodChannel('com.example.smart_cane/app_killer').invokeMethod('closeAppAndRemoveFromRecents');
            },
          ),
          ListTile(
            leading: Icon(Icons.logout, color: colors.warningRed),
            title: Text('Đăng Xuất', style: TextStyle(color: colors.warningRed, fontWeight: FontWeight.bold)),
            onTap: () => _logout(context),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
