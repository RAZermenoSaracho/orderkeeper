// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {OrderKeeper} from "../src/OrderKeeper.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title OrderKeeperForkTest
/// @notice Fork test proving getAssetPrice() correctly reads the real, live
///         Sepolia Chainlink ETH/USD feed — not a mock. This is the
///         automated, repeatable equivalent of the manual `cast call`
///         verification already done for Module 13's RWAAssetToken.
/// @dev Run with:
///        forge test --match-contract OrderKeeperForkTest --fork-url sepolia
///      (the sepolia alias in foundry.toml resolves to ${RPC_URL}). Every
///      test skips itself via vm.skip when not actually running on the
///      Sepolia fork, so plain `forge test` doesn't fail for contributors
///      without RPC_URL configured.
contract OrderKeeperForkTest is Test {
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;

    /// @dev Chainlink ETH/USD feed on Sepolia — verified live via `cast call`
    ///      for Module 13's RWAAssetToken (see that project's README), reused
    ///      here as the same already-proven address.
    address internal constant SEPOLIA_ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    /// @dev Real Uniswap V2 router deployed on Sepolia (see
    ///      deployments/sepolia.json) — verified via `cast code` (real
    ///      bytecode) and cross-checked via factory()/WETH() resolving to
    ///      live contracts. The constructor calls uniswapRouter_.WETH()
    ///      unconditionally, so this must be a real router, not a bare
    ///      placeholder address (a placeholder made this suite's setUp()
    ///      revert with "call to non-contract address" the first time this
    ///      was tried — same failure class the quoteToken comment below
    ///      already warns about).
    address internal constant SEPOLIA_UNISWAP_V2_ROUTER = 0x6e62b7a37F7d87F84F4A74116F1b5832B0171743;

    /// @dev The current DemoUSDC deployed on Sepolia (see
    ///      deployments/sepolia.json) — has actual WETH/DemoUSDC Uniswap
    ///      liquidity, unlike a freshly deployed mock token. Needed so the
    ///      real-swap tests have a real pool to trade against, in both
    ///      directions. This address must stay aligned with the current
    ///      canonical deployment record so the fork suite exercises the
    ///      same pool used by the live application.
    address internal constant SEPOLIA_QUOTE_TOKEN = 0x84811D4CBE30fA5Dd42a7421D771C3fA1cD31929;

    address internal owner = makeAddr("owner");

    /// @dev The asset every order's condition gates on. Must be the
    ///      router's real WETH now that orders trade the pair for real in
    ///      both directions — a stand-in address would make createOrder
    ///      revert with UnsupportedAsset.
    address internal asset;

    OrderKeeper internal orderKeeper;

    /// @notice Deploys OrderKeeper against the real Sepolia router and
    ///         quoteToken, and registers the real Sepolia ETH/USD feed —
    ///         skips the whole file if not running on the fork.
    function setUp() public {
        if (block.chainid != SEPOLIA_CHAIN_ID) {
            vm.skip(true);
            return;
        }

        // Not pranked as owner: initialOwner is set via the constructor's
        // Ownable(initialOwner) argument, not msg.sender, so the deployer's
        // identity is irrelevant here — and forge's `new` (CREATE) doesn't
        // count as "applying" a prank the way a call does, so a prank set
        // immediately before `new` and left unconsumed until the next
        // vm.prank() below throws "cannot overwrite a prank until it is
        // applied at least once" on stricter Foundry versions.
        orderKeeper = new OrderKeeper(owner, SEPOLIA_QUOTE_TOKEN, SEPOLIA_UNISWAP_V2_ROUTER);
        asset = orderKeeper.weth();

        vm.prank(owner);
        orderKeeper.addPriceFeed(asset, SEPOLIA_ETH_USD_FEED);
    }

    /// @notice Proves getAssetPrice() reads the real Sepolia Chainlink feed
    ///         and returns a sane, freshly-updated, PRICE_DECIMALS-normalized
    ///         ETH/USD price — not a mock, not a stale/zero value.
    function test_Fork_GetAssetPrice_ReadsLiveSepoliaFeed() public view {
        uint256 price = orderKeeper.getAssetPrice(asset);

        // Sanity bounds, not an exact match — the live price moves. $100 and
        // $1,000,000 are wide enough to catch a wrong feed address or a
        // decimal-normalization bug without being a brittle price pin.
        assertGt(price, 100e18);
        assertLt(price, 1_000_000e18);
    }

    /// @notice Cross-checks getAssetPrice()'s normalization directly against
    ///         the feed's own raw latestRoundData()/decimals(), proving the
    ///         on-chain normalization math is correct against live data, not
    ///         just internally self-consistent mock data.
    function test_Fork_GetAssetPrice_MatchesRawFeedData() public view {
        AggregatorV3Interface feed = AggregatorV3Interface(SEPOLIA_ETH_USD_FEED);
        (, int256 rawAnswer,, uint256 updatedAt,) = feed.latestRoundData();
        uint8 feedDecimals = feed.decimals();

        assertGt(rawAnswer, 0);
        assertGt(updatedAt, 0);

        // Safe: rawAnswer > 0 was just asserted above.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 expectedPrice = uint256(rawAnswer) * (10 ** (18 - feedDecimals));
        assertEq(orderKeeper.getAssetPrice(asset), expectedPrice);
    }

    /// @notice Proves the staleness check reverts even against the real
    ///         feed once enough time has passed without a new round —
    ///         staleness logic exercised against a live feed's actual
    ///         updatedAt, not a mock's synthetic one.
    function test_Fork_RevertWhen_GetAssetPriceStaleAgainstLiveFeed() public {
        vm.warp(block.timestamp + orderKeeper.PRICE_STALENESS_THRESHOLD() + 1);

        vm.expectRevert(OrderKeeper.InvalidPrice.selector);
        orderKeeper.getAssetPrice(asset);
    }

    /// @notice Proves the highest-risk path — a real swap through the real
    ///         Sepolia Uniswap V2 router — actually works: creates a real
    ///         order, executes it for real against the live WETH/DemoUSDC
    ///         pool, and confirms amountOut lands within a sane bound
    ///         derived from the same live oracle price the condition was
    ///         checked against (same style as this file's other price
    ///         sanity-bound tests — not an exact pin, since real AMM price
    ///         impact and any pool drift since deployment mean the actual
    ///         output won't exactly match a naive fair-value calc).
    /// @dev maxSlippageBps is 5%, wider than the 1% a real order would
    ///      reasonably use but far tighter than the 30% this test needed
    ///      before the 2026-08-26 redeploy. That redeploy seeded a fresh
    ///      pool at the then-current price, so the pool now tracks the
    ///      oracle to within a couple of percent instead of the ~24% gap
    ///      the old pool had drifted to. The remaining headroom covers
    ///      genuine AMM cost — the 0.3% swap fee, price impact against a
    ///      ~1 WETH pool, and whatever drift accrues between runs — not a
    ///      broken price. If this ever starts failing at 5%, check the pool
    ///      against the oracle before widening it: a growing gap is the
    ///      signal, and widening tolerance would hide it.
    function test_Fork_ExecuteOrder_RealSwap() public {
        uint256 livePrice = orderKeeper.getAssetPrice(asset);

        address orderOwner = makeAddr("forkOrderOwner");
        uint256 orderAmount = 0.001 ether;
        vm.deal(orderOwner, orderAmount);

        vm.prank(orderOwner);
        uint256 orderId = orderKeeper.createOrder{value: orderAmount}(
            OrderKeeper.OrderSide.Sell,
            OrderKeeper.PriceCondition.GreaterOrEqual,
            livePrice / 2, // comfortably below live price — condition is already true
            orderAmount,
            500, // 5% — see @dev above
            block.timestamp + 1 hours
        );

        address executor = makeAddr("forkExecutor");
        vm.prank(executor);
        uint256 amountOut = orderKeeper.executeOrder(orderId);

        uint256 keeperFee = (orderAmount * orderKeeper.KEEPER_FEE_BPS()) / orderKeeper.MAX_SLIPPAGE_BPS();
        uint256 swapAmount = orderAmount - keeperFee;
        uint256 expectedFairValue = (swapAmount * livePrice * (10 ** orderKeeper.quoteTokenDecimals()))
            / (10 ** (uint256(orderKeeper.PRICE_DECIMALS()) + 18));

        // Sane bound (half to 1.5x fair value), not an exact pin.
        assertGt(amountOut, expectedFairValue / 2);
        assertLt(amountOut, expectedFairValue + expectedFairValue / 2);

        // Fee math is deterministic regardless of swap outcome — exact,
        // not a bound. executor started at 0 ETH.
        assertEq(executor.balance, keeperFee);

        (,,,,,,, OrderKeeper.OrderStatus status) = orderKeeper.orders(orderId);
        assertEq(uint8(status), uint8(OrderKeeper.OrderStatus.Executed));
    }

    /// @notice Proves the Buy direction end-to-end against the same real
    ///         pool, traded the other way: deposits real DemoUSDC, executes
    ///         a real quoteToken -> WETH swap through the live router, and
    ///         confirms the owner receives ETH and the keeper its fee in
    ///         quoteToken.
    /// @dev The mirror of test_Fork_ExecuteOrder_RealSwap, and the reason
    ///      the mock-based unit tests aren't sufficient on their own: only
    ///      the real router actually unwraps WETH and forwards ETH to the
    ///      recipient, which is what confirms OrderKeeper's strict
    ///      receive() doesn't break Buy execution.
    function test_Fork_ExecuteBuyOrder_RealSwap() public {
        uint256 livePrice = orderKeeper.getAssetPrice(asset);

        address orderOwner = makeAddr("forkBuyOrderOwner");
        uint256 orderAmount = 5e6; // 5 DemoUSDC (6 decimals)
        deal(SEPOLIA_QUOTE_TOKEN, orderOwner, orderAmount);

        vm.prank(orderOwner);
        IERC20(SEPOLIA_QUOTE_TOKEN).approve(address(orderKeeper), orderAmount);

        vm.prank(orderOwner);
        uint256 orderId = orderKeeper.createOrder(
            OrderKeeper.OrderSide.Buy,
            OrderKeeper.PriceCondition.LessOrEqual,
            livePrice * 2, // comfortably above live price — condition is already true
            orderAmount,
            500, // 5% — same rationale as the Sell-side test above
            block.timestamp + 1 hours
        );

        address executor = makeAddr("forkBuyExecutor");
        uint256 ownerEthBefore = orderOwner.balance;
        // Captured rather than assumed zero: on a fork, `new OrderKeeper`
        // lands at a deterministic CREATE address that can already hold ETH
        // on the real chain — this one does (~0.379 ETH), which made an
        // absolute `== 0` assertion fail for reasons having nothing to do
        // with the contract. The property worth proving is that execution
        // leaves the contract's ETH unchanged, so assert the delta.
        uint256 keeperEthBefore = address(orderKeeper).balance;

        vm.prank(executor);
        uint256 amountOut = orderKeeper.executeOrder(orderId);

        uint256 keeperFee = (orderAmount * orderKeeper.KEEPER_FEE_BPS()) / orderKeeper.MAX_SLIPPAGE_BPS();
        uint256 swapAmount = orderAmount - keeperFee;
        uint256 expectedFairValue = (swapAmount * (10 ** (uint256(orderKeeper.PRICE_DECIMALS()) + 18)))
            / (livePrice * (10 ** orderKeeper.quoteTokenDecimals()));

        // Sane bound (half to 1.5x fair value), not an exact pin.
        assertGt(amountOut, expectedFairValue / 2);
        assertLt(amountOut, expectedFairValue + expectedFairValue / 2);

        // The owner really received ETH — proving the router's unwrap path
        // reached them without tripping OrderKeeper's strict receive().
        assertEq(orderOwner.balance, ownerEthBefore + amountOut);

        // Keeper fee is denominated in the deposit asset for Buy orders.
        assertEq(IERC20(SEPOLIA_QUOTE_TOKEN).balanceOf(executor), keeperFee);

        // Nothing stranded in the contract, in either asset.
        assertEq(IERC20(SEPOLIA_QUOTE_TOKEN).balanceOf(address(orderKeeper)), 0);
        assertEq(address(orderKeeper).balance, keeperEthBefore);

        (,,,,,,, OrderKeeper.OrderStatus status) = orderKeeper.orders(orderId);
        assertEq(uint8(status), uint8(OrderKeeper.OrderStatus.Executed));
    }
}
