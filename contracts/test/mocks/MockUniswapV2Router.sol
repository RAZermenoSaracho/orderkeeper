// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MockERC20} from "./MockERC20.sol";

/// @title MockUniswapV2Router
/// @notice Minimal stand-in for a Uniswap V2 router: swapExactETHForTokens
///         and WETH(), the two functions OrderKeeper calls. Output amount
///         is test-configurable via setAmountOut, and the swap function
///         reverts the same way the real router does when the configured
///         output is below the caller's amountOutMin. The path received by
///         the last swap is recorded (lastPath/getLastPath) so tests can
///         assert what OrderKeeper actually passed as path[0]/path[1].
contract MockUniswapV2Router {
    MockERC20 public immutable quoteToken;

    /// @notice The output amount this mock will pay out on the next swap.
    uint256 public amountOut;

    /// @notice The address WETH() returns. Defaults to a fixed deterministic
    ///         address so existing single-arg construction keeps working;
    ///         override via setWETH() when a test needs to assert against a
    ///         specific value (e.g. that OrderKeeper's swap path uses this
    ///         address, not an order's `asset`).
    address public weth;

    /// @notice The path received by the most recent swapExactETHForTokens
    ///         call, for tests to assert against.
    address[] public lastPath;

    constructor(MockERC20 quoteToken_) {
        quoteToken = quoteToken_;
        weth = address(uint160(uint256(keccak256("MockUniswapV2Router.defaultWETH"))));
    }

    /// @notice Sets the output amount future swaps will pay out.
    /// @param amountOut_ The quoteToken amount to mint to `to` on swap.
    function setAmountOut(uint256 amountOut_) external {
        amountOut = amountOut_;
    }

    /// @notice Overrides the address WETH() returns.
    /// @param weth_ The address to return from WETH().
    function setWETH(address weth_) external {
        weth = weth_;
    }

    /// @notice Mimics IUniswapV2Router02.WETH().
    function WETH() external view returns (address) {
        return weth;
    }

    /// @notice Returns the full path received by the most recent swap call.
    function getLastPath() external view returns (address[] memory) {
        return lastPath;
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

        delete lastPath;
        for (uint256 i = 0; i < path.length; i++) {
            lastPath.push(path[i]);
        }

        quoteToken.mint(to, amountOut);

        amounts = new uint256[](path.length);
        amounts[0] = msg.value;
        amounts[amounts.length - 1] = amountOut;
    }
}
