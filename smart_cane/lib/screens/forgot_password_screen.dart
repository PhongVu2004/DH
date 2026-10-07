import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  Future<void> _handleResetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('Vui lòng nhập Email của bạn!');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      
      if (!mounted) return;
      setState(() => _isLoading = false);
      
      final colors = AppTheme.colors(context);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: colors.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: colors.primaryGreen),
              const SizedBox(width: 10),
              Flexible(child: Text('Đã Gửi Link Thành Công!', style: TextStyle(color: colors.textPrimary, fontSize: 18))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Chúng tôi đã gửi một đường dẫn khôi phục mật khẩu đến email của bạn. Vui lòng bấm vào đường dẫn đó để đặt lại mật khẩu mới.',
                style: TextStyle(color: colors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A2323),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.warningRed, width: 1.5),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: colors.warningRed, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'LƯU Ý: Thư khôi phục có thể bị Google lọc nhầm vào mục HỘP THƯ RÁC (SPAM). Vui lòng kiểm tra thật kỹ hòm thư của bạn!',
                        style: TextStyle(color: colors.warningRed, fontWeight: FontWeight.bold, fontSize: 13, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primaryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(context); // Đóng Dialog
                Navigator.pop(context); // Quay về màn hình Đăng Nhập
              },
              child: const Text('Đã Hiểu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      
    } on FirebaseAuthException catch (e) {
      _showMessage(_getErrorMessage(e.code));
    } catch (e) {
      _showMessage('Đã xảy ra lỗi: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, {Color? color}) {
    if (!mounted) return;
    final colors = AppTheme.colors(context);
    final msgColor = color ?? colors.warningRed;
    
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (BuildContext dialogContext) {
        Future.delayed(const Duration(milliseconds: 3000), () {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        });

        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    msgColor == colors.primaryGreen ? Icons.check_circle : Icons.error_outline,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      message,
                      style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _getErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'user-not-found':
        return 'Email này chưa được đăng ký trong hệ thống!';
      case 'invalid-email':
        return 'Định dạng Email không hợp lệ!';
      default:
        return 'Lỗi: $errorCode';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Khôi Phục Mật Khẩu'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Icon(Icons.lock_reset, size: 100, color: colors.primaryGreen),
              const SizedBox(height: 32),
              Text(
                'Quên Mật Khẩu?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: colors.textPrimary),
              ),
              const SizedBox(height: 16),
              Text(
                'Đừng lo lắng! Vui lòng nhập địa chỉ Email bạn đã dùng để đăng ký. Chúng tôi sẽ gửi cho bạn một đường dẫn bảo mật để đặt lại mật khẩu mới.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: colors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Nhập Email của bạn...',
                  hintStyle: TextStyle(color: colors.textSecondary),
                  prefixIcon: Icon(Icons.email_outlined, color: colors.iconBlue),
                  filled: true,
                  fillColor: colors.cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleResetPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text(
                        'GỬI YÊU CẦU',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
