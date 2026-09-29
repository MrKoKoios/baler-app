import 'dart:convert';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// MARKET DATA SERVICE
// Binance API → real OHLCV candles (no screenshot, no accessibility)
// ─────────────────────────────────────────────────────────────────────────────

class Candle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  double get body     => (close - open).abs();
  double get range    => high - low;
  bool   get isBull   => close >= open;
  double get upperWick => high - (isBull ? close : open);
  double get lowerWick => (isBull ? open : close) - low;

  @override
  String toString() =>
      'Candle(${time.toIso8601String()} O:$open H:$high L:$low C:$close V:$volume)';
}

// ── Asset definition
class MarketAsset {
  final String symbol;    // display name  e.g. "BTC/USDT"
  final String binance;   // Binance symbol e.g. "BTCUSDT"
  final String type;      // "crypto" | "otc"
  const MarketAsset(this.symbol, this.binance, this.type);
}

// ── Timeframe mapping: user label → Binance interval
const Map<String, String> kTFtoBinance = {
  '5S':  '1m',   // 5s নেই, 1m নেব তারপর interpolate
  '15S': '1m',
  '20S': '1m',
  '1M':  '1m',
  '5M':  '5m',
  '15M': '15m',
  '30M': '30m',
  '1H':  '1h',
  '4H':  '4h',
};

// ── Available assets (Binance-listed)
const List<MarketAsset> kAssets = [
  MarketAsset('EUR/USD (OTC)', 'EURUSDT',  'otc'),
  MarketAsset('GBP/USD (OTC)', 'GBPUSDT',  'otc'),
  MarketAsset('BTC/USDT',      'BTCUSDT',  'crypto'),
  MarketAsset('ETH/USDT',      'ETHUSDT',  'crypto'),
  MarketAsset('BNB/USDT',      'BNBUSDT',  'crypto'),
  MarketAsset('XRP/USDT',      'XRPUSDT',  'crypto'),
  MarketAsset('SOL/USDT',      'SOLUSDT',  'crypto'),
  MarketAsset('DOGE/USDT',     'DOGEUSDT', 'crypto'),
  MarketAsset('ADA/USDT',      'ADAUSDT',  'crypto'),
  MarketAsset('MATIC/USDT',    'MATICUSDT','crypto'),
];

class MarketDataService {

  static const String _binanceBase = 'https://api.binance.com/api/v3';
  static const Duration _timeout   = Duration(seconds: 10);

  // ── Real OHLCV candles from Binance
  // limit: কতটা candle নেব (max 500)
  Future<List<Candle>> fetchCandles({
    required String binanceSymbol,
    required String timeframe,    // user timeframe e.g. "5M"
    int limit = 100,
  }) async {
    final interval = kTFtoBinance[timeframe] ?? '1m';
    final uri = Uri.parse(
      '$_binanceBase/klines'
      '?symbol=$binanceSymbol'
      '&interval=$interval'
      '&limit=$limit',
    );

    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw Exception('Binance API error: ${resp.statusCode}');
    }

    final raw = jsonDecode(resp.body) as List;
    return raw.map((k) {
      // Binance kline format:
      // [openTime, open, high, low, close, volume, closeTime, ...]
      return Candle(
        time:   DateTime.fromMillisecondsSinceEpoch(k[0] as int),
        open:   double.parse(k[1] as String),
        high:   double.parse(k[2] as String),
        low:    double.parse(k[3] as String),
        close:  double.parse(k[4] as String),
        volume: double.parse(k[5] as String),
      );
    }).toList();
  }

  // ── Current price (ticker)
  Future<double> fetchCurrentPrice(String binanceSymbol) async {
    final uri = Uri.parse('$_binanceBase/ticker/price?symbol=$binanceSymbol');
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) throw Exception('Price fetch failed');
    final data = jsonDecode(resp.body) as Map;
    return double.parse(data['price'] as String);
  }

  // ── 24hr stats
  Future<Map<String, dynamic>> fetch24hStats(String binanceSymbol) async {
    final uri = Uri.parse('$_binanceBase/ticker/24hr?symbol=$binanceSymbol');
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) throw Exception('Stats fetch failed');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}
