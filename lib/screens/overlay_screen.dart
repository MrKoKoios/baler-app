import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../engine/signal_engine.dart';
import '../services/market_data_service.dart';
import '../services/database_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OVERLAY SCREEN v2
// Direct API scan — Binance থেকে real OHLCV data নিয়ে analysis করে।
// কোনো screenshot নেই। কোনো accessibility swipe নেই।
// ─────────────────────────────────────────────────────────────────────────────

enum OverlayState { icon, assetPick, scanning, result, signal }

class OverlayScreen extends StatefulWidget {
  const OverlayScreen({super.key});
  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen>
    with TickerProviderStateMixin {

  OverlayState _state   = OverlayState.icon;
  MarketAsset  _asset   = kAssets[0];
  String       _tf      = '1M';
  String       _logMsg  = 'Ready to scan...';
  bool         _loading = false;

  final _engine  = SignalEngine();
  final _mds     = MarketDataService();
  final _db      = DatabaseService();

  SignalResult?     _result;
  List<Candle>      _candles  = [];
  Map<String, dynamic> _stats24 = {};

  late AnimationController _pulseCtrl;
  late AnimationController _scanCtrl;
  late Animation<double>   _pulseAnim;
  late Animation<double>   _scanAnim;

  static const Color kGreen = Color(0xFF00FF88);
  static const Color kRed   = Color(0xFFFF2244);
  static const Color kGold  = Color(0xFFFFD700);
  static const Color kBg    = Color(0xFF020408);
  static const Color kPanel = Color(0xFF080D16);

  int get _sw => (ui.PlatformDispatcher.instance.views.first.physicalSize.width /
                  ui.PlatformDispatcher.instance.views.first.devicePixelRatio).toInt();
  int get _sh => (ui.PlatformDispatcher.instance.views.first.physicalSize.height /
                  ui.PlatformDispatcher.instance.views.first.devicePixelRatio).toInt();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _scanCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
    _pulseAnim = Tween<double>(begin: 0.75, end: 1.0).animate(_pulseCtrl);
    _scanAnim  = Tween<double>(begin: 0.0,  end: 1.0).animate(_scanCtrl);
    _db.init();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _scanCtrl.dispose();
    super.dispose();
  }

  // ── Icon tap → asset picker
  void _expand() {
    FlutterOverlayWindow.resizeOverlay(_sw, _sh, true);
    setState(() => _state = OverlayState.assetPick);
  }

  void _collapse() {
    FlutterOverlayWindow.resizeOverlay(72, 72, true);
    setState(() => _state = OverlayState.icon);
  }

  // ── Asset selected → timeframe → scan
  void _selectAsset(MarketAsset asset) {
    setState(() { _asset = asset; _state = OverlayState.scanning; });
    _runScan();
  }

  void _changeTF(String tf) {
    setState(() { _tf = tf; _state = OverlayState.scanning; });
    _runScan();
  }

  // ── Main scan: fetch candles → analyze
  Future<void> _runScan() async {
    setState(() {
      _loading = true;
      _logMsg  = 'Connecting to market data...';
      _candles = [];
    });

    try {
      setState(() => _logMsg = 'Fetching ${_asset.symbol} candles...');

      // Binance থেকে candles নাও
      final candles = await _mds.fetchCandles(
        binanceSymbol: _asset.binance,
        timeframe: _tf,
        limit: 100,
      );

      setState(() => _logMsg = 'Fetching 24h stats...');
      Map<String, dynamic> stats = {};
      try {
        stats = await _mds.fetch24hStats(_asset.binance);
      } catch (_) {}

      setState(() => _logMsg = 'Running SMC / ICT analysis...');
      await Future.delayed(const Duration(milliseconds: 500)); // UI breathe

      // Signal engine চালাও
      final result = _engine.analyze(
        candles: candles,
        timeframe: _tf,
        asset: _asset.symbol,
      );

      // DB তে save
      await _db.saveSignal(result);

      setState(() {
        _candles  = candles;
        _stats24  = stats;
        _result   = result;
        _loading  = false;
        _state    = OverlayState.signal;
        _logMsg   = 'Analysis complete — ${candles.length} candles processed';
      });

    } catch (e) {
      setState(() {
        _loading = false;
        _state   = OverlayState.result;
        _logMsg  = 'Error: $e';
      });
    }
  }

  Future<void> _reset() async {
    setState(() {
      _result  = null;
      _candles = [];
      _state   = OverlayState.assetPick;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: _state == OverlayState.icon
          ? _buildIcon()
          : _buildPanel(),
    );
  }

  Widget _buildIcon() {
    return GestureDetector(
      onTap: _expand,
      child: ScaleTransition(
        scale: _pulseAnim,
        child: Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: kGreen, width: 2),
            boxShadow: [
              BoxShadow(color: kGreen.withOpacity(.6), blurRadius: 18)
            ],
          ),
          child: ClipOval(
              child: Image.asset('assets/logo.jpg', fit: BoxFit.cover)),
        ),
      ),
    );
  }

  Widget _buildPanel() {
    return Container(
      color: kBg,
      child: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF152030)))),
      child: Row(children: [
        _logo(40),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                  colors: [kGreen, Colors.white, kRed]).createShader(b),
              child: const Text('MR KOKO SIGNAL PRO',
                style: TextStyle(fontFamily: 'monospace', fontSize: 13,
                    fontWeight: FontWeight.w900, color: Colors.white,
                    letterSpacing: 1.5)),
            ),
            Text('${_asset.symbol} · $_tf',
              style: const TextStyle(fontSize: 9, color: Colors.white38,
                  letterSpacing: 1.5)),
          ],
        )),
        // Status chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _stateColor()),
            color: _stateColor().withOpacity(.1),
          ),
          child: Text(_stateLabel(),
            style: TextStyle(fontSize: 9, letterSpacing: 1,
                color: _stateColor(), fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _collapse,
          child: const Icon(Icons.close, color: Colors.white38, size: 20)),
      ]),
    );
  }

  Color  _stateColor() {
    switch (_state) {
      case OverlayState.scanning: return kGold;
      case OverlayState.signal:   return kGreen;
      case OverlayState.result:   return kRed;
      default:                    return Colors.white24;
    }
  }
  String _stateLabel() {
    switch (_state) {
      case OverlayState.assetPick: return 'ASSET';
      case OverlayState.scanning:  return 'LIVE';
      case OverlayState.signal:    return 'SIGNAL';
      case OverlayState.result:    return 'ERROR';
      default:                     return 'IDLE';
    }
  }

  Widget _buildBody() {
    switch (_state) {
      case OverlayState.assetPick: return _buildAssetPicker();
      case OverlayState.scanning:  return _buildScanning();
      case OverlayState.signal:    return _buildSignal();
      case OverlayState.result:    return _buildError();
      default:                     return const SizedBox();
    }
  }

  // ── Asset + TF picker
  Widget _buildAssetPicker() {
    final tfs = ['1M', '5M', '15M', '30M', '1H'];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Timeframe row
        _sectionLabel('TIMEFRAME'),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: tfs.map((tf) => GestureDetector(
              onTap: () => setState(() => _tf = tf),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _tf == tf ? kGold : const Color(0xFF152030)),
                  color: _tf == tf ? kGold.withOpacity(.12) : kPanel,
                ),
                child: Center(child: Text(tf,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                      color: _tf == tf ? kGold : Colors.white38,
                      letterSpacing: 1))),
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // Asset grid
        _sectionLabel('SELECT ASSET'),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, childAspectRatio: 2.8,
              mainAxisSpacing: 8, crossAxisSpacing: 8),
          itemCount: kAssets.length,
          itemBuilder: (_, i) {
            final a    = kAssets[i];
            final sel  = a.symbol == _asset.symbol;
            final isOtc = a.type == 'otc';
            return GestureDetector(
              onTap: () => _selectAsset(a),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: sel ? kGreen : const Color(0xFF152030), width: sel ? 2 : 1),
                  color: sel ? kGreen.withOpacity(.08) : kPanel,
                ),
                child: Row(children: [
                  const SizedBox(width: 10),
                  Text(isOtc ? '🔶' : '🔵', style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.symbol,
                        style: TextStyle(fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: sel ? kGreen : Colors.white70),
                        overflow: TextOverflow.ellipsis),
                      Text(a.type.toUpperCase(),
                        style: const TextStyle(fontSize: 8,
                            color: Colors.white24, letterSpacing: 1)),
                    ],
                  )),
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_forward_ios,
                      size: 10,
                      color: sel ? kGreen : Colors.white24),
                  const SizedBox(width: 8),
                ]),
              ),
            );
          },
        ),
      ]),
    );
  }

  // ── Scanning / loading
  Widget _buildScanning() {
    return Column(children: [
      const SizedBox(height: 32),
      AnimatedBuilder(
        animation: _scanAnim,
        builder: (_, __) {
          final t = _scanAnim.value;
          return Stack(alignment: Alignment.center, children: [
            // Outer ring
            Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: kGreen.withOpacity(0.2 + 0.4 * sin(t * pi * 2).abs()),
                    width: 2),
              ),
            ),
            // Inner pulse
            Container(
              width: 80 + 20 * sin(t * pi * 2).abs(), 
              height: 80 + 20 * sin(t * pi * 2).abs(),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kGreen.withOpacity(0.05 + 0.1 * sin(t * pi * 2).abs()),
                border: Border.all(color: kGreen.withOpacity(.4), width: 1),
              ),
            ),
            _logo(56),
          ]);
        },
      ),
      const SizedBox(height: 24),
      Text(_asset.symbol,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
            color: Colors.white, letterSpacing: 2)),
      const SizedBox(height: 4),
      Text('$_tf · Binance API',
        style: const TextStyle(fontSize: 10, color: kGold, letterSpacing: 1)),
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(_logMsg,
          style: const TextStyle(fontSize: 11, color: kGreen,
              fontFamily: 'monospace', letterSpacing: 0.5),
          textAlign: TextAlign.center),
      ),
      const SizedBox(height: 8),
      const SizedBox(
        width: 200,
        child: LinearProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(kGreen),
          backgroundColor: Color(0xFF152030),
        ),
      ),
      const Spacer(),
      Padding(
        padding: const EdgeInsets.all(16),
        child: _outlineBtn('← BACK', _reset),
      ),
    ]);
  }

  // ── Signal result
  Widget _buildSignal() {
    final r   = _result!;
    final buy = r.direction == SignalDirection.buy;
    final clr = buy ? kGreen : kRed;
    final pct24 = _stats24['priceChangePercent'] != null
        ? double.tryParse(_stats24['priceChangePercent'].toString())?.toStringAsFixed(2)
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [

        // ── Signal card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: clr.withOpacity(.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: clr.withOpacity(.4), width: 2),
            boxShadow: [BoxShadow(color: clr.withOpacity(.2), blurRadius: 20)],
          ),
          child: Column(children: [
            Text(buy ? 'BUY' : 'SELL',
              style: TextStyle(fontSize: 46, fontWeight: FontWeight.w900,
                  color: clr, letterSpacing: 4,
                  shadows: [Shadow(color: clr, blurRadius: 24)])),
            const SizedBox(height: 4),
            Text('${_asset.symbol} · $_tf',
              style: const TextStyle(fontSize: 12, color: kGold, letterSpacing: 2)),
            const SizedBox(height: 10),
            // Confidence bar
            Row(children: [
              const Text('CONFIDENCE',
                style: TextStyle(fontSize: 9, color: Colors.white38, letterSpacing: 1)),
              const Spacer(),
              Text('${r.confidence}%',
                style: TextStyle(fontSize: 12, color: clr,
                    fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: r.confidence / 100,
                valueColor: AlwaysStoppedAnimation<Color>(clr),
                backgroundColor: clr.withOpacity(.15),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 10),
            Text(r.rule,
              style: const TextStyle(fontSize: 10, color: Colors.white54),
              textAlign: TextAlign.center),
          ]),
        ),
        const SizedBox(height: 12),

        // ── Entry / TP / SL
        Row(children: [
          _priceTile('ENTRY', r.entryPrice, Colors.white70),
          const SizedBox(width: 6),
          _priceTile('TP', r.tp, kGreen),
          const SizedBox(width: 6),
          _priceTile('SL', r.sl, kRed),
        ]),
        const SizedBox(height: 12),

        // ── 24h stats
        if (_stats24.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kPanel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF152030)),
            ),
            child: Row(children: [
              _miniStat('24H %',
                pct24 != null
                    ? (double.tryParse(pct24)! >= 0 ? '+$pct24%' : '$pct24%')
                    : '--',
                pct24 != null && double.tryParse(pct24)! >= 0 ? kGreen : kRed),
              _vDiv(),
              _miniStat('HIGH',
                  _fmt(_stats24['highPrice']), Colors.white54),
              _vDiv(),
              _miniStat('LOW',
                  _fmt(_stats24['lowPrice']),  Colors.white54),
              _vDiv(),
              _miniStat('CANDLES',
                  '${_candles.length}', kGold),
            ]),
          ),
          const SizedBox(height: 12),
        ],

        // ── Confirmations
        _sectionLabel('CONFIRMATIONS (${r.confirmations.length})'),
        const SizedBox(height: 6),
        ...r.confirmations.take(6).map((c) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(children: [
            Icon(
              c.startsWith('▲') ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12,
              color: c.startsWith('▲') ? kGreen : kRed,
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(c.substring(2),
              style: const TextStyle(fontSize: 10, color: Colors.white54))),
          ]),
        )),
        const SizedBox(height: 12),

        // ── Buttons
        Row(children: [
          Expanded(child: _btn('↺ RESCAN', kGreen, Colors.black, _runScan)),
          const SizedBox(width: 8),
          Expanded(child: _btn('ASSET', kPanel, Colors.white54, _reset,
              border: const Color(0xFF152030))),
        ]),
        const SizedBox(height: 6),
        _btn('⚡ CHANGE TF', kGold, Colors.black, () {
          setState(() => _state = OverlayState.assetPick);
        }),
        const SizedBox(height: 8),
      ]),
    );
  }

  // ── Error state
  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off, color: kRed, size: 48),
          const SizedBox(height: 16),
          const Text('Market data unavailable',
            style: TextStyle(fontSize: 14, color: Colors.white70)),
          const SizedBox(height: 8),
          Text(_logMsg,
            style: const TextStyle(fontSize: 10, color: Colors.white38,
                fontFamily: 'monospace'),
            textAlign: TextAlign.center),
          const SizedBox(height: 24),
          _btn('↺ RETRY', kGreen, Colors.black, () {
            setState(() => _state = OverlayState.scanning);
            _runScan();
          }),
          const SizedBox(height: 8),
          _outlineBtn('← BACK', _reset),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _logo(double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: kGreen, width: 2),
        boxShadow: [BoxShadow(color: kGreen.withOpacity(.4), blurRadius: 10)],
      ),
      child: ClipOval(
          child: Image.asset('assets/logo.jpg', fit: BoxFit.cover)),
    );
  }

  Widget _priceTile(String label, double? price, Color clr) {
    final text = price != null ? _fmt(price) : '--';
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: clr.withOpacity(.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: clr.withOpacity(.25)),
      ),
      child: Column(children: [
        Text(label, style: const TextStyle(fontSize: 8,
            color: Colors.white38, letterSpacing: 1)),
        const SizedBox(height: 3),
        Text(text, style: TextStyle(fontSize: 11,
            fontWeight: FontWeight.bold, color: clr)),
      ]),
    ));
  }

  Widget _miniStat(String label, String val, Color clr) {
    return Expanded(child: Column(children: [
      Text(val, style: TextStyle(fontSize: 11,
          fontWeight: FontWeight.bold, color: clr)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 8,
          color: Colors.white24, letterSpacing: 1)),
    ]));
  }

  Widget _vDiv() => Container(
    width: 1, height: 28, color: const Color(0xFF152030),
    margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _sectionLabel(String t) => Text(t,
    style: const TextStyle(fontSize: 9, color: Colors.white24,
        letterSpacing: 2, fontWeight: FontWeight.bold));

  Widget _btn(String label, Color bg, Color fg, VoidCallback? onTap,
      {Color? border}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: onTap == null ? 0.3 : 1.0,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border ?? bg),
            boxShadow: bg != kPanel && bg != Colors.transparent
                ? [BoxShadow(color: bg.withOpacity(.25), blurRadius: 12)]
                : null,
          ),
          child: Center(child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                color: fg, letterSpacing: 1.5))),
        ),
      ),
    );
  }

  Widget _outlineBtn(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF152030)),
      ),
      child: Center(child: Text(label,
        style: const TextStyle(fontSize: 11, color: Colors.white38,
            letterSpacing: 1))),
    ),
  );

  String _fmt(dynamic v) {
    if (v == null) return '--';
    final d = double.tryParse(v.toString());
    if (d == null) return '--';
    if (d >= 1000) return d.toStringAsFixed(2);
    if (d >= 1)    return d.toStringAsFixed(4);
    return d.toStringAsFixed(6);
  }
}
