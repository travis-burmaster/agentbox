---
name: copula-modeling
description: >
  Dependency modeling beyond correlation matrices. Gaussian, Student-t, Clayton,
  and Gumbel copulas for correlated prediction market outcomes. Tail dependence
  quantification and vine copulas for high-dimensional portfolios. The reason
  Gaussian copulas failed in 2008 — and what to use instead.
license: MIT
allowed-tools: Read Edit Grep Glob Bash
metadata:
  author: lyzr
  version: "1.0.0"
  category: quantitative-simulation
---

# Copula Modeling — What Correlation Matrices Can't Capture

## When to Use
When modeling joint outcomes across multiple correlated prediction markets:
- Swing state election portfolios (PA, MI, WI, GA, AZ)
- Correlated policy markets (Fed rate + inflation + employment)
- Any portfolio where extreme co-movement matters

## The Problem: Tail Dependence

**Gaussian copula:** Tail dependence lambda_U = lambda_L = 0. Extreme co-movements are
modeled as having **zero probability**. This is catastrophically wrong.

**Student-t copula:** With nu=4 and rho=0.6, tail dependence is ~0.18. An 18% probability
of extreme co-movement. Gaussian says 0%.

**Clayton copula:** Lower tail dependence only (lambda_L = 2^{-1/theta}). When one market
crashes, others follow.

**Gumbel copula:** Upper tail dependence only (lambda_U = 2 - 2^{1/theta}). Correlated
positive resolutions.

## Sklar's Theorem

F(x_1, ..., x_d) = C(F_1(x_1), ..., F_d(x_d))

where C is the copula (pure dependency structure) and F_i are the marginal CDFs. Model
each market's marginal behavior separately, then glue together with a copula.

## Full Implementation

```python
import numpy as np
from scipy.stats import norm, t as t_dist

def simulate_correlated_outcomes_gaussian(probs, corr_matrix, N=100_000):
    """Gaussian copula — no tail dependence."""
    d = len(probs)
    L = np.linalg.cholesky(corr_matrix)
    Z = np.random.standard_normal((N, d))
    X = Z @ L.T
    U = norm.cdf(X)
    outcomes = (U < np.array(probs)).astype(int)
    return outcomes

def simulate_correlated_outcomes_t(probs, corr_matrix, nu=4, N=100_000):
    """Student-t copula — symmetric tail dependence."""
    d = len(probs)
    L = np.linalg.cholesky(corr_matrix)
    Z = np.random.standard_normal((N, d))
    X = Z @ L.T

    S = np.random.chisquare(nu, N) / nu
    T = X / np.sqrt(S[:, None])
    U = t_dist.cdf(T, nu)
    outcomes = (U < np.array(probs)).astype(int)
    return outcomes

def simulate_correlated_outcomes_clayton(probs, theta=2.0, N=100_000):
    """Clayton copula — lower tail dependence (Marshall-Olkin algorithm)."""
    V = np.random.gamma(1 / theta, 1, N)
    E = np.random.exponential(1, (N, len(probs)))
    U = (1 + E / V[:, None])**(-1 / theta)
    outcomes = (U < np.array(probs)).astype(int)
    return outcomes


# --- Compare tail behavior across copulas ---
np.random.seed(42)

probs = [0.52, 0.53, 0.51, 0.48, 0.50]  # 5 swing state probabilities
state_names = ['PA', 'MI', 'WI', 'GA', 'AZ']

corr = np.array([
    [1.0, 0.7, 0.7, 0.4, 0.3],
    [0.7, 1.0, 0.8, 0.3, 0.3],
    [0.7, 0.8, 1.0, 0.3, 0.3],
    [0.4, 0.3, 0.3, 1.0, 0.5],
    [0.3, 0.3, 0.3, 0.5, 1.0],
])

N = 500_000

gauss_outcomes = simulate_correlated_outcomes_gaussian(probs, corr, N)
t_outcomes = simulate_correlated_outcomes_t(probs, corr, nu=4, N=N)

# P(sweep all 5 states)
p_sweep_gauss = gauss_outcomes.all(axis=1).mean()
p_sweep_t = t_outcomes.all(axis=1).mean()

# P(lose all 5 states)
p_lose_gauss = (1 - gauss_outcomes).all(axis=1).mean()
p_lose_t = (1 - t_outcomes).all(axis=1).mean()

# If independent
p_sweep_indep = np.prod(probs)
p_lose_indep = np.prod([1 - p for p in probs])

print("Joint Outcome Probabilities:")
print(f"{'':>25}  {'Independent':>12}  {'Gaussian':>12}  {'t-copula':>12}")
print(f"{'P(sweep all 5)':>25}  {p_sweep_indep:>12.4f}  {p_sweep_gauss:>12.4f}  {p_sweep_t:>12.4f}")
print(f"{'P(lose all 5)':>25}  {p_lose_indep:>12.4f}  {p_lose_gauss:>12.4f}  {p_lose_t:>12.4f}")
print(f"\nt-copula increases sweep probability by {p_sweep_t/p_sweep_gauss:.1f}x vs Gaussian")
```

The t-copula with nu=4 routinely shows **2–5x higher probability** of extreme joint
outcomes vs Gaussian. Trading correlated contracts without modeling tail dependence
means your portfolio will blow up in exactly the scenarios that matter most.

## Vine Copulas for d > 5

For high-dimensional portfolios, bivariate copulas are insufficient. Vine copulas
decompose d-dimensional dependency into d(d-1)/2 bivariate conditional copulas in a
tree structure:

| Type | Structure | Use Case |
|------|-----------|----------|
| C-vine (star) | One central event drives all | Presidential winner -> all policy markets |
| D-vine (path) | Sequential dependencies | Primary results -> general election |
| R-vine (general) | Maximum flexibility | Complex multi-market portfolios |

**Construction:** Build maximum spanning trees ordered by |tau_Kendall|, select
pair-copula families via AIC, estimate sequentially.

**Libraries:** pyvinecopulib (Python), VineCopula (R).

## Copula Selection Guide

| Scenario | Copula | Why |
|----------|--------|-----|
| Symmetric moderate correlation | Gaussian | Simple, fast, no tail dependence |
| Symmetric with fat tails | Student-t (nu=3-6) | Captures joint extremes |
| Crash contagion | Clayton (theta=1-5) | Lower tail dependence only |
| Joint positive resolution | Gumbel (theta=1.5-4) | Upper tail dependence only |
| Complex asymmetric | Frank + rotation | Flexible, no tail dependence |
| d > 5 contracts | Vine copula | Pair-copula decomposition |
