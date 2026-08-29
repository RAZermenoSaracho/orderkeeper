// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MockERC20} from "./MockERC20.sol";

/// @title MockUniswapV2Router
/// @notice Minimal stand-in for a Uniswap V2 router: the three functions
///         OrderKeeper calls — swapExactETHForTokens (Sell orders),
///         swapExactTokensForETH (Buy orders), and WETH().
/// @dev Both swap directions reproduce the parts of the real router's
///      behavior that OrderKeeper's accounting depends on:
///
///      - the amountOutMin check, so slippage-exceeded reverts are
///        exercised the same way the real router raises them;
///      - actually consuming the input. swapExactETHForTokens consumes
///        msg.value implicitly, and swapExactTokensForETH really does
///        transferFrom the caller's quoteToken. That pull is what makes the
///        multi-asset solvency invariant meaningful — a mock that only
///        minted output would leave OrderKeeper's quoteToken balance
///        untouched, and the invariant would pass while proving nothing.
///
///      Output amounts are configured per direction (setAmountOut for
///      quoteToken out, setEthAmountOut for wei out) since the two are
///      denominated differently. The mock must be funded with ETH (e.g.
///      vm.deal) before it can settle a Buy order.
contract MockUniswapV2Router {
    MockERC20 public immutable quoteToken;

    /// @notice quoteToken amount paid out by swapExactETHForTokens.
    uint256 public amountOut;

    /// @notice Wei amount paid out by swapExactTokensForETH.
    uint256 public ethAmountOut;

    /// @notice The address WETH() returns. Defaults to a fixed deterministic
    ///         address so existing single-arg construction keeps working;
    ///         override via setWETH() when a test needs to assert against a
    ///         specific value (e.g. that OrderKeeper's swap path uses this
    ///         address on the correct side for the order's direction).
    address public weth;

    /// @notice The path received by the most recent swap call, for tests to
    ///         assert against.
    address[] public lastPath;

    constructor(MockERC20 quoteToken_) {
        quoteToken = quoteToken_;
        weth = address(uint160(uint256(keccak256("MockUniswapV2Router.defaultWETH"))));
    }

    /// @notice Accepts ETH so tests can fund the mock for Buy-order payouts.
    receive() external payable {}

    /// @notice Sets the quoteToken amount ETH->token swaps will pay out.
    /// @param amountOut_ The quoteToken amount to mint to `to` on swap.
    function setAmountOut(uint256 amountOut_) external {
        amountOut = amountOut_;
    }

    /// @notice Sets the wei amount token->ETH swaps will pay out.
    /// @param ethAmountOut_ The wei amount to send to `to` on swap.
    function setEthAmountOut(uint256 ethAmountOut_) external {
        ethAmountOut = ethAmountOut_;
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

        _recordPath(path);

        quoteToken.mint(to, amountOut);

        amounts = new uint256[](path.length);
        amounts[0] = msg.value;
        amounts[amounts.length - 1] = amountOut;
    }

    /// @notice Mimics IUniswapV2Router02.swapExactTokensForETH: pulls
    ///         amountIn of quoteToken from the caller and sends ethAmountOut
    ///         wei to `to`, reverting if that output is below amountOutMin.
    /// @dev The transferFrom is deliberate, not incidental — see the
    ///      contract-level note on why the pull matters for solvency.
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "MockUniswapV2Router: EXPIRED");
        require(path.length >= 2, "MockUniswapV2Router: INVALID_PATH");
        require(ethAmountOut >= amountOutMin, "MockUniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");

        _recordPath(path);

        quoteToken.transferFrom(msg.sender, address(this), amountIn);

        (bool sent,) = to.call{value: ethAmountOut}("");
        require(sent, "MockUniswapV2Router: ETH_TRANSFER_FAILED");

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[amounts.length - 1] = ethAmountOut;
    }

    /// @notice Records a swap path for later assertion.
    function _recordPath(address[] calldata path) private {
        delete lastPath;
        for (uint256 i = 0; i < path.length; i++) {
            lastPath.push(path[i]);
        }
    }
}
