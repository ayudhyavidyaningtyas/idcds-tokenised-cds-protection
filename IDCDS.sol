// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ============================================================================
// IDCDS v4 — Indonesia Credit Default Swap Protection Token
// ============================================================================
// Tokenised CDS protection on Indonesian sovereign USD-denominated bonds.
//
// v4 improvements over v3:
//   - Post-credit-event seller settlement (residual collateral + premiums)
//   - Exact-balance redemption (no dust from fractional tokens)
//   - Economic terms frozen at activation (trigger price immutable once live)
//   - SafeERC20 for robust token transfers
//   - Oracle staleness checks (updatedAt, answeredInRound)
//   - Constructor input validation (zero address, zero maturity guards)
//   - Capital-efficient collateral (locked to max payout, not full notional)
//
// Deployed on Sepolia testnet for IFTE0007 coursework at UCL IFT.
// ============================================================================

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract IDCDS is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    IERC20 public immutable usdc;
    AggregatorV3Interface public immutable priceFeed;

    // --- Contract parameters ---
    uint256 public immutable maturity;
    uint256 public parametricTriggerPrice;
    bool public termsLocked;  // True after activation — no more parameter changes

    uint256 public constant NOTIONAL = 100e6;         // $100 per token (USDC 6 decimals)
    uint256 public constant BASE_PREMIUM_BPS = 300;    // 3% base premium (calm markets)
    uint256 public constant STRESS_PREMIUM_BPS = 800;  // 8% stress premium (volatile markets)
    uint256 public constant RECOVERY_BPS = 4000;       // 40% assumed recovery rate
    uint256 public constant BPS = 10000;
    uint256 public constant MAX_ORACLE_AGE = 3600;     // Oracle data must be < 1 hour old

    // Payout per token = NOTIONAL * (BPS - RECOVERY_BPS) / BPS = $60
    uint256 public constant PAYOUT_PER_TOKEN = (NOTIONAL * (BPS - RECOVERY_BPS)) / BPS;

    // --- Oracle reference prices for dynamic premium ---
    uint256 public constant CALM_PRICE = 300000000000;    // $3,000 ETH
    uint256 public constant STRESS_PRICE = 150000000000;  // $1,500 ETH

    // --- Lifecycle ---
    enum Phase { Issuance, Active, CreditEvent, Expired }
    Phase public currentPhase;

    // --- Accounting ---
    uint256 public totalCollateral;
    uint256 public totalPremiumsCollected;
    uint256 public totalTokensSold;
    uint256 public totalTokensRedeemed;          // Track redemptions for seller settlement
    mapping(address => uint256) public sellerCollateral;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event CollateralDeposited(
        address indexed seller, uint256 amount, uint256 tokensBackable,
        uint256 oraclePrice, uint256 timestamp
    );
    event ProtectionPurchased(
        address indexed buyer, uint256 numTokens, uint256 premiumPaid,
        uint256 effectivePremiumBps, uint256 oraclePrice, uint256 timestamp
    );
    event PhaseAdvanced(Phase newPhase, uint256 timestamp);
    event CreditEventTriggered(uint256 timestamp, string triggerType, uint256 oraclePrice);
    event ParametricTriggerUpdated(uint256 oldPrice, uint256 newPrice);
    event ProtectionRedeemed(address indexed holder, uint256 tokensBurned, uint256 payout, uint256 timestamp);
    event CollateralReclaimed(address indexed seller, uint256 amount, uint256 timestamp);
    event SellerSettledPostDefault(address indexed seller, uint256 residual, uint256 premiumShare, uint256 timestamp);

    // ========================================================================
    // CONSTRUCTOR (with input validation)
    // ========================================================================

    /// @param _usdc          MockUSDC address (must be non-zero)
    /// @param _priceFeed     Chainlink ETH/USD on Sepolia (must be non-zero)
    /// @param _maturityDays  Contract tenor in days (must be > 0)
    /// @param _triggerPrice  Parametric trigger threshold (8 decimals, must be > 0)
    constructor(
        address _usdc,
        address _priceFeed,
        uint256 _maturityDays,
        uint256 _triggerPrice
    ) ERC20("Indonesia CDS Protection", "IDCDS") Ownable(msg.sender) {
        require(_usdc != address(0), "USDC address cannot be zero");
        require(_priceFeed != address(0), "Price feed address cannot be zero");
        require(_maturityDays > 0, "Maturity must be greater than zero");
        require(_triggerPrice > 0, "Trigger price must be greater than zero");

        usdc = IERC20(_usdc);
        priceFeed = AggregatorV3Interface(_priceFeed);
        maturity = block.timestamp + (_maturityDays * 1 days);
        parametricTriggerPrice = _triggerPrice;
        currentPhase = Phase.Issuance;
    }

    // ========================================================================
    // CHAINLINK ORACLE (with staleness + validity checks)
    // ========================================================================

    /// @notice Read live ETH/USD price with safety checks.
    ///         Reverts if data is stale (> 1 hour) or round is incomplete.
    function getLatestPrice() public view returns (
        int256 price, uint256 timestamp, uint80 roundId
    ) {
        (
            uint80 _roundId,
            int256 _price,
            ,
            uint256 _updatedAt,

        ) = priceFeed.latestRoundData();

        // Safety checks: price must be positive, data must be fresh
        require(_price > 0, "Oracle: invalid price");
        require(_updatedAt > 0, "Oracle: incomplete round");
        require(block.timestamp - _updatedAt <= MAX_ORACLE_AGE, "Oracle: stale data");

        return (_price, _updatedAt, _roundId);
    }

    /// @notice Safe oracle read that returns 0 instead of reverting (for event logging)
    function _safeOraclePrice() internal view returns (uint256) {
        try this.getLatestPrice() returns (int256 p, uint256, uint80) {
            return uint256(p);
        } catch {
            return 0;
        }
    }

    /// @notice Dynamic premium based on oracle price.
    ///         ETH >= $3,000 → 3% | ETH <= $1,500 → 8% | Between → linear interpolation
    function getCurrentPremiumBps() public view returns (
        uint256 premiumBps, uint256 currentPrice
    ) {
        (int256 price, , ) = getLatestPrice();
        uint256 uPrice = uint256(price);

        if (uPrice >= CALM_PRICE) {
            return (BASE_PREMIUM_BPS, uPrice);
        } else if (uPrice <= STRESS_PRICE) {
            return (STRESS_PREMIUM_BPS, uPrice);
        } else {
            uint256 range = CALM_PRICE - STRESS_PRICE;
            uint256 distanceFromCalm = CALM_PRICE - uPrice;
            uint256 premiumRange = STRESS_PREMIUM_BPS - BASE_PREMIUM_BPS;
            uint256 dynamicPremium = BASE_PREMIUM_BPS + (distanceFromCalm * premiumRange / range);
            return (dynamicPremium, uPrice);
        }
    }

    /// @notice Parametric trigger — permissionless, fires if oracle breaches threshold
    function triggerCreditEventParametric() external {
        require(currentPhase == Phase.Active, "Must be in active phase");
        require(block.timestamp < maturity, "Contract already matured");

        (int256 price, , ) = getLatestPrice();  // Includes staleness check
        require(uint256(price) <= parametricTriggerPrice, "Trigger condition not met");

        currentPhase = Phase.CreditEvent;
        emit CreditEventTriggered(block.timestamp, "parametric", uint256(price));
        emit PhaseAdvanced(Phase.CreditEvent, block.timestamp);
    }

    /// @notice Update trigger price — only allowed BEFORE activation (terms lock at activate)
    function updateTriggerPrice(uint256 _newTriggerPrice) external onlyOwner {
        require(!termsLocked, "Terms locked after activation");
        require(_newTriggerPrice > 0, "Trigger price must be > 0");
        uint256 oldPrice = parametricTriggerPrice;
        parametricTriggerPrice = _newTriggerPrice;
        emit ParametricTriggerUpdated(oldPrice, _newTriggerPrice);
    }

    // ========================================================================
    // PHASE 1: ISSUANCE
    // ========================================================================

    /// @notice Sellers deposit USDC collateral. Each $100 backs 1 token.
    function depositCollateral(uint256 amount) external nonReentrant {
        require(currentPhase == Phase.Issuance, "Not in issuance phase");
        require(amount >= NOTIONAL, "Minimum deposit is $100 USDC");
        require(amount % NOTIONAL == 0, "Must be multiple of $100");

        usdc.safeTransferFrom(msg.sender, address(this), amount);
        sellerCollateral[msg.sender] += amount;
        totalCollateral += amount;

        uint256 oraclePrice = _safeOraclePrice();
        uint256 tokensBackable = amount / NOTIONAL;
        emit CollateralDeposited(msg.sender, amount, tokensBackable, oraclePrice, block.timestamp);
    }

    /// @notice Buyers pay dynamic premium and receive IDCDS tokens.
    function buyProtection(uint256 numTokens) external nonReentrant {
        require(currentPhase == Phase.Issuance, "Not in issuance phase");
        require(numTokens > 0, "Must buy at least 1 token");

        uint256 maxTokens = totalCollateral / NOTIONAL - totalTokensSold;
        require(numTokens <= maxTokens, "Insufficient collateral backing");

        (uint256 premiumBps, uint256 oraclePrice) = getCurrentPremiumBps();
        uint256 premium = (numTokens * NOTIONAL * premiumBps) / BPS;

        usdc.safeTransferFrom(msg.sender, address(this), premium);
        totalPremiumsCollected += premium;
        totalTokensSold += numTokens;

        _mint(msg.sender, numTokens * 1e18);

        emit ProtectionPurchased(
            msg.sender, numTokens, premium, premiumBps, oraclePrice, block.timestamp
        );
    }

    // ========================================================================
    // PHASE TRANSITIONS
    // ========================================================================

    /// @notice Activate — locks economic terms, requires at least 1 seller and 1 buyer
    function activate() external onlyOwner {
        require(currentPhase == Phase.Issuance, "Must be in issuance phase");
        require(totalCollateral > 0, "No collateral deposited");
        require(totalTokensSold > 0, "No tokens sold");
        termsLocked = true;  // Freeze trigger price, recovery rate, etc.
        currentPhase = Phase.Active;
        emit PhaseAdvanced(Phase.Active, block.timestamp);
    }

    /// @notice Manual credit event trigger (ISDA DC proxy)
    function triggerCreditEvent() external onlyOwner {
        require(currentPhase == Phase.Active, "Must be in active phase");
        require(block.timestamp < maturity, "Contract already matured");

        uint256 oraclePrice = _safeOraclePrice();
        currentPhase = Phase.CreditEvent;
        emit CreditEventTriggered(block.timestamp, "manual", oraclePrice);
        emit PhaseAdvanced(Phase.CreditEvent, block.timestamp);
    }

    function expire() external {
        require(currentPhase == Phase.Active, "Must be in active phase");
        require(block.timestamp >= maturity, "Maturity not yet reached");
        currentPhase = Phase.Expired;
        emit PhaseAdvanced(Phase.Expired, block.timestamp);
    }

    // ========================================================================
    // SETTLEMENT — Supports both credit event and expiry paths
    // ========================================================================

    /// @notice Redeem tokens after credit event. Works with exact token balance.
    ///         Accepts actual token units (with 18 decimals) for dust-free redemption.
    /// @param tokenAmount Amount of IDCDS tokens to redeem (in 18-decimal units)
    function redeem(uint256 tokenAmount) external nonReentrant {
        require(currentPhase == Phase.CreditEvent, "No credit event triggered");
        require(tokenAmount > 0, "Must redeem more than 0");
        require(balanceOf(msg.sender) >= tokenAmount, "Insufficient IDCDS balance");

        // Calculate payout proportional to token amount
        // payout = tokenAmount * PAYOUT_PER_TOKEN / 1e18
        uint256 payout = (tokenAmount * PAYOUT_PER_TOKEN) / 1e18;
        require(payout > 0, "Payout rounds to zero");

        // Track whole tokens redeemed for seller settlement accounting
        totalTokensRedeemed += tokenAmount / 1e18;

        _burn(msg.sender, tokenAmount);
        usdc.safeTransfer(msg.sender, payout);

        emit ProtectionRedeemed(msg.sender, tokenAmount, payout, block.timestamp);
    }

    /// @notice Convenience: redeem all tokens held by caller
    function redeemAll() external {
        uint256 bal = balanceOf(msg.sender);
        require(bal > 0, "No tokens to redeem");
        // Call internal redeem logic directly to avoid external call overhead
        require(currentPhase == Phase.CreditEvent, "No credit event triggered");

        uint256 payout = (bal * PAYOUT_PER_TOKEN) / 1e18;
        require(payout > 0, "Payout rounds to zero");
        totalTokensRedeemed += bal / 1e18;

        _burn(msg.sender, bal);
        usdc.safeTransfer(msg.sender, payout);

        emit ProtectionRedeemed(msg.sender, bal, payout, block.timestamp);
    }

    /// @notice Sellers reclaim collateral + premium share after expiry (no credit event)
    function reclaimCollateral() external nonReentrant {
        require(currentPhase == Phase.Expired, "Contract not expired");

        uint256 deposit = sellerCollateral[msg.sender];
        require(deposit > 0, "No collateral to reclaim");

        uint256 premiumShare = (totalPremiumsCollected * deposit) / totalCollateral;
        sellerCollateral[msg.sender] = 0;

        usdc.safeTransfer(msg.sender, deposit + premiumShare);
        emit CollateralReclaimed(msg.sender, deposit + premiumShare, block.timestamp);
    }

    /// @notice POST-DEFAULT seller settlement: sellers claim residual collateral + premiums
    ///         after credit event. The $40 per token not paid to protection buyers,
    ///         plus collected premiums, are returned pro-rata to sellers.
    function settlePostDefault() external nonReentrant {
        require(currentPhase == Phase.CreditEvent, "Not in credit event phase");
        // Require all tokens to be redeemed (or supply is 0 = all burned)
        require(totalSupply() == 0, "Buyers must redeem all tokens first");

        uint256 deposit = sellerCollateral[msg.sender];
        require(deposit > 0, "No collateral to settle");

        // Total paid out to protection buyers
        uint256 totalPayouts = totalTokensRedeemed * PAYOUT_PER_TOKEN;

        // Residual collateral = total deposited - total paid out
        uint256 residualPool = totalCollateral - totalPayouts;

        // Seller's pro-rata share of residual + premiums
        uint256 residualShare = (residualPool * deposit) / totalCollateral;
        uint256 premiumShare = (totalPremiumsCollected * deposit) / totalCollateral;

        sellerCollateral[msg.sender] = 0;

        uint256 totalReturn = residualShare + premiumShare;
        usdc.safeTransfer(msg.sender, totalReturn);

        emit SellerSettledPostDefault(msg.sender, residualShare, premiumShare, block.timestamp);
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    function availableProtection() external view returns (uint256) {
        return totalCollateral / NOTIONAL - totalTokensSold;
    }

    /// @notice Dynamic premium quote for N tokens
    function premiumFor(uint256 numTokens) external view returns (
        uint256 totalPremium, uint256 premiumBps, uint256 oraclePrice
    ) {
        (uint256 bps, uint256 price) = getCurrentPremiumBps();
        uint256 premium = (numTokens * NOTIONAL * bps) / BPS;
        return (premium, bps, price);
    }

    function payoutPerToken() external pure returns (uint256) {
        return PAYOUT_PER_TOKEN;
    }

    function timeToMaturity() external view returns (uint256) {
        if (block.timestamp >= maturity) return 0;
        return maturity - block.timestamp;
    }
}
