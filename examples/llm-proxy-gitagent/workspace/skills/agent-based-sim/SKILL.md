---
name: agent-based-sim
description: >
  Agent-based prediction market simulation with heterogeneous traders.
  Informed traders, noise traders, market makers, Kyle lambda price impact,
  order book dynamics, and emergent price discovery. Based on Gode & Sunder (1993),
  Farmer et al. (2005), and Kyle (1985).
license: MIT
allowed-tools: Read Edit Grep Glob Bash
metadata:
  author: lyzr
  version: "1.0.0"
  category: quantitative-simulation
---

# Agent-Based Simulation — Emergent Market Dynamics

## When to Use
When you need to model prediction market microstructure:
- How fast do prices converge to true probabilities?
- What happens when informed/noise trader ratios shift?
- How do market maker spreads respond to information flow?
- Why do informed traders extract profit at noise traders' expense?

No closed-form SDE can capture these emergent dynamics from heterogeneous agents.

## The Zero-Intelligence Revelation

Gode & Sunder (1993): Markets achieve near-100% allocative efficiency even when every
trader is completely irrational — zero-intelligence agents with random orders subject
only to budget constraints.

Farmer, Patelli & Zovko (2005): Extended this to limit order books. **One parameter
explained 96% of cross-sectional spread variation** on the London Stock Exchange.

## Full Implementation

```python
import numpy as np

class PredictionMarketABM:
    """
    Agent-based model of a prediction market order book.

    Agent types:
    - Informed: know the true probability, trade toward it
    - Noise: random trades
    - Market maker: provides liquidity around current price
    """
    def __init__(self, true_prob, n_informed=10, n_noise=50, n_mm=5):
        self.true_prob = true_prob
        self.price = 0.50
        self.price_history = [self.price]

        self.best_bid = 0.49
        self.best_ask = 0.51

        self.n_informed = n_informed
        self.n_noise = n_noise
        self.n_mm = n_mm

        self.volume = 0
        self.informed_pnl = 0
        self.noise_pnl = 0

    def step(self):
        """One time step: randomly select an agent to trade."""
        total = self.n_informed + self.n_noise + self.n_mm
        r = np.random.random()

        if r < self.n_informed / total:
            self._informed_trade()
        elif r < (self.n_informed + self.n_noise) / total:
            self._noise_trade()
        else:
            self._mm_update()

        self.price_history.append(self.price)

    def _informed_trade(self):
        """Informed trader: buy if price < true_prob, sell otherwise."""
        signal = self.true_prob + np.random.normal(0, 0.02)

        if signal > self.best_ask + 0.01:
            size = min(0.1, abs(signal - self.price) * 2)
            self.price += size * self._kyle_lambda()
            self.volume += size
            self.informed_pnl += (self.true_prob - self.best_ask) * size
        elif signal < self.best_bid - 0.01:
            size = min(0.1, abs(self.price - signal) * 2)
            self.price -= size * self._kyle_lambda()
            self.volume += size
            self.informed_pnl += (self.best_bid - self.true_prob) * size

        self.price = np.clip(self.price, 0.01, 0.99)
        self._update_book()

    def _noise_trade(self):
        """Noise trader: random buy/sell."""
        direction = np.random.choice([-1, 1])
        size = np.random.exponential(0.02)
        self.price += direction * size * self._kyle_lambda()
        self.price = np.clip(self.price, 0.01, 0.99)
        self.volume += size
        self.noise_pnl -= abs(self.price - self.true_prob) * size * 0.5
        self._update_book()

    def _mm_update(self):
        """Market maker: tighten spread toward current price."""
        spread = max(0.02, 0.05 * (1 - self.volume / 100))
        self.best_bid = self.price - spread / 2
        self.best_ask = self.price + spread / 2

    def _kyle_lambda(self):
        """Kyle (1985) price impact parameter: lambda = sigma_v / (2 * sigma_u)"""
        sigma_v = abs(self.true_prob - self.price) + 0.05
        sigma_u = 0.1 * np.sqrt(self.n_noise)
        return sigma_v / (2 * sigma_u)

    def _update_book(self):
        spread = self.best_ask - self.best_bid
        self.best_bid = self.price - spread / 2
        self.best_ask = self.price + spread / 2

    def run(self, n_steps=1000):
        for _ in range(n_steps):
            self.step()
        return np.array(self.price_history)


# --- Simulation ---
np.random.seed(42)

sim = PredictionMarketABM(true_prob=0.65, n_informed=10, n_noise=50, n_mm=5)
prices = sim.run(n_steps=2000)

print("Agent-Based Prediction Market Simulation")
print(f"True probability:   {sim.true_prob:.2f}")
print(f"Starting price:     0.50")
print(f"Final price:        {prices[-1]:.4f}")
print(f"Price at t=500:     {prices[500]:.4f}")
print(f"Price at t=1000:    {prices[1000]:.4f}")
print(f"Total volume:       {sim.volume:.1f}")
print(f"Informed P&L:       ${sim.informed_pnl:.2f}")
print(f"Noise trader P&L:   ${sim.noise_pnl:.2f}")
print(f"Convergence error:  {abs(prices[-1] - sim.true_prob):.4f}")
```

## Key Dynamics

| Parameter | Effect |
|-----------|--------|
| n_informed / n_noise ratio | Higher = faster convergence to true probability |
| Market maker spread | Tightens as volume increases (information incorporated) |
| Kyle lambda | Price impact decreases with more noise traders (camouflage) |
| Informed P&L | Always positive — information advantage extracts value |
| Noise P&L | Always negative — the cost of providing liquidity without information |

## Extensions

- **Strategic informed traders** — Kyle (1985) optimal order splitting
- **Multiple informed with different signals** — Glosten-Milgrom (1985) sequential trade
- **Regime switches** — sudden changes in true probability (news events)
- **Network effects** — agents observe and copy other agents' trades
- **Latency arbitrage** — fast vs slow traders in the order book

## The Production Stack

```
LAYER 1: DATA INGESTION
  WebSocket feed from Polymarket CLOB API (real-time prices, volumes)
  News/poll feeds (NLP-processed into probability signals)
  On-chain event data (Polygon)

LAYER 2: PROBABILITY ENGINE
  Hierarchical Bayesian model (Stan/PyMC) — state-level posteriors
  Particle filter — real-time updating on new observations
  Jump-diffusion SDE path simulation — risk management
  Ensemble: weighted average of model outputs

LAYER 3: DEPENDENCY MODELING
  Vine copula — pairwise dependencies between contracts
  Factor model — shared national/global risk factors
  Tail dependence estimation via t-copula

LAYER 4: RISK MANAGEMENT
  EVT-based VaR and Expected Shortfall
  Reverse stress testing — identify worst-case scenarios
  Correlation stress — what if state correlations spike?
  Liquidity risk — order book depth monitoring

LAYER 5: MONITORING
  Brier score tracking (calibration)
  P&L attribution (which model component added value?)
  Drawdown alerts
  Model drift detection
```
