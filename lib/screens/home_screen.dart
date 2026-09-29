import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../services/database_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _overlayGranted = false;
  bool _overlayActive  = false;
  final _db = DatabaseService();
  int  _savedCount = 0;
  List<Map<String, dynamic>> _history = [];

  static const Color kGreen = Color(0xFF00FF88);
  static const Color kRed   = Color(0xFFFF2244);
  static const Color kGold  = Color(0xFFFFD700);
  static const Color kBg    = Color(0xFF020408);
  static const Color kPanel = Color(0xFF080D16);

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadHistory();
  }

  Future<void> _checkPermissions() async {
    final ok = await FlutterOverlayWindow.isPermissionGranted();
    if (mounted) setState(() => _overlayGranted = ok);
  }

  Future<void> _loadHistory() async {
    await _db.init();
    final count = await _db.getSignalCount();
    final hist  = await _db.getSignals(limit: 30);
    if (mounted) setState(() { _savedCount = count; _history = hist; });
  }

  Future<void> _requestOverlay() async {
    await FlutterOverlayWindow.requestPermission();
    await _checkPermissions();
  }

  Future<void> _toggleOverlay() async {
    if (!_overlayGranted) { await _requestOverlay(); return; }
    if (_overlayActive) {
      await FlutterOverlayWindow.closeOverlay();
      if (mounted) setState(() => _overlayActive = false);
    } else {
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        height: 72,
        width: 72,
        alignment: OverlayAlignment.centerRight,
        flag: OverlayFlag.defaultFlag,
        overlayTitle: 'MR KOKO',
        overlayContent: 'Tap to scan market',
        visibility: NotificationVisibility.visibilityPublic,
      );
      if (mounted) setState(() => _overlayActive = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(child: Column(children: [
        _buildHeader(),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            _buildPermCard(),
            const SizedBox(height: 12),
            _buildHowTo(),
            const SizedBox(height: 12),
            _buildStats(),
            const SizedBox(height: 12),
            if (_history.isNotEmpty) _buildHistory(),
          ]),
        )),
      ])),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF152030)))),
      child: Row(children: [
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: kGreen, width: 2),
            boxShadow: [BoxShadow(color: kGreen.withOpacity(.4), blurRadius: 10)],
          ),
          child: ClipOval(
              child: Image.asset('assets/logo.jpg', fit: BoxFit.cover)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                  colors: [kGreen, Colors.white, kRed]).createShader(b),
              child: const Text('MR KOKO',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                    color: Colors.white, letterSpacing: 2)),
            ),
            const Text('SIGNAL PRO · REAL API',
              style: TextStyle(fontSize: 9, color: Colors.white38, letterSpacing: 3)),
          ],
        )),
        Column(children: [
          Text('$_savedCount',
            style: const TextStyle(fontSize: 18,
                fontWeight: FontWeight.bold, color: kGold)),
          const Text('SAVED',
            style: TextStyle(fontSize: 9, color: Colors.white38, letterSpacing: 1)),
        ]),
      ]),
    );
  }

  Widget _buildPermCard() {
    return _card('PERMISSIONS', [
      _permRow('Display over other apps', _overlayGranted, _requestOverlay),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: kGreen.withOpacity(.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kGreen.withOpacity(.2)),
        ),
        child: const Row(children: [
          Icon(Icons.wifi, color: kGreen, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text(
            'Internet permission: AUTO\nBinance API থেকে real market data নেওয়া হবে',
            style: TextStyle(fontSize: 10, color: kGreen, height: 1.6),
          )),
        ]),
      ),
    ]);
  }

  Widget _permRow(String label, bool granted, VoidCallback onTap) {
    return Row(children: [
      Icon(granted ? Icons.check_circle : Icons.radio_button_unchecked,
        color: granted ? kGreen : Colors.white24, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(label,
        style: const TextStyle(fontSize: 12, color: Colors.white70))),
      if (!granted)
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
                border: Border.all(color: kGreen),
                borderRadius: BorderRadius.circular(6)),
            child: const Text('GRANT',
              style: TextStyle(fontSize: 10, color: kGreen, letterSpacing: 1)),
          ),
        ),
    ]);
  }

  Widget _buildHowTo() {
    return _card('HOW TO USE', [
      _step('1', 'Grant "Display over other apps" permission'),
      _step('2', 'Press LAUNCH FLOATING ICON'),
      _step('3', 'Tap the MR KOKO floating icon — panel খুলবে'),
      _step('4', 'Asset select করুন (EUR/USD, BTC/USDT, etc.)'),
      _step('5', 'Timeframe select করুন (1M, 5M, 15M...)'),
      _step('6', 'Binance API থেকে real candles আসবে'),
      _step('7', 'SMC + ICT + RSI + EMA দিয়ে BUY/SELL signal'),
      const SizedBox(height: 14),
      GestureDetector(
        onTap: _toggleOverlay,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _overlayActive
                ? [const Color(0xFF380010), const Color(0xFFFF2244)]
                : [const Color(0xFF003822), const Color(0xFF00FF88)]),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(
              color: (_overlayActive ? kRed : kGreen).withOpacity(.3),
              blurRadius: 16)],
          ),
          child: Center(child: Text(
            _overlayActive ? '■ HIDE FLOATING ICON' : '▶ LAUNCH FLOATING ICON',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                color: Colors.black, letterSpacing: 1.5))),
        ),
      ),
    ]);
  }

  Widget _step(String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Container(
          width: 22, height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: kGreen.withOpacity(.5)),
          ),
          child: Center(child: Text(n,
            style: const TextStyle(fontSize: 10, color: kGreen,
                fontWeight: FontWeight.bold))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text,
          style: const TextStyle(fontSize: 11, color: Colors.white70))),
      ]),
    );
  }

  Widget _buildStats() {
    return _card('SIGNAL STATS', [
      Row(children: [
        _statBox('TOTAL', '$_savedCount', kGold),
        const SizedBox(width: 8),
        _statBox('BUY',
          '${_history.where((s) => s['direction'] == 'buy').length}', kGreen),
        const SizedBox(width: 8),
        _statBox('SELL',
          '${_history.where((s) => s['direction'] == 'sell').length}', kRed),
      ]),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: () async { await _db.clearAll(); _loadHistory(); },
        child: const Text('Clear all history',
          style: TextStyle(fontSize: 10, color: Colors.white24,
              decoration: TextDecoration.underline)),
      ),
    ]);
  }

  Widget _statBox(String label, String val, Color clr) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: clr.withOpacity(.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: clr.withOpacity(.3)),
      ),
      child: Column(children: [
        Text(val, style: TextStyle(fontSize: 16,
            fontWeight: FontWeight.bold, color: clr)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 9,
            color: Colors.white38, letterSpacing: 1)),
      ]),
    ));
  }

  Widget _buildHistory() {
    return _card('SIGNAL HISTORY', [
      ..._history.take(10).map((s) {
        final buy = s['direction'] == 'buy';
        final clr = buy ? kGreen : kRed;
        final ts  = s['timestamp'].toString();
        final time = ts.length > 16 ? ts.substring(11, 16) : '';
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: kPanel, borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: clr, width: 3)),
          ),
          child: Row(children: [
            Text(buy ? 'BUY' : 'SELL',
              style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w900, color: clr, letterSpacing: 1)),
            const SizedBox(width: 10),
            Expanded(child: Text(
              '${s['timeframe']} · ${s['rule']}',
              style: const TextStyle(fontSize: 10, color: Colors.white38),
              overflow: TextOverflow.ellipsis)),
            Text('${s['confidence']}%\n$time',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
          ]),
        );
      }),
    ]);
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kPanel, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF152030)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 10,
            color: Colors.white38, letterSpacing: 2,
            fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }
}
