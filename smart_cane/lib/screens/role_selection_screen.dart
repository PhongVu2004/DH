import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'elderly_screen.dart';
import 'login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({Key? key}) : super(key: key);

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final user = FirebaseAuth.instance.currentUser;
  
  // Xóa static vì đã restart app, SharedPreferences đã hoạt động bình thường
  String? _myRole;
  String? _myDeviceId;
  bool _isInitLoaded = false;
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInitialRole();
    
    // Fallback khi không có mạng (Offline mode)
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _myRole != null) {
        // Nếu đã 4 giây mà không có dữ liệu Firebase (offline) nhưng đã có role cục bộ thì cho vào luôn
        _navigateToNextScreen();
      }
    });
  }

  Future<void> _loadInitialRole() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Tạo ID thiết bị cố định nếu chưa có
    String? deviceId = prefs.getString('device_id');
    if (deviceId == null) {
      deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('device_id', deviceId);
    }

    if (mounted) {
      setState(() {
        _myDeviceId = deviceId;
        _myRole = prefs.getString('my_role');
        _isInitLoaded = true;
      });
    }
  }

  Future<void> _saveMyRole(String? role) async {
    final prefs = await SharedPreferences.getInstance();
    if (role == null) {
      await prefs.remove('my_role');
    } else {
      await prefs.setString('my_role', role);
    }
    
    if (mounted) {
      setState(() {
        _myRole = role;
      });
    }
  }

  Future<void> _confirmAndSelectRole(String role, bool hasRole) async {
    final colors = AppTheme.colors(context);

    if (hasRole || _myDeviceId == null) {
      _showMessage('Vai trò này đã có thiết bị kết nối hoặc lỗi thiết bị!');
      return;
    }
    
    // Hộp thoại xác nhận
    final String roleName = role == 'guardian' ? 'Người Giám Hộ' : 'Người Dùng Gậy';
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Xác nhận vai trò', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'Bạn có chắc chắn thiết bị này sẽ đóng vai trò là\n[$roleName]?',
          style: TextStyle(color: colors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Hủy', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primaryGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Chắc chắn', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || user == null) return;
    
    try {
      final dbRef = FirebaseDatabase.instance.ref('users/${user!.uid}');
      await dbRef.update({
        if (role == 'guardian') 'guardianDeviceId': _myDeviceId,
        if (role == 'elderly') 'elderlyDeviceId': _myDeviceId,
      });
      
      await _saveMyRole(role);
      _showMessage('Đã chọn thành công! Đang chờ thiết bị kia...', color: colors.primaryGreen);
    } catch (e) {
      _showMessage('Lỗi cập nhật: ${e.toString()}');
    }
  }

  Future<void> _resetRoles() async {
    final colors = AppTheme.colors(context);
    if (user == null) return;
    try {
      await FirebaseDatabase.instance.ref('users/${user!.uid}').update({
        'guardianDeviceId': null,
        'elderlyDeviceId': null,
      });
      await _saveMyRole(null);
      _showMessage('Đã hủy kết nối thành công!', color: colors.primaryGreen);
    } catch (e) {
      _showMessage('Lỗi hủy kết nối: ${e.toString()}');
    }
  }

  void _showMessage(String message, {Color? color}) {
    if (!mounted) return;
    final colors = AppTheme.colors(context);
    final msgColor = color ?? colors.warningRed;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
        });
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(30)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(msgColor == colors.primaryGreen ? Icons.check_circle : Icons.info_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _logout() async {
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
      await _saveMyRole(null);
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
      }
    }
  }

  void _navigateToNextScreen() {
    // Dùng Future.microtask để tránh lỗi setState during build
    Future.microtask(() {
      if (!mounted) return;
      if (_myRole == 'guardian') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const DashboardScreen()));
      } else if (_myRole == 'elderly') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ElderlyScreen()));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) return const Scaffold();
    final colors = AppTheme.colors(context);

    if (_isLoading || !_isInitLoaded) {
      return Scaffold(body: Center(child: CircularProgressIndicator(color: colors.primaryGreen)));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ghép Nối Thiết Bị'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: colors.warningRed),
            tooltip: 'Đăng xuất',
            onPressed: _logout,
          ),
        ],
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance.ref('users/${user!.uid}').onValue,
        builder: (context, snapshot) {
          // Bắt buộc hiển thị Loading trong khi chờ dữ liệu từ Firebase
          if (!snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: colors.primaryGreen),
                  const SizedBox(height: 16),
                  Text('Đang kiểm tra kết nối...', style: TextStyle(color: colors.textSecondary)),
                ],
              ),
            );
          }

          String? guardianDeviceId;
          String? elderlyDeviceId;
          
          if (snapshot.data!.snapshot.value != null) {
            final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>?;
            if (data != null) {
              guardianDeviceId = data['guardianDeviceId']?.toString();
              elderlyDeviceId = data['elderlyDeviceId']?.toString();
            }
          }

          // Xác định Role thực sự của MÁY NÀY dựa trên Firebase
          String? actualRole;
          if (_myDeviceId != null) {
            if (guardianDeviceId == _myDeviceId) actualRole = 'guardian';
            if (elderlyDeviceId == _myDeviceId) actualRole = 'elderly';
          }
          
          bool hasGuardian = guardianDeviceId != null;
          bool hasElderly = elderlyDeviceId != null;
          bool isLobbyFull = hasGuardian && hasElderly;

          // Đồng bộ state local nếu Firebase thay đổi
          if (snapshot.hasData) {
            if (_myRole != null && actualRole == null) {
              Future.microtask(() => _saveMyRole(null));
            } else if (actualRole != null && _myRole != actualRole) {
              Future.microtask(() => _saveMyRole(actualRole));
            }
          }

          // Logic 2: Nếu phòng Lobby đã đủ 2 máy
          if (isLobbyFull) {
            if (actualRole != null) {
              // Máy này là 1 trong 2 máy hợp lệ
              _navigateToNextScreen();
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: colors.primaryGreen),
                    const SizedBox(height: 16),
                    Text('Ghép nối thành công! Đang chuyển trang...', style: TextStyle(color: colors.textPrimary)),
                  ],
                ),
              );
            } else {
              // KẺ THỨ BA CỐ TÌNH ĐĂNG NHẬP VÀO TÀI KHOẢN NÀY (Hoặc máy đã bị reset data)
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.block, size: 80, color: colors.warningRed),
                      const SizedBox(height: 24),
                      Text(
                        'Tài khoản này đã đủ 2 thiết bị kết nối!',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.warningRed),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Một máy đang làm Giám Hộ, một máy đang làm Gậy. Máy của bạn không thể tham gia trừ khi chủ tài khoản tự hủy kết nối trên máy của họ.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: colors.textSecondary, height: 1.5),
                      ),
                    ],
                  ),
                ),
              );
            }
          }

          // Giao diện khi 1 thiết bị ĐÃ CHỌN vai trò nhưng thiết bị kia CHƯA CHỌN (Chờ đợi)
          if (actualRole != null) {
            final isGuardian = actualRole == 'guardian';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sync, size: 80, color: colors.primaryGreen),
                    const SizedBox(height: 24),
                    Text(
                      'Bạn là:\n${isGuardian ? "NGƯỜI GIÁM HỘ" : "NGƯỜI DÙNG GẬY"}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.primaryGreen),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Vui lòng dùng thiết bị còn lại đăng nhập vào tài khoản này và chọn vai trò còn lại để hoàn tất ghép nối.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: colors.textSecondary, height: 1.5),
                    ),
                    const SizedBox(height: 48),
                    CircularProgressIndicator(color: colors.iconBlue),
                    const SizedBox(height: 24),
                    Text('Đang chờ thiết bị thứ 2...', style: TextStyle(color: colors.iconBlue, fontWeight: FontWeight.bold)),
                    
                    const Spacer(),
                    // Yêu cầu: CHỈ CÓ NGƯỜI GIÁM HỘ mới có quyền Reset
                    if (isGuardian)
                      TextButton.icon(
                        onPressed: _resetRoles,
                        icon: Icon(Icons.refresh, color: colors.warningRed),
                        label: Text(
                          'Hủy & Cài đặt lại vai trò',
                          style: TextStyle(color: colors.warningRed, decoration: TextDecoration.underline, fontSize: 16),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }

          // Giao diện khi CHƯA CHỌN VAI TRÒ NÀO (Mặc định)
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildRoleCard(
                  context,
                  title: 'Người Giám Hộ',
                  subtitle: hasGuardian ? 'Đã có thiết bị kết nối' : 'Theo dõi thông số, cảnh báo và định vị gậy',
                  icon: Icons.monitor_heart,
                  color: hasGuardian ? Colors.grey : colors.iconBlue,
                  isLocked: hasGuardian,
                  onTap: () => _confirmAndSelectRole('guardian', hasGuardian),
                ),
                const SizedBox(height: 24),
                _buildRoleCard(
                  context,
                  title: 'Người Dùng Gậy',
                  subtitle: hasElderly ? 'Đã có thiết bị kết nối' : 'Chế độ SOS và tự động phát định vị GPS',
                  icon: Icons.elderly,
                  color: hasElderly ? Colors.grey : colors.warningRed,
                  isLocked: hasElderly,
                  onTap: () => _confirmAndSelectRole('elderly', hasElderly),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildRoleCard(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isLocked,
    required VoidCallback onTap,
  }) {
    final colors = AppTheme.colors(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          color: colors.cardColor,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: color.withOpacity(isLocked ? 0.2 : 0.5), width: 2),
        ),
        child: Opacity(
          opacity: isLocked ? 0.4 : 1.0,
          child: Column(
            children: [
              Icon(isLocked ? Icons.lock : icon, size: 64, color: color),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isLocked ? Colors.grey : colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isLocked ? colors.warningRed : colors.textSecondary,
                  fontWeight: isLocked ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
