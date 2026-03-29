---
name: particle-filter
description: >
  Sequential Monte Carlo (particle filters) for real-time probability updating.
  Bootstrap filter with systematic resampling, ESS monitoring, logit-space
  state evolution, and credible intervals. For live event tracking like
  election night or real-time market monitoring.
license: MIT
allowed-tools: Read Edit Grep Glob Bash
metadata:
  author: lyzr
  version: "1.0.0"
  category: quantitative-simulation
---

# Particle Filters — Real-Time Bayesian Updating

## When to Use
When probabilities need to update dynamically as new data arrives:
- Election night: early returns shift state-by-state probabilities
- Live markets: new trades, news events, poll releases
- Any scenario where static estimation is insufficient and you need filtering

## The State-Space Model

- Hidden state x_t: the "true" probability (unobserved)
- Observation y_t: market prices, poll results, vote counts

State evolves via a logit random walk (keeps probabilities in [0,1]):
  logit(x_t) = logit(x_{t-1}) + epsilon_t,  epsilon_t ~ N(0, sigma_process^2)

Observations are noisy readings:
  y_t = x_t + eta_t,  eta_t ~ N(0, sigma_obs^2)

## Bootstrap Particle Filter Algorithm

```
1. INITIALIZE: Draw x_0^(i) ~ Prior  for i = 1,...,N
   Set weights w_0^(i) = 1/N

2. FOR each new observation y_t:
   a. PROPAGATE:  x_t^(i) ~ f( . | x_{t-1}^(i) )
   b. REWEIGHT:   w_t^(i) proportional to g( y_t | x_t^(i) )
   c. NORMALIZE:  w_tilde_t^(i) = w_t^(i) / sum_j w_t^(j)
   d. RESAMPLE if ESS = 1 / sum(w_tilde^2) < N/2
```

## Full Implementation

```python
import numpy as np
from scipy.special import expit, logit  # sigmoid and logit

class PredictionMarketParticleFilter:
    """
    Sequential Monte Carlo filter for real-time event probability estimation.

    Usage during a live event (e.g., election night):
        pf = PredictionMarketParticleFilter(prior_prob=0.50)
        pf.update(observed_price=0.55)
        pf.update(observed_price=0.62)
        pf.update(observed_price=0.58)
        print(pf.estimate())
    """
    def __init__(self, N_particles=5000, prior_prob=0.5,
                 process_vol=0.05, obs_noise=0.03):
        self.N = N_particles
        self.process_vol = process_vol
        self.obs_noise = obs_noise

        logit_prior = logit(prior_prob)
        self.logit_particles = logit_prior + np.random.normal(0, 0.5, N_particles)
        self.weights = np.ones(N_particles) / N_particles
        self.history = []

    def update(self, observed_price):
        """Incorporate a new observation (market price, poll result, etc.)"""
        # 1. Propagate: random walk in logit space
        noise = np.random.normal(0, self.process_vol, self.N)
        self.logit_particles += noise

        # 2. Convert to probability space
        prob_particles = expit(self.logit_particles)

        # 3. Reweight: likelihood of observation given each particle
        log_likelihood = -0.5 * ((observed_price - prob_particles) / self.obs_noise)**2
        log_weights = np.log(self.weights + 1e-300) + log_likelihood

        # Normalize in log space for stability
        log_weights -= log_weights.max()
        self.weights = np.exp(log_weights)
        self.weights /= self.weights.sum()

        # 4. Check ESS and resample if needed
        ess = 1.0 / np.sum(self.weights**2)
        if ess < self.N / 2:
            self._systematic_resample()

        self.history.append(self.estimate())

    def _systematic_resample(self):
        """Systematic resampling — lower variance than multinomial."""
        cumsum = np.cumsum(self.weights)
        u = (np.arange(self.N) + np.random.uniform()) / self.N
        indices = np.searchsorted(cumsum, u)
        self.logit_particles = self.logit_particles[indices]
        self.weights = np.ones(self.N) / self.N

    def estimate(self):
        """Weighted mean probability estimate."""
        probs = expit(self.logit_particles)
        return np.average(probs, weights=self.weights)

    def credible_interval(self, alpha=0.05):
        """Weighted quantile-based credible interval."""
        probs = expit(self.logit_particles)
        sorted_idx = np.argsort(probs)
        sorted_probs = probs[sorted_idx]
        sorted_weights = self.weights[sorted_idx]
        cumw = np.cumsum(sorted_weights)
        lower = sorted_probs[np.searchsorted(cumw, alpha / 2)]
        upper = sorted_probs[np.searchsorted(cumw, 1 - alpha / 2)]
        return lower, upper


# --- Simulate election night ---
np.random.seed(42)
pf = PredictionMarketParticleFilter(prior_prob=0.50, process_vol=0.03)

observations = [0.50, 0.52, 0.55, 0.58, 0.61, 0.63, 0.60,
                0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95]

print("Election Night Tracker:")
print(f"{'Time':>6}  {'Observed':>10}  {'Filtered':>10}  {'95% CI':>20}")
print("-" * 52)

for t, obs in enumerate(observations):
    pf.update(obs)
    ci = pf.credible_interval()
    print(f"{t:>5}h  {obs:>10.3f}  {pf.estimate():>10.3f}  ({ci[0]:.3f}, {ci[1]:.3f})")
```

## Why Better Than Raw Market Price

The particle filter **smooths noise** and **propagates uncertainty**. When the market
spikes from $0.58 to $0.65 on a single trade, the filter recognizes the true probability
may not have changed that much — it tempers the update based on how volatile the
observation process has been.

## Tuning Parameters

| Parameter | Effect | Typical Range |
|-----------|--------|---------------|
| N_particles | More = smoother, slower | 1,000–50,000 |
| process_vol | Higher = more responsive to change | 0.01–0.10 |
| obs_noise | Higher = more smoothing of observations | 0.01–0.10 |
| ESS threshold | Lower = less resampling | N/3 to N/2 |

**Trade-off:** High process_vol + low obs_noise = trust the data. Low process_vol + high obs_noise = trust the model.
