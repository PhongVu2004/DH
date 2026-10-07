import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

class AlertHistoryScreen extends StatefulWidget {
  const AlertHistoryScreen({Key? key}) : super(key: key);

  @override
  State<AlertHistoryScreen> createState() => _AlertHistoryScreenState();
}

class _AlertHistoryScreenState extends State<AlertHistoryScreen> {
  List<String> _alertHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _listenToFirebase();
  }

  void _listenToFirebase() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseDatabase.instance.ref('users/${user.uid}/alert_history').onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.value == null) {
        setState(() {
          _alertHistory = [];
          _isLoading = false;
        });
        return;
      }
      
      final historyMap = event.snapshot.value as Map<dynamic, dynamic>;
      final list = historyMap.values.toList();
      // Sắp xếp giảm dần theo thời gian (mới nhất lên đầu)
      list.sort((a, b) => (b['timestamp'] as num).compareTo(a['timestamp'] as num));
      final jsonList = list.map((e) => jsonEncode(e)).toList();
      
      setState(() {
        _alertHistory = jsonList;
        _isLoading = false;
      });
    });
  }

  Future<void> _clearHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseDatabase.instance.ref('users/${user.uid}/alert_history').remove();
    }
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
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Lịch Sử Cảnh Báo'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.red),
            onPressed: _alertHistory.isEmpty ? null : () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: colors.cardColor,
                  title: Text('Xóa lịch sử', style: TextStyle(color: colors.textPrimary)),
                  content: Text('Bạn có chắc chắn muốn xóa toàn bộ lịch sử?', style: TextStyle(color: colors.textSecondary)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Xóa', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (confirm == true) _clearHistory();
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.primaryGreen))
          : _alertHistory.isEmpty
              ? Center(child: Text('Chưa có cảnh báo nào', style: TextStyle(color: colors.textSecondary)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _alertHistory.length,
                  itemBuilder: (context, index) {
                    try {
                      final data = jsonDecode(_alertHistory[index]) as Map<String, dynamic>;
                      final msg = data['message'].toString();
                      final color = _getColorForMessage(msg, colors);
                      final icon = _getIconForMessage(msg);
                      
                      return Card(
                        color: colors.cardColor,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: color.withOpacity(0.2),
                            child: Icon(icon, color: color),
                          ),
                          title: Text(msg, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                          subtitle: Text(data['time'] ?? '', style: TextStyle(color: colors.textSecondary)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          onTap: () => _showDetails(data),
                        ),
                      );
                    } catch (e) {
                       return const SizedBox.shrink(); // Ignore unparseable old string format
                    }
                  },
                ),
    );
  }
}
