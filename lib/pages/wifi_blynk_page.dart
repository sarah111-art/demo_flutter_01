import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

import '../models/mock_wifi_network.dart';

class WifiBlynkPage extends StatefulWidget {
  const WifiBlynkPage({super.key});
  @override
  State<WifiBlynkPage> createState() => _WifiBlynkPageState();
}

class _WifiBlynkPageState extends State<WifiBlynkPage> {
  final String baseUrl = "https://blynk.cloud/external/api";

  // Wi-Fi networks - real data for mobile, mock for web
  List<WiFiAccessPoint> realWifiList = [];
  List<MockWiFiNetwork> mockWifiList = [];
  String? selectedSsid;
  final TextEditingController passCtrl = TextEditingController();
  final TextEditingController tokenCtrl = TextEditingController();

  bool scanning = false;
  bool connecting = false;
  bool connected = false;
  bool ledOn = false;
  bool permissionGranted = false;
  bool autoScanning = false;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _loadSavedToken();
    _checkConnection();
    if (kIsWeb) {
      _initializeMockNetworks();
    } else {
      _checkPermissions();
    }
  }

  void _initializeMockNetworks() {
    // Initialize with some mock networks for web demo
    mockWifiList = [
      const MockWiFiNetwork(ssid: "Home_WiFi", level: -45, isSecure: true),
      const MockWiFiNetwork(ssid: "Office_5G", level: -55, isSecure: true),
      const MockWiFiNetwork(ssid: "Guest_Network", level: -65, isSecure: false),
      const MockWiFiNetwork(ssid: "Neighbor_WiFi", level: -75, isSecure: true),
    ];
    selectedSsid = mockWifiList.first.ssid;
  }

  Future<void> _checkPermissions() async {
    try {
      // Check if WiFi scanning is supported
      final canScan = await WiFiScan.instance.canGetScannedResults();
      if (canScan != CanGetScannedResults.yes) {
        debugPrint('WiFi scanning not supported: $canScan');
        return;
      }

      // Request location permission (required for WiFi scanning)
      final permission = await Permission.locationWhenInUse.request();
      setState(() {
        permissionGranted = permission.isGranted;
      });

      if (!permissionGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cần quyền truy cập vị trí để quét WiFi'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Permission check error: $e');
    }
  }

  Future<void> _loadSavedToken() async {
    if (kIsWeb) {
      // For web, we can still use SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      tokenCtrl.text = prefs.getString('blynk_token') ?? '';
    }
  }

  Future<void> _saveToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('blynk_token', tokenCtrl.text.trim());
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu Auth Token')),
      );
    }
  }

  Future<void> _checkConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      setState(() {
        connected = connectivityResult.contains(ConnectivityResult.wifi) ||
            connectivityResult.contains(ConnectivityResult.ethernet) ||
            connectivityResult.contains(ConnectivityResult.mobile);
      });
    } catch (e) {
      debugPrint('Connection check error: $e');
    }
  }

  void _startAutoScan() {
    if (autoScanning) return;

    setState(() => autoScanning = true);

    // Scan immediately
    _performScan();

    // Then scan every 10 seconds
    _scanTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (autoScanning && mounted) {
        _performScan();
      }
    });
  }

  void _stopAutoScan() {
    setState(() => autoScanning = false);
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  Future<void> _performScan() async {
    if (kIsWeb) {
      // Web simulation - update existing networks with new signal levels
      final updatedList = <MockWiFiNetwork>[];

      for (var network in mockWifiList) {
        final levelChange = (DateTime.now().millisecondsSinceEpoch % 10) - 5;
        final newLevel = (network.level + levelChange).clamp(-90, -30);

        updatedList.add(MockWiFiNetwork(
          ssid: network.ssid,
          level: newLevel,
          isSecure: network.isSecure,
        ));
      }

      // Sometimes add a new network
      final random = DateTime.now().millisecondsSinceEpoch % 3;
      if (random == 0) {
        final newNetwork = MockWiFiNetwork(
          ssid: "New_Network_${DateTime.now().second}",
          level: -60 - (DateTime.now().second % 30),
          isSecure: DateTime.now().second % 2 == 0,
        );
        if (!updatedList.any((w) => w.ssid == newNetwork.ssid)) {
          updatedList.add(newNetwork);
        }
      }

      // Sort by signal strength
      updatedList.sort((a, b) => b.level.compareTo(a.level));

      setState(() {
        mockWifiList = updatedList;
        if (selectedSsid == null ||
            !mockWifiList.any((w) => w.ssid == selectedSsid)) {
          selectedSsid = mockWifiList.isNotEmpty ? mockWifiList.first.ssid : null;
        }
      });
    } else {
      // Real WiFi scanning for mobile platforms
      if (!permissionGranted) return;

      try {
        // Start WiFi scan
        await WiFiScan.instance.startScan();

        // Wait a moment for scan to complete
        await Future.delayed(const Duration(seconds: 2));

        // Get scan results
        final results = await WiFiScan.instance.getScannedResults();

        setState(() {
          realWifiList = results;

          // Update selected SSID if needed
          if (selectedSsid == null ||
              !realWifiList.any((w) => w.ssid == selectedSsid)) {
            selectedSsid =
                realWifiList.isNotEmpty ? realWifiList.first.ssid : null;
          }
        });
      } catch (e) {
        debugPrint('Auto scan error: $e');
      }
    }
  }

  Future<void> scanWifi() async {
    if (kIsWeb) {
      // Web simulation of Wi-Fi scanning
      setState(() => scanning = true);

      // Simulate scanning delay
      await Future.delayed(const Duration(seconds: 2));

      // Add some randomization to make it feel more realistic
      final random = DateTime.now().millisecondsSinceEpoch % 3;
      if (random == 0) {
        // Sometimes add a new network
        final newNetwork = MockWiFiNetwork(
          ssid: "New_Network_${DateTime.now().second}",
          level: -60 - (DateTime.now().second % 30),
          isSecure: DateTime.now().second % 2 == 0,
        );
        if (!mockWifiList.any((w) => w.ssid == newNetwork.ssid)) {
          mockWifiList.add(newNetwork);
        }
      }

      // Sort by signal strength
      mockWifiList.sort((a, b) => b.level.compareTo(a.level));

      setState(() {
        scanning = false;
        if (selectedSsid == null ||
            !mockWifiList.any((w) => w.ssid == selectedSsid)) {
          selectedSsid = mockWifiList.isNotEmpty ? mockWifiList.first.ssid : null;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tìm thấy ${mockWifiList.length} mạng Wi-Fi')),
        );
      }
    } else {
      // Real WiFi scanning for mobile platforms
      if (!permissionGranted) {
        await _checkPermissions();
        if (!permissionGranted) return;
      }

      setState(() => scanning = true);

      try {
        // Start WiFi scan
        await WiFiScan.instance.startScan();

        // Wait a moment for scan to complete
        await Future.delayed(const Duration(seconds: 3));

        // Get scan results
        final results = await WiFiScan.instance.getScannedResults();

        setState(() {
          realWifiList = results;
          scanning = false;

          // Update selected SSID if needed
          if (selectedSsid == null ||
              !realWifiList.any((w) => w.ssid == selectedSsid)) {
            selectedSsid =
                realWifiList.isNotEmpty ? realWifiList.first.ssid : null;
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tìm thấy ${realWifiList.length} mạng Wi-Fi thực tế')),
          );
        }
      } catch (e) {
        setState(() => scanning = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi quét Wi-Fi: $e')),
          );
        }
      }
    }
  }

  Future<void> connectSelected() async {
    final ssid = selectedSsid;
    if (ssid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hãy chọn một mạng Wi-Fi')),
      );
      return;
    }

    setState(() => connecting = true);

    try {
      if (kIsWeb) {
        // Web simulation
        final selectedNetwork = mockWifiList.firstWhere((w) => w.ssid == ssid);

        // Simulate connection process
        await Future.delayed(const Duration(seconds: 3));

        // Check if password is required and provided
        if (selectedNetwork.isSecure && passCtrl.text.trim().isEmpty) {
          throw Exception('Mạng này cần mật khẩu');
        }

        // Simulate success/failure (90% success rate for demo)
        final success = DateTime.now().millisecondsSinceEpoch % 10 != 0;

        if (success) {
          setState(() => connected = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Đã kết nối $ssid (mô phỏng)')),
          );
        } else {
          throw Exception('Không thể kết nối - kiểm tra mật khẩu');
        }
      } else {
        // Real WiFi connection for mobile
        final selectedNetwork = realWifiList.firstWhere((w) => w.ssid == ssid);
        final password = passCtrl.text.trim();

        // Check if password is required
        final isSecure = selectedNetwork.capabilities.contains('WPA') ||
            selectedNetwork.capabilities.contains('WEP');

        if (isSecure && password.isEmpty) {
          throw Exception('Mạng này cần mật khẩu');
        }

        // Attempt real connection
        bool success = false;
        if (isSecure) {
          success = await WiFiForIoTPlugin.connect(
            ssid,
            password: password,
            security: NetworkSecurity.WPA,
            withInternet: true,
          );
        } else {
          success = await WiFiForIoTPlugin.connect(
            ssid,
            withInternet: true,
          );
        }

        if (success) {
          setState(() => connected = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Đã kết nối $ssid thành công')),
          );

          // Verify connection after a moment
          Future.delayed(const Duration(seconds: 2), () {
            _checkConnection();
          });
        } else {
          throw Exception('Không thể kết nối - kiểm tra SSID và mật khẩu');
        }
      }
    } catch (e) {
      setState(() => connected = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Lỗi kết nối: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  Future<void> disconnectWifi() async {
    setState(() {
      connected = false;
      ledOn = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã ngắt Wi-Fi')),
    );
  }

  Future<void> sendBlynk(int pin, int value) async {
    final token = tokenCtrl.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập Auth Token trước')),
      );
      return;
    }

    try {
      final url = Uri.parse('$baseUrl/update?token=$token&V$pin=$value');
      final res = await http.get(url).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Đã gửi V$pin=$value')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Blynk lỗi: ${res.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Lỗi mạng: $e')),
      );
    }
  }

  String _getSignalBars(int level) {
    if (level >= -50) return '▮▮▮▮';
    if (level >= -60) return '▮▮▮';
    if (level >= -70) return '▮▮';
    return '▮';
  }

  // Helper methods to get current WiFi list
  List<String> get currentWifiSsids {
    if (kIsWeb) {
      return mockWifiList.map((w) => w.ssid).toList();
    } else {
      return realWifiList.map((w) => w.ssid).toList();
    }
  }

  int get currentWifiCount {
    if (kIsWeb) {
      return mockWifiList.length;
    } else {
      return realWifiList.length;
    }
  }

  bool isNetworkSecure(String ssid) {
    if (kIsWeb) {
      final network = mockWifiList.firstWhere((w) => w.ssid == ssid);
      return network.isSecure;
    } else {
      final network = realWifiList.firstWhere((w) => w.ssid == ssid);
      return network.capabilities.contains('WPA') ||
          network.capabilities.contains('WEP');
    }
  }

  int getNetworkLevel(String ssid) {
    if (kIsWeb) {
      final network = mockWifiList.firstWhere((w) => w.ssid == ssid);
      return network.level;
    } else {
      final network = realWifiList.firstWhere((w) => w.ssid == ssid);
      return network.level;
    }
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    passCtrl.dispose();
    tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canConnect = selectedSsid != null && !connecting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Wi-Fi • Save Token • Blynk'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Platform indicator
            if (kIsWeb)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.web, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Web Demo Mode - Sử dụng dữ liệu mô phỏng'),
                  ],
                ),
              ),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: scanning ? null : scanWifi,
                    icon: scanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_find),
                    label: Text(scanning ? 'Đang quét…' : 'Quét Wi-Fi'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: connected
                        ? disconnectWifi
                        : (canConnect ? connectSelected : null),
                    icon: connecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(connected ? Icons.wifi_off : Icons.wifi),
                    label: Text(
                      connecting
                          ? 'Đang kết nối...'
                          : (connected ? 'Ngắt kết nối' : 'Kết nối'),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Auto scan button
            ElevatedButton.icon(
              onPressed: autoScanning ? _stopAutoScan : _startAutoScan,
              icon: autoScanning ? const Icon(Icons.stop) : const Icon(Icons.refresh),
              label: Text(
                autoScanning
                    ? 'Dừng Auto Scan ($currentWifiCount networks)'
                    : 'Bật Auto Scan (10s)',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    autoScanning ? Colors.red.shade100 : Colors.green.shade100,
                foregroundColor:
                    autoScanning ? Colors.red.shade800 : Colors.green.shade800,
              ),
            ),

            const SizedBox(height: 16),

            // Wi-Fi network selector
            if (currentWifiCount > 0)
              DropdownButtonFormField<String>(
                value: selectedSsid,
                isExpanded: true,
                items: currentWifiSsids.map((ssid) {
                  final level = getNetworkLevel(ssid);
                  final bars = _getSignalBars(level);
                  final security = isNetworkSecure(ssid) ? '🔒' : '🌐';
                  return DropdownMenuItem(
                    value: ssid,
                    child: Row(
                      children: [
                        Text(security),
                        const SizedBox(width: 8),
                        Expanded(child: Text(ssid)),
                        Text(bars, style: const TextStyle(color: Colors.grey)),
                        const SizedBox(width: 8),
                        Text(
                          '${level}dBm',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => selectedSsid = v),
                decoration: const InputDecoration(
                  labelText: 'Chọn SSID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi),
                ),
              ),

            if (currentWifiCount == 0)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('Chưa có danh sách Wi-Fi. Bấm "Quét Wi-Fi".'),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Password field
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mật khẩu Wi-Fi (để trống nếu mạng mở)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
                suffixIcon: Icon(Icons.visibility_off),
              ),
            ),

            const SizedBox(height: 20),

            // Blynk token field
            TextField(
              controller: tokenCtrl,
              decoration: const InputDecoration(
                labelText: 'Blynk Auth Token',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
                helperText: 'Lấy token từ ứng dụng Blynk',
              ),
            ),

            const SizedBox(height: 12),

            // Token management buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saveToken,
                    icon: const Icon(Icons.save),
                    label: const Text('Lưu Token'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => tokenCtrl.clear(),
                    icon: const Icon(Icons.clear),
                    label: const Text('Xoá Token'),
                  ),
                ),
              ],
            ),

            const Divider(height: 32),

            // LED control
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: ledOn ? Colors.green : Colors.grey,
                  child: Icon(
                    ledOn ? Icons.lightbulb : Icons.lightbulb_outline,
                    color: Colors.white,
                  ),
                ),
                title: const Text('Điều khiển V1 (LED)'),
                subtitle: Text(
                  connected ? '✅ Đã kết nối Wi-Fi' : '❌ Chưa kết nối Wi-Fi',
                ),
                trailing: Switch(
                  value: ledOn,
                  onChanged: connected
                      ? (v) async {
                          setState(() => ledOn = v);
                          await sendBlynk(1, v ? 1 : 0);
                        }
                      : null,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Status info
            Card(
              color: Colors.grey.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kIsWeb ? 'Thông tin Web Demo:' : 'Thông tin Mobile:',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (kIsWeb) ...[
                      const Text('• Wi-Fi scanning được mô phỏng'),
                      const Text('• Auto scan: Cập nhật networks mỗi 10 giây'),
                      const Text('• Kết nối thực tế qua Ethernet/Wi-Fi của máy tính'),
                      const Text('• Blynk API calls hoạt động bình thường'),
                      const Text('• Token được lưu trong browser storage'),
                    ] else ...[
                      Text('• Wi-Fi scanning thực tế: ${permissionGranted ? "✅ Có quyền" : "❌ Cần quyền"}'),
                      Text('• Auto scan: ${autoScanning ? "✅ Đang chạy (10s)" : "❌ Tắt"}'),
                      Text('• Đã tìm thấy ${realWifiList.length} mạng WiFi'),
                      const Text('• Có thể kết nối WiFi thực tế'),
                      const Text('• Blynk API calls hoạt động bình thường'),
                      const Text('• Token được lưu trong device storage'),
                    ],
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


