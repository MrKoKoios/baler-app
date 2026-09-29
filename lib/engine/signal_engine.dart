import 'dart:math';
import 'market_data_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SIGNAL ENGINE v2 — Real Technical Analysis on OHLCV Candles
// SMC + ICT + Price Action + Indicators
// ─────────────────────────────────────────────────────────────────────────────

enum SignalDirection { buy, sell, none }

class SignalResult {
  final SignalDirection direction;
  final int confidence;
  final String rule;        // primary trigger
  final String timeframe;
  final List<String> confirmations;
  final DateTime timestamp;
  final double entryPrice;
  final double? tp;         // take profit
  final double? sl;         // stop loss

  const SignalResult({
    required this.direction,
    required this.confidence,
    required this.rule,
    required this.timeframe,
    required this.confirmations,
    required this.timestamp,
    required this.entryPrice,
    this.tp,
    this.sl,
  });

  Map<String, dynamic> toMap() => {
    'direction':     direction.name,
    'confidence':    confidence,
    'rule':          rule,
    'timeframe':     timeframe,
    'confirmations': confirmations.join('|'),
    'timestamp':     timestamp.toIso8601String(),
  };
}

// ── Individual analysis result from one rule
class _Vote {
  final bool bull;
  final double weight;   // 0.0–1.0
  final String label;
  const _Vote(this.bull, this.weight, this.label);
}

class SignalEngine {

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC — main entry point
  // ─────────────────────────────────────────────────────────────────────────

  SignalResult analyze({
    required List<Candle> candles,
    required String timeframe,
    required String asset,
  }) {
    if (candles.length < 20) {
      throw Exception('Need at least 20 candles for analysis');
    }

    final votes  = <_Vote>[];
    final c      = candles;           // short alias
    final last   = c.last;
    final prev   = c[c.length - 2];
    final close  = last.close;

    // ── 1. EMA crossover (9 / 21 / 50)
    final ema9  = _ema(c, 9);
    final ema21 = _ema(c, 21);
    final ema50 = c.length >= 50 ? _ema(c, 50) : null;

    if (ema9.last > ema21.last) {
      votes.add(const _Vote(true,  0.72, 'EMA 9 > EMA 21 — bullish cross'));
    } else {
      votes.add(const _Vote(false, 0.72, 'EMA 9 < EMA 21 — bearish cross'));
    }

    if (ema50 != null) {
      if (close > ema50.last) {
        votes.add(const _Vote(true,  0.68, 'Price above EMA 50'));
      } else {
        votes.add(const _Vote(false, 0.68, 'Price below EMA 50'));
      }
    }

    // ── 2. RSI (14)
    final rsi = _rsi(c, 14);
    if (rsi < 30) {
      votes.add(_Vote(true,  0.88, 'RSI ${ rsi.toStringAsFixed(1) } — Oversold zone'));
    } else if (rsi > 70) {
      votes.add(_Vote(false, 0.88, 'RSI ${ rsi.toStringAsFixed(1) } — Overbought zone'));
    } else if (rsi < 45) {
      votes.add(_Vote(true,  0.55, 'RSI ${ rsi.toStringAsFixed(1) } — Bearish lean'));
    } else if (rsi > 55) {
      votes.add(_Vote(false, 0.55, 'RSI ${ rsi.toStringAsFixed(1) } — Bullish lean'));
    }

    // ── 3. MACD
    final macd = _macd(c);
    if (macd['histogram']! > 0 && macd['histogram']! > macd['prevHistogram']!) {
      votes.add(const _Vote(true,  0.78, 'MACD histogram rising — bullish momentum'));
    } else if (macd['histogram']! < 0 && macd['histogram']! < macd['prevHistogram']!) {
      votes.add(const _Vote(false, 0.78, 'MACD histogram falling — bearish momentum'));
    }

    // ── 4. Candlestick patterns
    _candlePatterns(c, votes);

    // ── 5. SMC — Structure
    _smcAnalysis(c, votes, ema21);

    // ── 6. Support / Resistance
    _srAnalysis(c, votes);

    // ── 7. Volume analysis
    _volumeAnalysis(c, votes);

    // ── 8. Bollinger Bands
    _bollingerAnalysis(c, votes);

    // ── Tally votes
    double bullScore = 0, bearScore = 0;
    final confirmations = <String>[];
    _Vote? topVote;
    double topWeight = 0;

    for (final v in votes) {
      if (v.bull) {
        bullScore += v.weight;
        if (v.weight > topWeight && bullScore > bearScore) {
          topWeight = v.weight;
          topVote   = v;
        }
      } else {
        bearScore += v.weight;
        if (v.weight > topWeight && bearScore > bullScore) {
          topWeight = v.weight;
          topVote   = v;
        }
      }
    }

    for (final v in votes) {
      final icon = v.bull ? '▲' : '▼';
      confirmations.add('$icon ${v.label}');
    }

    final isBull     = bullScore >= bearScore;
    final totalScore = bullScore + bearScore;
    final rawConf    = totalScore > 0
        ? ((isBull ? bullScore : bearScore) / totalScore * 100).round()
        : 50;
    final confidence = rawConf.clamp(55, 99);

    // ── TP / SL based on ATR
    final atr  = _atr(c, 14);
    final tp   = isBull ? close + atr * 1.5 : close - atr * 1.5;
    final sl   = isBull ? close - atr * 0.8 : close + atr * 0.8;

    final direction = votes.isEmpty
        ? SignalDirection.none
        : (isBull ? SignalDirection.buy : SignalDirection.sell);

    return SignalResult(
      direction:     direction,
      confidence:    confidence,
      rule:          topVote?.label ?? (isBull ? 'Bullish confluence' : 'Bearish confluence'),
      timeframe:     timeframe,
      confirmations: confirmations,
      timestamp:     DateTime.now(),
      entryPrice:    close,
      tp:            tp,
      sl:            sl,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INDICATORS
  // ─────────────────────────────────────────────────────────────────────────

  // EMA
  List<double> _ema(List<Candle> c, int period) {
    final k      = 2.0 / (period + 1);
    final result = <double>[];
    double ema   = c.take(period).map((x) => x.close).reduce((a, b) => a + b) / period;
    result.add(ema);
    for (int i = period; i < c.length; i++) {
      ema = c[i].close * k + ema * (1 - k);
      result.add(ema);
    }
    return result;
  }

  // RSI (14)
  double _rsi(List<Candle> c, int period) {
    if (c.length < period + 1) return 50;
    double gains = 0, losses = 0;
    for (int i = c.length - period; i < c.length; i++) {
      final diff = c[i].close - c[i - 1].close;
      if (diff > 0) gains  += diff;
      else          losses -= diff;
    }
    if (losses == 0) return 100;
    final rs = gains / losses;
    return 100 - (100 / (1 + rs));
  }

  // MACD (12, 26, 9)
  Map<String, double> _macd(List<Candle> c) {
    if (c.length < 35) return {'histogram': 0, 'prevHistogram': 0};
    final ema12 = _ema(c, 12);
    final ema26 = _ema(c, 26);

    // Align: ema12 is longer by 14 elements
    final offset = ema12.length - ema26.length;
    final macdLine = List.generate(
        ema26.length, (i) => ema12[i + offset] - ema26[i]);

    // Signal (9 EMA of macdLine)
    if (macdLine.length < 9) return {'histogram': 0, 'prevHistogram': 0};
    double sig = macdLine.take(9).reduce((a, b) => a + b) / 9;
    double prevSig = sig;
    for (int i = 9; i < macdLine.length - 1; i++) {
      prevSig = sig;
      sig = macdLine[i] * (2.0 / 10) + sig * (8.0 / 10);
    }

    final hist     = macdLine.last - sig;
    final prevHist = macdLine[macdLine.length - 2] - prevSig;
    return {'histogram': hist, 'prevHistogram': prevHist};
  }

  // ATR (14)
  double _atr(List<Candle> c, int period) {
    if (c.length < period + 1) return c.last.range;
    double atr = 0;
    for (int i = c.length - period; i < c.length; i++) {
      final tr = [
        c[i].range,
        (c[i].high - c[i - 1].close).abs(),
        (c[i].low  - c[i - 1].close).abs(),
      ].reduce(max);
      atr += tr;
    }
    return atr / period;
  }

  // Bollinger Bands (20, 2σ)
  Map<String, double> _bollinger(List<Candle> c, {int period = 20}) {
    if (c.length < period) {
      return {'upper': c.last.close, 'lower': c.last.close, 'mid': c.last.close};
    }
    final window = c.sublist(c.length - period).map((x) => x.close).toList();
    final mean   = window.reduce((a, b) => a + b) / period;
    final variance = window.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / period;
    final stddev = sqrt(variance);
    return {
      'upper': mean + 2 * stddev,
      'lower': mean - 2 * stddev,
      'mid':   mean,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PATTERN DETECTION
  // ─────────────────────────────────────────────────────────────────────────

  void _candlePatterns(List<Candle> c, List<_Vote> votes) {
    final last  = c.last;
    final prev  = c[c.length - 2];
    final prev2 = c.length >= 3 ? c[c.length - 3] : null;

    // Engulfing
    if (last.isBull && !prev.isBull &&
        last.close > prev.open && last.open < prev.close) {
      votes.add(const _Vote(true, 0.84, 'Bullish Engulfing — reversal signal'));
    }
    if (!last.isBull && prev.isBull &&
        last.close < prev.open && last.open > prev.close) {
      votes.add(const _Vote(false, 0.84, 'Bearish Engulfing — reversal signal'));
    }

    // Doji (body < 10% of range)
    if (last.range > 0 && last.body / last.range < 0.1) {
      final prevBull = prev.isBull;
      votes.add(_Vote(!prevBull, 0.65, 'Doji at key level — indecision/reversal'));
    }

    // Pin Bar (wick > 2× body, small opposite wick)
    if (last.range > 0) {
      final lowerRatio = last.lowerWick / last.range;
      final upperRatio = last.upperWick / last.range;
      if (lowerRatio > 0.6 && last.lowerWick > 2 * last.body) {
        votes.add(const _Vote(true, 0.82, 'Bullish Pin Bar — rejection at low'));
      }
      if (upperRatio > 0.6 && last.upperWick > 2 * last.body) {
        votes.add(const _Vote(false, 0.82, 'Bearish Pin Bar — rejection at high'));
      }
    }

    // Morning/Evening Star
    if (prev2 != null) {
      final midBody = prev.body;
      final midRange = prev.range;
      if (!prev2.isBull && midRange > 0 && midBody / midRange < 0.3 && last.isBull &&
          last.close > (prev2.open + prev2.close) / 2) {
        votes.add(const _Vote(true, 0.87, 'Morning Star — strong bullish reversal'));
      }
      if (prev2.isBull && midRange > 0 && midBody / midRange < 0.3 && !last.isBull &&
          last.close < (prev2.open + prev2.close) / 2) {
        votes.add(const _Vote(false, 0.87, 'Evening Star — strong bearish reversal'));
      }
    }

    // Three white soldiers / Three black crows
    if (prev2 != null) {
      if (last.isBull && prev.isBull && prev2.isBull &&
          last.close > prev.close && prev.close > prev2.close) {
        votes.add(const _Vote(true, 0.80, 'Three White Soldiers — strong uptrend'));
      }
      if (!last.isBull && !prev.isBull && !prev2.isBull &&
          last.close < prev.close && prev.close < prev2.close) {
        votes.add(const _Vote(false, 0.80, 'Three Black Crows — strong downtrend'));
      }
    }
  }

  void _smcAnalysis(List<Candle> c, List<_Vote> votes, List<double> ema21) {
    if (c.length < 10) return;

    final last  = c.last;
    final prev  = c[c.length - 2];

    // BOS — Break of Structure
    // Simple: new high above last 5 candles' high = bullish BOS
    final last5High = c.sublist(c.length - 6, c.length - 1)
        .map((x) => x.high).reduce(max);
    final last5Low  = c.sublist(c.length - 6, c.length - 1)
        .map((x) => x.low).reduce(min);

    if (last.close > last5High) {
      votes.add(const _Vote(true, 0.86, 'SMC: BOS — Break of Structure (bullish)'));
    } else if (last.close < last5Low) {
      votes.add(const _Vote(false, 0.86, 'SMC: BOS — Break of Structure (bearish)'));
    }

    // CHoCH — Check if trend recently flipped
    final recent10 = c.sublist(max(0, c.length - 10));
    int bullCandles = recent10.where((x) => x.isBull).length;
    if (bullCandles >= 7 && !last.isBull) {
      votes.add(const _Vote(false, 0.78, 'SMC: CHoCH — Change of Character detected'));
    } else if (bullCandles <= 3 && last.isBull) {
      votes.add(const _Vote(true, 0.78, 'SMC: CHoCH — Change of Character detected'));
    }

    // Order Block: big candle 3-5 bars ago, price returning to its body
    for (int i = 3; i <= 6 && i < c.length - 1; i++) {
      final ob = c[c.length - 1 - i];
      if (ob.body / (ob.range + 0.0001) > 0.6) {
        final obMid  = (ob.open + ob.close) / 2;
        final inZone = last.low <= ob.high && last.high >= ob.low;
        if (inZone) {
          if (ob.isBull) {
            votes.add(_Vote(true, 0.89,
                'SMC: Demand OB mitigation at ${obMid.toStringAsFixed(4)}'));
          } else {
            votes.add(_Vote(false, 0.89,
                'SMC: Supply OB mitigation at ${obMid.toStringAsFixed(4)}'));
          }
          break;
        }
      }
    }

    // FVG — Fair Value Gap (ICT)
    if (c.length >= 3) {
      final c1 = c[c.length - 3];
      final c3 = c[c.length - 1];
      // Bull FVG: c1.high < c3.low (gap above)
      if (c1.high < c3.low) {
        votes.add(const _Vote(true, 0.83, 'ICT: Bullish Fair Value Gap — target fill'));
      }
      // Bear FVG: c1.low > c3.high (gap below)
      if (c1.low > c3.high) {
        votes.add(const _Vote(false, 0.83, 'ICT: Bearish Fair Value Gap — target fill'));
      }
    }
  }

  void _srAnalysis(List<Candle> c, List<_Vote> votes) {
    if (c.length < 20) return;

    final last    = c.last;
    final highs   = c.map((x) => x.high).toList();
    final lows    = c.map((x) => x.low).toList();
    final atr     = _atr(c, 14);
    final zone    = atr * 0.3;    // tolerance for S/R touch

    // Find pivot highs/lows in last 30 candles
    final window = c.sublist(max(0, c.length - 30));

    double? pivotHigh;
    double? pivotLow;
    for (int i = 2; i < window.length - 2; i++) {
      final h = window[i].high;
      if (h > window[i-1].high && h > window[i-2].high &&
          h > window[i+1].high && h > window[i+2].high) {
        if (pivotHigh == null || h > pivotHigh) pivotHigh = h;
      }
      final l = window[i].low;
      if (l < window[i-1].low && l < window[i-2].low &&
          l < window[i+1].low && l < window[i+2].low) {
        if (pivotLow == null || l < pivotLow) pivotLow = l;
      }
    }

    if (pivotHigh != null && (last.close - pivotHigh).abs() < zone) {
      votes.add(_Vote(false, 0.80,
          'Resistance at ${pivotHigh.toStringAsFixed(4)} — potential rejection'));
    }
    if (pivotLow != null && (last.close - pivotLow).abs() < zone) {
      votes.add(_Vote(true, 0.80,
          'Support at ${pivotLow.toStringAsFixed(4)} — potential bounce'));
    }

    // Double bottom / Double top (simplified)
    if (pivotLow != null) {
      final prevTouches = window.where((x) => (x.low - pivotLow!).abs() < zone).length;
      if (prevTouches >= 2 && last.isBull) {
        votes.add(_Vote(true, 0.86,
            'Double Bottom at ${pivotLow.toStringAsFixed(4)}'));
      }
    }
    if (pivotHigh != null) {
      final prevTouches = window.where((x) => (x.high - pivotHigh!).abs() < zone).length;
      if (prevTouches >= 2 && !last.isBull) {
        votes.add(_Vote(false, 0.86,
            'Double Top at ${pivotHigh.toStringAsFixed(4)}'));
      }
    }
  }

  void _volumeAnalysis(List<Candle> c, List<_Vote> votes) {
    if (c.length < 10) return;

    final last    = c.last;
    final avgVol  = c.sublist(c.length - 10, c.length - 1)
        .map((x) => x.volume).reduce((a, b) => a + b) / 9;

    if (last.volume > avgVol * 1.8) {
      // High volume — confirms direction
      final label = last.isBull
          ? 'Volume spike ${(last.volume / avgVol).toStringAsFixed(1)}× — strong buying'
          : 'Volume spike ${(last.volume / avgVol).toStringAsFixed(1)}× — strong selling';
      votes.add(_Vote(last.isBull, 0.75, label));
    } else if (last.volume < avgVol * 0.5) {
      // Low volume — weak move, possible reversal
      votes.add(_Vote(!last.isBull, 0.55, 'Low volume on this candle — weak move'));
    }
  }

  void _bollingerAnalysis(List<Candle> c, List<_Vote> votes) {
    if (c.length < 20) return;

    final last = c.last;
    final bb   = _bollinger(c);

    if (last.close <= bb['lower']!) {
      votes.add(const _Vote(true, 0.82, 'Price at Lower Bollinger Band — oversold squeeze'));
    } else if (last.close >= bb['upper']!) {
      votes.add(const _Vote(false, 0.82, 'Price at Upper Bollinger Band — overbought squeeze'));
    } else if ((last.close - bb['mid']!).abs() / (bb['upper']! - bb['mid']!) < 0.1) {
      // Price near middle band — directional from trend
      final trend = last.close > bb['mid']!;
      votes.add(_Vote(trend, 0.60, 'Price at BB midline — trend continuation'));
    }
  }
}
