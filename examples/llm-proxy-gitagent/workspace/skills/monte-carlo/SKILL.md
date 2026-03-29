---
name: monte-carlo
description: >
  Foundation Monte Carlo simulation for binary contracts and prediction markets.
  GBM-based path simulation, binary payoff estimation, confidence intervals,
  and Brier score calibration. The base layer everything else builds on.
license: MIT
allowed-tools: Read Edit Grep Glob Bash
metadata:
  author: lyzr
  version: "1.0.0"
  category: quantitative-simulation
---

# Monte Carlo — The Foundation

## When to Use
When a user needs to estimate the probability of a binary event (e.g., "Will AAPL close
above $200?"), simulate terminal asset prices under GBM, or evaluate model calibration
with Brier scores.

## Core Concept

Every simulation reduces to: draw samples from a distribution, compute a statistic, repeat.

The estimator for event probability p = P(A) is the sample mean of indicator variables.
The Central Limit Theorem gives convergence rate O(N^{-1/2}), with variance
Var(p_hat) = p(1-p)/N.

**Critical insight:** Variance is maximized at p = 0.5. The most uncertain contracts
require the most samples for precision.

To hit +/-0.01 precision at 95% confidence when p = 0.50:
N = (1.96)^2 * 0.25 / (0.01)^2 = 9,604 samples.

## Binary Contract Simulation (GBM)

```python
import numpy as np

def simulate_binary_contract(S0, K, mu, sigma, T, N_paths=100_000):
    """
    Monte Carlo simulation for a binary contract.

    S0:      Current asset price
    K:       Strike / threshold
    mu:      Annual drift
    sigma:   Annual volatility
    T:       Time to expiry in years
    N_paths: Number of simulated paths
    """
    Z = np.random.standard_normal(N_paths)
    S_T = S0 * np.exp((mu - 0.5 * sigma**2) * T + sigma * np.sqrt(T) * Z)

    payoffs = (S_T > K).astype(float)

    p_hat = payoffs.mean()
    se = np.sqrt(p_hat * (1 - p_hat) / N_paths)
    ci_lower = p_hat - 1.96 * se
    ci_upper = p_hat + 1.96 * se

    return {
        'probability': p_hat,
        'std_error': se,
        'ci_95': (ci_lower, ci_upper),
        'N_paths': N_paths
    }

# Example: AAPL at $195, strike $200, 20% vol, 30 days
result = simulate_binary_contract(S0=195, K=200, mu=0.08, sigma=0.20, T=30/365)
print(f"P(AAPL > $200) = {result['probability']:.4f}")
print(f"95% CI: ({result['ci_95'][0]:.4f}, {result['ci_95'][1]:.4f})")
```

## Brier Score Calibration

```python
import numpy as np

def brier_score(predictions, outcomes):
    """Evaluate simulation calibration. Lower is better."""
    return np.mean((np.array(predictions) - np.array(outcomes))**2)

# Compare two models
model_A_preds = [0.7, 0.3, 0.9, 0.1]  # sharp, confident
model_B_preds = [0.5, 0.5, 0.5, 0.5]  # always uncertain
actual_outcomes = [1, 0, 1, 0]

print(f"Model A Brier: {brier_score(model_A_preds, actual_outcomes):.4f}")  # 0.05
print(f"Model B Brier: {brier_score(model_B_preds, actual_outcomes):.4f}")  # 0.25
```

**Benchmarks:**
- Below 0.20: good
- Below 0.10: excellent
- Best election forecasters (538, Economist): 0.06–0.12 on presidential races

## Assumptions That Break

- GBM assumes lognormal returns — real markets have fat tails and jumps
- Constant volatility — real vol is stochastic (see Heston model)
- Continuous trading — prediction markets have discrete order books
- No transaction costs — real markets have spread and slippage

When these assumptions fail, escalate to importance sampling, particle filters, or
agent-based simulation.
