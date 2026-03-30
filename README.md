# IDCDS — Tokenised Credit Default Swap Protection on Indonesian Sovereign Debt

## Overview

IDCDS is an ERC-20 token representing credit default swap (CDS) protection on Indonesian sovereign USD-denominated bonds. Each token entitles the holder to a contingent payout upon a qualifying credit event on the reference entity.

Developed for **IFTE0007 Decentralised Finance and Blockchain** at **UCL Institute of Finance and Technology** (2025–26).

**Live Dashboard:** [ayudhyavidyaningtyas.github.io/idcds-tokenised-cds-protection](https://ayudhyavidyaningtyas.github.io/idcds-tokenised-cds-protection/)

## Features

- **Dynamic premium pricing** — Adjusts in real time based on Chainlink oracle data (3% calm to 8% stressed, linearly interpolated)
- **Dual trigger mechanism** — Manual trigger (ISDA DC proxy) plus parametric trigger (permissionless, oracle-driven)
- **Full lifecycle management** — Issuance -> Active -> Credit Event/Expiry -> Settlement
- **Post-default seller settlement** — Sellers recover seller-owned surplus collateral and premiums after credit event
- **Chainlink oracle integration** — Live ETH/USD on Sepolia with staleness and round-validity checks
- **SafeERC20** — Robust token transfer handling via OpenZeppelin
- **Fractional redemption support** — Supports fractional token redemption where payout is large enough to round to non-zero USDC
- **Frozen economic terms** — Trigger price and parameters locked at activation
- **Analytics dashboard** — Real Indonesia 5Y CDS spreads (LSEG) vs. on-chain premium model (CoinGecko), visualising oracle mismatch

## How It Works

1. **Protection sellers** deposit USDC collateral into the contract
2. **Protection buyers** pay a dynamic premium (oracle-adjusted) and receive IDCDS tokens (each = $100 notional)
3. If a **credit event** occurs, token holders redeem at `(1 - recovery rate) x notional = $60` per token
4. After a credit event, **sellers settle** and recover the seller-owned surplus plus earned premiums
5. If **maturity** is reached with no credit event, sellers reclaim full collateral plus premiums

## Contract Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Notional per token | $100 (USDC) | Face value of protection per token |
| Base premium | 300 bps (3%) | Premium in calm markets (ETH > $3,000) |
| Stress premium | 800 bps (8%) | Premium in stressed markets (ETH < $1,500) |
| Recovery rate | 40% | Assumed recovery in credit event |
| Payout per token | $60 | Notional x (1 - recovery rate) |
| Oracle max age | 3,600 seconds | Staleness threshold for Chainlink data |
| Maturity | 365 days | Contract tenor from deployment |
| Collateral model | $100 per token | Conservative overcollateralised backing |

## Dynamic Premium Logic

```text
ETH >= $3,000  ->  3.0% premium (calm markets)
ETH  = $2,250  ->  5.5% premium (interpolated)
ETH <= $1,500  ->  8.0% premium (stressed markets)
```

At testnet deployment on **30 March 2026**, ETH/USD was approximately **$2,041**, producing a dynamic premium of **6.19%** (619 bps).

## Deployment (Sepolia Testnet)

| Contract | Address |
|----------|---------|
| MockUSDC | [`0x6D063BDc716F021d1ed8F1EBbB238A83AcBea132`](https://sepolia.etherscan.io/address/0x6D063BDc716F021d1ed8F1EBbB238A83AcBea132) |
| IDCDS v4 | [`0xa9d554A7c09Ab58Ead68A8F59F123F20Bb55622b`](https://sepolia.etherscan.io/address/0xa9d554A7c09Ab58Ead68A8F59F123F20Bb55622b) |

## Demonstrated Lifecycle

| Step | Method | Description |
|------|--------|-------------|
| 1 | `depositCollateral` | $1,000 USDC deposited (backs 10 tokens) |
| 2 | `buyProtection` | 5 tokens purchased at 619 bps dynamic premium |
| 3 | `activate` | Contract terms locked, active phase begins |
| 4 | `triggerCreditEvent` | Manual trigger (simulating ISDA DC decision) |
| 5 | `redeemAll` | 5 tokens burned, $300 USDC payout (5 x $60) |
| 6 | `settlePostDefault` | Seller recovers residual collateral plus premiums |

## Smart Contract Architecture

```text
MockUSDC.sol  - Test stablecoin (6 decimals, public mint)
IDCDS.sol     - Main protection token with oracle integration
index.html    - Frontend dApp with analytics dashboard
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
| `redeem()` | Token holder | Burn a chosen token amount, receive payout |
| `redeemAll()` | Token holder | Burn all tokens, receive payout |
| `reclaimCollateral()` | Seller | Reclaim collateral plus premiums after expiry |
| `settlePostDefault()` | Seller | Recover seller-owned surplus plus premiums after credit event |
| `getLatestPrice()` | Anyone | Read live Chainlink oracle price (with freshness and round checks) |
| `getCurrentPremiumBps()` | Anyone | Get current dynamic premium rate |

## Frontend Dashboard

The live dashboard provides:

- **Analytics chart** — Real Indonesia 5Y CDS spreads (LSEG Workspace, `IDGV5YUSAC=R`) plotted against the on-chain dynamic premium model (CoinGecko ETH/USD API)
- **Real-time oracle data** — Live Chainlink ETH/USD price and computed premium
- **Premium stress indicator** — Gradient bar showing current market regime
- **Contract interaction** — Deposit, buy, activate, trigger, redeem, settle
- **Balance tracking** — IDCDS tokens, USDC, collateral positions
- **Activity log** — Transaction history with status

## Security Features (v4)

| Feature | Implementation |
|---------|---------------|
| SafeERC20 | All transfers use OpenZeppelin `safeTransferFrom` / `safeTransfer` |
| Oracle staleness | `getLatestPrice()` rejects data older than 1 hour |
| Oracle round validity | `getLatestPrice()` checks `answeredInRound >= roundId` |
| Term immutability | Parameters locked after `activate()` |
| Input validation | Constructor rejects zero addresses, zero maturity, zero trigger |
| Activation guards | Requires at least one seller and one buyer |
| Reentrancy protection | State-changing settlement and transfer paths use `ReentrancyGuard` |
| Post-default settlement | Prevents buyer-redemption deadlock after credit events |

## Design Simplifications

| Aspect | Prototype | Production |
|--------|-----------|------------|
| Oracle | Chainlink ETH/USD (proxy) | Dedicated sovereign CDS spread feed |
| Credit event | Owner trigger or parametric | ISDA DC vote via DAO plus multi-oracle |
| Collateral | Mock USDC | Real USDC/USDT |
| Premium | Upfront, oracle-adjusted | Quarterly, market-driven |
| Recovery rate | Hardcoded 40% | Post-event auction (ISDA protocol) |
| Secondary market | Not implemented | Uniswap v3 IDCDS/USDC pool |

## Technology Stack

- Solidity ^0.8.20
- OpenZeppelin Contracts (ERC20, Ownable, ReentrancyGuard, SafeERC20)
- Chainlink Price Feeds (`AggregatorV3Interface`)
- Chart.js (analytics visualisation)
- ethers.js v6 (frontend wallet integration)
- CoinGecko API (live ETH/USD historical data)
- LSEG Workspace (Indonesia 5Y CDS reference data)
- Remix IDE / Sepolia Testnet / MetaMask

## Notes

- The current implementation uses conservative `$100` collateral per `$100` protection token, even though the maximum payout is `$60`.
- Fractional token redemption is supported when the calculated USDC payout is non-zero after integer rounding.
- Smart contracts already deployed on-chain are immutable, so code updates require redeployment to a new contract address.

## License

MIT
