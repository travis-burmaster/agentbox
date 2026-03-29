---
name: variance-reduction
description: >
  Importance sampling for rare events, antithetic variates, control variates,
  stratified sampling, and stacking all three. Achieves 100-10,000x variance
  reduction over crude Monte Carlo. Table stakes for production simulation.
license: MIT
allowed-tools: Read Edit Grep Glob Bash
metadata:
  author: lyzr
  version: "1.0.0"
  category: quantitative-simulation
---

# Variance Reduction — Make Every Sample Count

## When to Use
When crude Monte Carlo is too slow or imprecise. Specifically:
- Tail-risk contracts (trading below $0.05 or above $0.95)
- Rare event estimation (market crashes, extreme outcomes)
- Production systems where compute budget matters
- Any contract where 100,000 samples still produce wide confidence intervals

## 1. Importance Sampling for Rare Events

When a contract trades at $0.003, crude MC at 100K samples produces zero or one hit.
Importance sampling tilts the distribution to oversample the rare region, then corrects
with a likelihood ratio.

```python
import numpy as np

def rare_event_IS(S0, K_crash, sigma, T, N_paths=100_000):
    """
    Importance sampling for extreme downside binary contracts.
    Example: P(S&P drops 20% in one week)
    """
    K = S0 * (1 - K_crash)
    mu_original = -0.5 * sigma**2
    log_threshold = np.log(K / S0)
    mu_tilt = log_threshold / T

    Z = np.random.standard_normal(N_paths)

    # Simulate under TILTED measure
    log_returns_tilted = mu_tilt * T + sigma * np.sqrt(T) * Z
    S_T_tilted = S0 * np.exp(log_returns_tilted)

    # Likelihood ratio
    log_LR = (
        -0.5 * ((log_returns_tilted - mu_original * T) / (sigma * np.sqrt(T)))**2
        + 0.5 * ((log_returns_tilted - mu_tilt * T) / (sigma * np.sqrt(T)))**2
    )
    LR = np.exp(log_LR)

    # IS estimator
    payoffs = (S_T_tilted < K).astype(float)
    is_estimates = payoffs * LR

    p_IS = is_estimates.mean()
    se_IS = is_estimates.std() / np.sqrt(N_paths)

    # Compare with crude MC
    Z_crude = np.random.standard_normal(N_paths)
    S_T_crude = S0 * np.exp(mu_original * T + sigma * np.sqrt(T) * Z_crude)
    p_crude = (S_T_crude < K).mean()
    se_crude = np.sqrt(p_crude * (1 - p_crude) / N_paths) if p_crude > 0 else float('inf')

    return {
        'p_IS': p_IS, 'se_IS': se_IS,
        'p_crude': p_crude, 'se_crude': se_crude,
        'variance_reduction': (se_crude / se_IS)**2 if se_IS > 0 else float('inf')
    }

result = rare_event_IS(S0=5000, K_crash=0.20, sigma=0.15, T=5/252)
print(f"IS estimate:    {result['p_IS']:.6f} +/- {result['se_IS']:.6f}")
print(f"Crude estimate: {result['p_crude']:.6f} +/- {result['se_crude']:.6f}")
print(f"Variance reduction: {result['variance_reduction']:.1f}x")
```

On extreme contracts, IS achieves 100–10,000x variance reduction.
100 IS samples can beat 1,000,000 crude samples.

## 2. Antithetic Variates — Free Symmetry

For monotone payoffs (all binary contracts), pair each draw Z with -Z:

```python
import numpy as np

def antithetic_binary(S0, K, sigma, T, N_paths=100_000):
    """Antithetic variates for binary contracts. ~50-75% variance reduction, zero cost."""
    N_half = N_paths // 2
    Z = np.random.standard_normal(N_half)

    S_T_pos = S0 * np.exp((-0.5 * sigma**2) * T + sigma * np.sqrt(T) * Z)
    S_T_neg = S0 * np.exp((-0.5 * sigma**2) * T + sigma * np.sqrt(T) * (-Z))

    payoff_pos = (S_T_pos > K).astype(float)
    payoff_neg = (S_T_neg > K).astype(float)
    paired = (payoff_pos + payoff_neg) / 2

    p_hat = paired.mean()
    se = paired.std() / np.sqrt(N_half)
    return p_hat, se

p, se = antithetic_binary(S0=100, K=105, sigma=0.20, T=30/365)
print(f"Antithetic estimate: {p:.6f} +/- {se:.6f}")
```

## 3. Stratified Sampling — Divide and Conquer

Partition the probability space into J strata, sample within each, combine.

```python
import numpy as np
from scipy.stats import norm

def stratified_binary_mc(S0, K, sigma, T, J=10, N_total=100_000):
    """Stratified MC for binary contract pricing."""
    n_per_stratum = N_total // J
    estimates = []

    for j in range(J):
        U = np.random.uniform(j/J, (j+1)/J, n_per_stratum)
        Z = norm.ppf(U)
        S_T = S0 * np.exp((-0.5 * sigma**2) * T + sigma * np.sqrt(T) * Z)
        stratum_mean = (S_T > K).mean()
        estimates.append(stratum_mean)

    p_stratified = np.mean(estimates)
    se_stratified = np.std(estimates) / np.sqrt(J)
    return p_stratified, se_stratified

p, se = stratified_binary_mc(S0=100, K=105, sigma=0.20, T=30/365)
print(f"Stratified estimate: {p:.6f} +/- {se:.6f}")
```

## 4. Control Variates — Exploit What You Know

Use Black-Scholes digital price (closed form) as a control variate for stochastic
volatility simulations:

p_cv = p_hat_SV - beta * (p_hat_BS_MC - p_BS_exact)

where beta = Cov(payoff_SV, payoff_BS) / Var(payoff_BS), estimated from the same paths.

## Stacking All Three

Antithetic variates inside each stratum, with a control variate correction.
Routine 100–500x variance reduction over crude MC. This is table stakes in production.
