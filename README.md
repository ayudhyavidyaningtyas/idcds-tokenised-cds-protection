# IDCDS — Tokenised Credit Default Swap Protection on Indonesian Sovereign Debt

## Overview

IDCDS is a proof-of-concept ERC-20 token that represents credit default swap (CDS) protection on Indonesian sovereign USD-denominated bonds. Each token entitles the holder to a contingent payout in the event of a qualifying credit event on the reference entity.

This project was developed as part of the **IFTE0007 Decentralised Finance and Blockchain** coursework at **UCL Institute of Finance and Technology** (2025–26).

## How It Works

1. **Protection sellers** deposit USDC collateral into the contract, backing the protection pool
2. **Protection buyers** pay an upfront premium (5% of notional) and receive IDCDS tokens (each token = $100 notional)
3. If a **credit event** is triggered (simulated by owner/oracle), token holders redeem at (1 − recovery rate) × notional
4. If the contract reaches **maturity** with no credit event, sellers reclaim their collateral plus earned premiums

## Contract Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Notional per token | $100 (USDC) | Face value of protection per token |
| Premium | 500 bps (5%) | Upfront cost paid by protection buyers |
| Recovery rate | 40% | Assumed recovery in credit event |
| Payout per token | $60 | Notional × (1 − recovery rate) |
| Maturity | 365 days | Contract tenor from deployment |
| Token standard | ERC-20 | Fungible, divisible, transferable |

## Smart Contract Architecture

```
MockUSDC.sol    — Test stablecoin (6 decimals, public mint)
IDCDS.sol       — Main protection token with lifecycle management
```

### Key Functions

| Function | Role | Description |
|----------|------|-------------|
| `depositCollateral()` | Seller | Lock USDC to back protection tokens |
| `buyProtection()` | Buyer | Pay premium, receive IDCDS tokens |
| `activate()` | Owner | End issuance, begin active period |
| `triggerCreditEvent()` | Owner (oracle proxy) | Declare credit event |
| `expire()` | Anyone | Expire contract at maturity |
| `redeem()` | Token holder | Burn tokens, receive payout |
| `reclaimCollateral()` | Seller | Reclaim collateral after expiry |

### Lifecycle Phases

```
Issuance → Active → Credit Event → Redemption
                  → Expiry → Collateral Reclaim
```

## Deployment (Sepolia Testnet)

| Contract | Address |
|----------|---------|
| MockUSDC | `0x5f4f6CeB1AfCc4a93102ce3e9124fcAFC7f98d38` |
| IDCDS | `0x2fba3BF5C7E421952396E6b296AFB062387E16eB` |

Both contracts are verified on [Etherscan (Sepolia)](https://sepolia.etherscan.io/address/0x2fba3BF5C7E421952396E6b296AFB062387E16eB).

## Demonstrated Lifecycle

The full protection lifecycle was executed on Sepolia testnet:

1. Deployed MockUSDC and IDCDS contracts
2. Approved USDC spending allowance
3. Deposited $1,000 USDC collateral (seller)
4. Purchased 5 protection tokens for $25 premium (buyer)
5. Activated the contract
6. Triggered a simulated credit event
7. Redeemed 5 tokens for $300 USDC payout (5 × $60)

## Design Simplifications

This is an academic proof-of-concept. Key simplifications include:

- **Oracle**: Credit event is triggered by the contract owner rather than a decentralised oracle (e.g. Chainlink) or DAO vote. A production implementation would use multi-source oracle verification.
- **Collateral**: Uses a mock USDC token rather than real stablecoins.
- **Premium**: Charged as a one-time upfront payment rather than periodic (quarterly) payments as in traditional CDS contracts.
- **Recovery rate**: Hardcoded at 40% rather than determined post-event via auction (as per ISDA protocols).
- **Price feeds**: No real-time bond pricing or CDS spread data is integrated. Production would use Chainlink oracles for reference pricing.

## Technology Stack

- Solidity ^0.8.20
- OpenZeppelin Contracts (ERC20, Ownable, ReentrancyGuard)
- Remix IDE
- Sepolia Testnet
- MetaMask
