// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ============================================================================
// MockUSDC — Fake USDC for Sepolia testnet testing
// ============================================================================
// Deploy this FIRST, then pass its address to the IDCDS constructor.
// ============================================================================

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {

    constructor() ERC20("Mock USDC", "MUSDC") {
        // Mint 1,000,000 MUSDC to deployer for testing
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    /// @notice USDC uses 6 decimals, not the default 18
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Public mint — anyone can get test tokens
    /// @param to      Address to receive tokens
    /// @param amount   Amount in USDC units (6 decimals)
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
