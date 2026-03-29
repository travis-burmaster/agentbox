# Key Formulas

## Monte Carlo Estimator
p_hat_N = (1/N) * sum(1_{A}(X_i))
Var(p_hat_N) = p(1-p) / N
Convergence: O(N^{-1/2})
Max variance at p = 0.5

## Sample Size for Precision
N = z_{alpha/2}^2 * p(1-p) / epsilon^2
For +/-0.01 at 95% with p=0.5: N = 9,604

## Geometric Brownian Motion
S_T = S_0 * exp((mu - 0.5*sigma^2)*T + sigma*sqrt(T)*Z)
Z ~ N(0,1)

## Importance Sampling
E_P[h(X)] = E_Q[h(X) * dP/dQ(X)]
Exponential tilting: Q(dx) = exp(gamma*x - log M(gamma)) * P(dx)
Optimal gamma: solve M(gamma) = 1

## Brier Score
BS = (1/N) * sum((p_i - o_i)^2)
Range: [0, 1], lower is better
Good: < 0.20, Excellent: < 0.10

## Particle Filter (Bootstrap)
Propagate: x_t^(i) ~ f(.|x_{t-1}^(i))
Reweight: w_t^(i) proportional to g(y_t | x_t^(i))
ESS = 1 / sum(w_tilde^2), resample if ESS < N/2

## Logit Random Walk (for bounded probabilities)
logit(x_t) = logit(x_{t-1}) + epsilon_t
epsilon_t ~ N(0, sigma_process^2)

## Kyle Lambda (Price Impact)
lambda = sigma_v / (2 * sigma_u)
sigma_v: fundamental value uncertainty
sigma_u: noise trading intensity

## Copula (Sklar's Theorem)
F(x_1,...,x_d) = C(F_1(x_1),...,F_d(x_d))

## Tail Dependence Coefficients
Gaussian: lambda_U = lambda_L = 0
Student-t(nu, rho): lambda_U = lambda_L > 0
Clayton(theta): lambda_L = 2^{-1/theta}, lambda_U = 0
Gumbel(theta): lambda_U = 2 - 2^{1/theta}, lambda_L = 0
