# IDCDS — Tokenised Credit Default Swap Protection on Indonesian Sovereign Debt

## Overview

IDCDS is an ERC-20 token representing credit default swap (CDS) protection on Indonesian sovereign USD-denominated bonds. Each token entitles the holder to a contingent payout upon a qualifying credit event on the reference entity.

Developed for **IFTE0007 Decentralised Finance and Blockchain** at **UCL Institute of Finance and Technology** (2025–26).

## Features

- **Dynamic premium pricing** — Adjusts in real-time based on Chainlink oracle data (3% in calm markets to 8% in stressed markets, linearly interpolated)
- **Dual trigger mechanism** — Manual trigger (simulating ISDA Determinations Committee) + parametric trigger (permissionless, oracle-driven)
- **Full lifecycle management** — Issuance → Active → Credit Event/Expiry → Settlement
- **Post-default seller settlement** — Sellers recover residual collateral and premiums after credit event
- **Chainlink oracle integration** — Reads live ETH/USD on Sepolia with staleness and validity checks
- **SafeERC20** — Robust token transfer handling
- **Exact-balance redemption** — Supports fractional token redemption (no dust)
- **Frozen economic terms** — Trigger price and parameters locked at activation

## How It Works

1. **Protection sellers** deposit USDC collateral into the contract
2. **Protection buyers** pay a dynamic premium (oracle-adjusted) and receive IDCDS tokens (each = $100 notional)
3. If **credit event** occurs → token holders redeem at (1 − recovery rate) × notional = $60 per token
4. After redemption → **sellers settle** and recover residual collateral ($40/token) + earned premiums
5. If **maturity** reached with no credit event → sellers reclaim full collateral + premiums

## Contract Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Notional per token | $100 (USDC) | Face value of protection per token |
| Base premium | 300 bps (3%) | Premium in calm markets (ETH > $3,000) |
| Stress premium | 800 bps (8%) | Premium in stressed markets (ETH < $1,500) |
| Recovery rate | 40% | Assumed recovery in credit event |
| Payout per token | $60 | Notional × (1 − recovery rate) |
| Oracle max age | 3,600 seconds | Staleness threshold for Chainlink data |
| Maturity | 365 days | Contract tenor from deployment |

## Dynamic Premium Logic

```
ETH >= $3,000  →  3.0% premium (calm markets)
ETH  = $2,250  →  5.5% premium (interpolated)
ETH <= $1,500  →  8.0% premium (stressed markets)
```

This mirrors real CDS markets where spreads widen during periods of market stress. At the time of testnet deployment, ETH/USD was ~$2,041, producing a dynamic premium of **6.19%** (619 bps).

## Smart Contract Architecture

```
MockUSDC.sol    — Test stablecoin (6 decimals, public mint)
IDCDS.sol       — Main protection token with oracle integration
dashboard.html  — Frontend dApp for contract interaction
```

### Key Functions

| Function | Role | Description |
|----------|------|-------------|
| `depositCollateral()` | Seller | Lock USDC to back protection tokens |
| `buyProtection()` | Buyer | Pay dynamic premium, receive IDCDS tokens |
| `activate()` | Owner | End issuance, lock terms, begin active period |
| `triggerCreditEvent()` | Owner | Manual credit event (ISDA DC proxy) |
| `triggerCreditEventParametric()` | Anyone | Auto-trigger if oracle threshold breached |
| `expire()` | Anyone | Expire contract at maturity |
| `redeemAll()` | Token holder | Burn all tokens, receive payout |
| `redeem()` | Token holder | Burn exact token amount (supports fractional) |
| `reclaimCollateral()` | Seller | Reclaim collateral + premiums after expiry |
| `settlePostDefault()` | Seller | Recover residual collateral + premiums after credit event |
| `getLatestPrice()` | Anyone | Read live Chainlink oracle price (with staleness check) |
| `getCurrentPremiumBps()` | Anyone | Get current dynamic premium rate |

### Lifecycle Phases

```
Issuance → Active → Credit Event → Redeem → Seller Settlement
                  → Expiry → Seller Reclaim
```

## Deployment (Sepolia Testnet)

| Contract | Address |
|----------|---------|
| MockUSDC | `0x5f4f6CeB1AfCc4a93102ce3e9124fcAFC7f98d38` |
| IDCDS v4 | `0xB25794122E3b3e5df3C5C5aeC3f895CeaC4d0E41` |

Verified on [Etherscan (Sepolia)](https://sepolia.etherscan.io/address/0xB25794122E3b3e5df3C5C5aeC3f895CeaC4d0E41).

## Demonstrated Lifecycle

The full lifecycle was executed on Sepolia testnet:

| Step | Transaction | Description |
|------|------------|-------------|
| 1 | Deposit Collateral | $1,000 USDC deposited (backs 10 tokens) |
| 2 | Buy Protection | 5 tokens purchased at 619 bps dynamic premium |
| 3 | Activate | Contract terms locked, active phase begins |
| 4 | Trigger Credit Event | Manual trigger (simulating ISDA DC decision) |
| 5 | Redeem All | 5 tokens burned, $300 USDC payout (5 × $60) |
| 6 | Settle Post Default | Seller recovers residual $200 + $15.48 premium |

## Frontend Dashboard

Open `dashboard.html` in any browser with MetaMask installed. Features:

- Real-time oracle price and dynamic premium display
- Premium stress indicator bar
- One-click contract interaction (deposit, buy, activate, trigger, redeem)
- Live balance tracking (IDCDS tokens, USDC, collateral)
- Transaction log

To use: update the `IDCDS_ADDRESS` constant in the HTML file with the deployed contract address.

## Design Simplifications

| Aspect | Prototype | Production |
|--------|-----------|------------|
| Oracle | Chainlink ETH/USD (proxy) | Dedicated sovereign CDS spread feed |
| Credit event | Owner trigger or parametric | ISDA DC vote via DAO + multi-oracle |
| Collateral | Mock USDC | Real USDC/USDT |
| Premium | Upfront, oracle-adjusted | Quarterly, market-driven |
| Recovery rate | Hardcoded 40% | Post-event auction (ISDA protocol) |
| Secondary market | Not implemented | Uniswap v3 IDCDS/USDC pool |

## Security Considerations (v4)

- **SafeERC20**: All token transfers use OpenZeppelin SafeERC20 to handle non-standard ERC-20 behaviour
- **Oracle staleness**: `getLatestPrice()` rejects data older than 1 hour and validates round completeness
- **Term immutability**: Economic parameters (trigger price, oracle source) locked after `activate()`
- **Input validation**: Constructor rejects zero addresses, zero maturity, and zero trigger price
- **Activation guards**: `activate()` requires at least one seller and one buyer
- **Reentrancy protection**: All state-changing functions use OpenZeppelin ReentrancyGuard
- **Post-default settlement**: Sellers can recover residual collateral after credit event, preventing fund entrapment

## Technology Stack

- Solidity ^0.8.20
- OpenZeppelin Contracts (ERC20, Ownable, ReentrancyGuard, SafeERC20)
- Chainlink Price Feeds (AggregatorV3Interface)
- ethers.js v6 (frontend)
- Remix IDE / Sepolia Testnet / MetaMask

## License

MIT
