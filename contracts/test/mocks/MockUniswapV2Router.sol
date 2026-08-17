// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MockERC20} from "./MockERC20.sol";

/// @title MockUniswapV2Router
/// @notice Minimal stand-in for a Uniswap V2 router, implementing only
///         swapExactETHForTokens — the one function OrderKeeper calls.
///         Output amount is test-configurable via setAmountOut, and the
///         function reverts the same way the real router does when the
///         configured output is below the caller's amountOutMin.
contract MockUniswapV2Router {
    MockERC20 public immutable quoteToken;

    /// @notice The output amount this mock will pay out on the next swap.
    uint256 public amountOut;

    constructor(MockERC20 quoteToken_) {
        quoteToken = quoteToken_;
    }

    /// @notice Sets the output amount future swaps will pay out.
    /// @param amountOut_ The quoteToken amount to mint to `to` on swap.
    function setAmountOut(uint256 amountOut_) external {
        amountOut = amountOut_;
    }

    /// @notice Mimics IUniswapV2Router02.swapExactETHForTokens: mints
    ///         amountOut of quoteToken to `to`, reverting if it's below
    ///         amountOutMin — same as the real router's slippage check.
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts)
    {
        require(deadline >= block.timestamp, "MockUniswapV2Router: EXPIRED");
        require(path.length >= 2, "MockUniswapV2Router: INVALID_PATH");
        require(amountOut >= amountOutMin, "MockUniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");

        quoteToken.mint(to, amountOut);

        amounts = new uint256[](path.length);
        amounts[0] = msg.value;
        amounts[amounts.length - 1] = amountOut;
    }
}
