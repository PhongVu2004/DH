import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  
  final _nameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  bool _isLoading = false;

  void _showMessage(String title, String message, IconData icon, Color iconColor) {
    if (!mounted) return;
    final colors = AppTheme.colors(context);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: colors.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 60),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, height: 1.5),
                ),
              ],
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
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    if (user != null) {
      _nameController.text = user?.displayName ?? '';
      _loadEmergencyPhone();
    }
  }

  Future<void> _loadEmergencyPhone() async {
    if (user == null) return;
    try {
      final snapshot = await FirebaseDatabase.instance.ref('users/${user!.uid}/guardianPhone').get();
      if (snapshot.exists && mounted) {
        setState(() {
          _emergencyPhoneController.text = snapshot.value.toString();
        });
      }
    } catch (e) {
      print("Lỗi tải số điện thoại: $e");
    }
  }

  Future<void> _updateProfile() async {
    final newName = _nameController.text.trim();
    final newPhone = _emergencyPhoneController.text.trim();
    
    if (newName.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await user?.updateDisplayName(newName);
      await user?.reload();
      
      if (newPhone.isNotEmpty) {
        await FirebaseDatabase.instance.ref('users/${user!.uid}').update({
          'guardianPhone': newPhone,
        });
      }
      
      _showMessage('Thành Công!', 'Hồ sơ của bạn đã được cập nhật.', Icons.check_circle, AppTheme.colors(context).primaryGreen);
    } catch (e) {
      _showMessage('Có lỗi xảy ra', e.toString(), Icons.error_outline, AppTheme.colors(context).warningRed);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _changePassword() async {
    final oldPassword = _oldPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();

    if (oldPassword.isEmpty || newPassword.isEmpty) {
      _showMessage('Thiếu thông tin', 'Vui lòng nhập đủ mật khẩu cũ và mới!', Icons.warning_amber_rounded, AppTheme.colors(context).warningRed);
      return;
    }

    if (newPassword.length < 6) {
      _showMessage('Mật khẩu quá ngắn', 'Mật khẩu mới phải từ 6 ký tự trở lên!', Icons.warning_amber_rounded, AppTheme.colors(context).warningRed);
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 1. Xác thực lại với mật khẩu cũ
      final cred = EmailAuthProvider.credential(
        email: user!.email!,
        password: oldPassword,
      );
      await user!.reauthenticateWithCredential(cred);

      // 2. Cập nhật mật khẩu mới
      await user!.updatePassword(newPassword);

      // Cập nhật lại mật khẩu trong cache nếu đã lưu tự động đăng nhập
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('cached_password') != null) {
        await prefs.setString('cached_password', newPassword);
      }

      _oldPasswordController.clear();
      _newPasswordController.clear();

      _showMessage('Thành Công!', 'Mật khẩu của bạn đã được cập nhật.', Icons.check_circle, AppTheme.colors(context).primaryGreen);
    } on FirebaseAuthException catch (e) {
      String msg = 'Đã xảy ra lỗi hệ thống';
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        msg = 'Mật khẩu cũ không chính xác!';
      }
      _showMessage('Lỗi Xác Thực', msg, Icons.error_outline, AppTheme.colors(context).warningRed);
    } catch (e) {
      _showMessage('Có lỗi xảy ra', e.toString(), Icons.error_outline, AppTheme.colors(context).warningRed);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text(
          'Hồ Sơ Của Tôi',
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Phần ảnh đại diện (trang trí)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primaryGreen.withOpacity(0.1),
                    ),
                    child: Icon(Icons.person, size: 60, color: colors.primaryGreen),
                  ),
                ),
                const SizedBox(height: 32),

                // Tài khoản (Email) - Chỉ xem
                Text('Tài khoản Email', style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: colors.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.textSecondary.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.email, color: colors.textSecondary, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        user?.email ?? 'Không rõ',
                        style: TextStyle(color: colors.textPrimary, fontSize: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Đổi Tên Hiển Thị
                Text('Tên Hiển Thị', style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Nhập tên của bạn...',
                    hintStyle: TextStyle(color: colors.textSecondary),
                    filled: true,
                    fillColor: colors.cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.textSecondary.withOpacity(0.2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.textSecondary.withOpacity(0.2)),
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Số điện thoại khẩn cấp
                Text('Số Điện Thoại Khẩn Cấp (Người Giám Hộ)', style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _emergencyPhoneController,
                  style: TextStyle(color: colors.textPrimary),
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: 'Nhập SĐT để gọi khi té ngã...',
                    hintStyle: TextStyle(color: colors.textSecondary),
                    filled: true,
                    fillColor: colors.cardColor,
                    prefixIcon: Icon(Icons.phone, color: colors.warningRed),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.textSecondary.withOpacity(0.2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.textSecondary.withOpacity(0.2)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.iconBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _updateProfile,
                    child: const Text('Lưu Thông Tin Hồ Sơ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                
                const SizedBox(height: 40),
                const Divider(),
                const SizedBox(height: 20),

                // Đổi Mật Khẩu
                Text('Đổi Mật Khẩu', style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                
                TextField(
                  controller: _oldPasswordController,
                  obscureText: true,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Mật khẩu cũ',
                    hintStyle: TextStyle(color: colors.textSecondary),
                    filled: true,
                    fillColor: colors.cardColor,
                    prefixIcon: Icon(Icons.lock_outline, color: colors.textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _newPasswordController,
                  obscureText: true,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Mật khẩu mới (Tối thiểu 6 ký tự)',
                    hintStyle: TextStyle(color: colors.textSecondary),
                    filled: true,
                    fillColor: colors.cardColor,
                    prefixIcon: Icon(Icons.lock, color: colors.warningRed),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _changePassword,
                    child: const Text('CẬP NHẬT MẬT KHẨU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
          
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
