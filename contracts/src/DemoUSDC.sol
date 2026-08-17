// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title DemoUSDC
/// @author Ricardo
/// @notice Testnet-only mintable stand-in for a USD stablecoin, used as
///         OrderKeeper's quoteToken on Sepolia.
/// @dev Exists solely because no real WETH/stablecoin Uniswap V2 pair is
///      available on Sepolia's deployed router yet (verified via getPair()
///      returning address(0) for both Circle's official USDC and a
///      third-party test USDC). Not audited, not production code — mint()
///      is intentionally unrestricted, matching a testnet faucet token, not
///      a real asset. Never deploy this to mainnet.
contract DemoUSDC is ERC20 {
    constructor() ERC20("Demo USD", "mUSDC") {}

    /// @notice Returns 6 decimals, matching real USDC.
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mints `amount` tokens to `to`. Unrestricted — testnet only.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
