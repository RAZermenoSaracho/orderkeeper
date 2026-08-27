// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {OrderKeeper} from "../src/OrderKeeper.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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

    /// @dev The real DemoUSDC deployed on Sepolia (see
    ///      deployments/sepolia.json) — has actual WETH/DemoUSDC Uniswap
    ///      liquidity, unlike a freshly deployed mock token. Needed so
    ///      test_Fork_ExecuteOrder_RealSwap has a real pool to swap against.
    address internal constant SEPOLIA_QUOTE_TOKEN = 0x4d43Dc9D52b9eE1FF82367943f9EbE75a2383521;

    address internal owner = makeAddr("owner");
    address internal asset = makeAddr("weth"); // our own registry key, not itself an on-chain call target

    OrderKeeper internal orderKeeper;

    /// @notice Deploys OrderKeeper against the real Sepolia router and
    ///         quoteToken, and registers the real Sepolia ETH/USD feed —
    ///         skips the whole file if not running on the fork.
    function setUp() public {
        if (block.chainid != SEPOLIA_CHAIN_ID) {
            vm.skip(true);
            return;
        }

        vm.prank(owner);
        orderKeeper = new OrderKeeper(owner, SEPOLIA_QUOTE_TOKEN, SEPOLIA_UNISWAP_V2_ROUTER);

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
    /// @dev maxSlippageBps is deliberately wide (30%), not the 1% a real
    ///      order would reasonably use. Discovered by actually running this
    ///      test: this pool was seeded in an earlier task at ETH ≈ $1,900
    ///      and hasn't been arbitraged since (no bots trade this testnet
    ///      pool), while the live oracle now reads ETH ≈ $2,500 — a ~24%
    ///      gap. At 1% tolerance the swap correctly reverts with
    ///      UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT — that's the
    ///      slippage protection working exactly as designed, rejecting a
    ///      trade against a stale-priced pool. Widening tolerance here is a
    ///      testing accommodation for that staleness, not evidence the
    ///      protection is too strict for real use.
    function test_Fork_ExecuteOrder_RealSwap() public {
        uint256 livePrice = orderKeeper.getAssetPrice(asset);

        address orderOwner = makeAddr("forkOrderOwner");
        uint256 orderAmount = 0.001 ether;
        vm.deal(orderOwner, orderAmount);

        vm.prank(orderOwner);
        uint256 orderId = orderKeeper.createOrder{value: orderAmount}(
            asset,
            OrderKeeper.PriceCondition.GreaterOrEqual,
            livePrice / 2, // comfortably below live price — condition is already true
            3_000, // 30% slippage — see @dev above: this pool is currently ~24% stale
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
}
