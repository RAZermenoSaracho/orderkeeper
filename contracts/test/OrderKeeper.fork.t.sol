// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {OrderKeeper} from "../src/OrderKeeper.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

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

    address internal owner = makeAddr("owner");
    // Placeholder — never called by getAssetPrice(), only queried at
    // construction (decimals()) and by executeOrder(), neither of which
    // this fork test exercises. Unlike quoteToken, it needs no real code.
    address internal uniswapRouter = makeAddr("uniswapRouter");
    address internal asset = makeAddr("weth"); // our own registry key, not itself an on-chain call target

    OrderKeeper internal orderKeeper;

    /// @notice Deploys OrderKeeper and registers the real Sepolia ETH/USD
    ///         feed — skips the whole file if not running on the fork.
    function setUp() public {
        if (block.chainid != SEPOLIA_CHAIN_ID) {
            vm.skip(true);
            return;
        }

        // A real deployed contract, not a bare address — the constructor
        // calls quoteToken_.decimals(), which only a placeholder address
        // (no code on the actual fork) can't satisfy.
        MockERC20 quoteToken = new MockERC20("Mock USD", "mUSD", 6);

        vm.prank(owner);
        orderKeeper = new OrderKeeper(owner, address(quoteToken), uniswapRouter);

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
}
