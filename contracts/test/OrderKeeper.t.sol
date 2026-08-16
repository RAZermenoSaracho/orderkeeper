// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {OrderKeeper} from "../src/OrderKeeper.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

/// @title OrderKeeperTest
/// @notice Unit tests for OrderKeeper's oracle price verification slice.
contract OrderKeeperTest is Test {
    // =============================================================
    //                           CONSTANTS
    // =============================================================

    uint8 internal constant FEED_DECIMALS = 8;
    int256 internal constant INITIAL_PRICE = 4_000e8; // $4,000, normalizes to 4_000e18

    // =============================================================
    //                       STATE VARIABLES
    // =============================================================

    OrderKeeper internal orderKeeper;
    MockV3Aggregator internal priceFeed;

    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");
    address internal asset = makeAddr("asset"); // stand-in token address (e.g. WETH)

    // =============================================================
    //                            SETUP
    // =============================================================

    /// @notice Sets up the test environment before each test.
    function setUp() public {
        priceFeed = new MockV3Aggregator(FEED_DECIMALS, INITIAL_PRICE);

        vm.prank(owner);
        orderKeeper = new OrderKeeper(owner);
    }

    /// @notice Registers `asset` with the mock feed, as owner.
    function _registerAssetFeed() internal {
        vm.prank(owner);
        orderKeeper.addPriceFeed(asset, address(priceFeed));
    }

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    /// @notice Tests that the contract is initialized with the given owner.
    function test_Constructor() public view {
        assertEq(orderKeeper.owner(), owner);
    }

    // =============================================================
    //                      ADD PRICE FEED TESTS
    // =============================================================

    /// @notice Tests that the owner can register a price feed for an asset.
    function test_AddPriceFeed() public {
        vm.expectEmit(true, true, false, false, address(orderKeeper));
        emit OrderKeeper.PriceFeedAdded(asset, address(priceFeed));

        _registerAssetFeed();

        assertEq(address(orderKeeper.priceFeeds(asset)), address(priceFeed));
    }

    /// @notice Tests that a non-owner cannot register a price feed.
    function test_RevertWhen_AddPriceFeedNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", stranger));
        orderKeeper.addPriceFeed(asset, address(priceFeed));
    }

    /// @notice Tests that registering a zero asset address reverts.
    function test_RevertWhen_AddPriceFeedZeroAsset() public {
        vm.prank(owner);
        vm.expectRevert(OrderKeeper.ZeroAsset.selector);
        orderKeeper.addPriceFeed(address(0), address(priceFeed));
    }

    /// @notice Tests that registering a zero feed address reverts.
    function test_RevertWhen_AddPriceFeedZeroFeed() public {
        vm.prank(owner);
        vm.expectRevert(OrderKeeper.ZeroPriceFeed.selector);
        orderKeeper.addPriceFeed(asset, address(0));
    }

    /// @notice Tests that re-registering an asset replaces its feed.
    function test_AddPriceFeed_Replaces() public {
        _registerAssetFeed();

        MockV3Aggregator newFeed = new MockV3Aggregator(FEED_DECIMALS, INITIAL_PRICE);
        vm.prank(owner);
        orderKeeper.addPriceFeed(asset, address(newFeed));

        assertEq(address(orderKeeper.priceFeeds(asset)), address(newFeed));
    }

    // =============================================================
    //                    GET ASSET PRICE TESTS
    // =============================================================

    /// @notice Tests that the current asset price is read and normalized.
    function test_GetAssetPrice() public {
        _registerAssetFeed();
        priceFeed.updateAnswer(2_000e8);

        uint256 price = orderKeeper.getAssetPrice(asset);

        assertEq(price, 2_000e18);
    }

    /// @notice Tests that pricing an asset with no registered feed reverts.
    function test_RevertWhen_GetAssetPriceUnsupportedAsset() public {
        vm.expectRevert(abi.encodeWithSelector(OrderKeeper.UnsupportedAsset.selector, asset));
        orderKeeper.getAssetPrice(asset);
    }

    /// @notice Tests that a non-positive oracle price is rejected.
    function test_RevertWhen_GetAssetPriceNonPositive() public {
        _registerAssetFeed();
        priceFeed.updateAnswer(0);

        vm.expectRevert(OrderKeeper.InvalidPrice.selector);
        orderKeeper.getAssetPrice(asset);
    }

    /// @notice Tests that a stale oracle price is rejected.
    function test_RevertWhen_GetAssetPriceStale() public {
        _registerAssetFeed();

        vm.warp(block.timestamp + orderKeeper.PRICE_STALENESS_THRESHOLD() + 1);

        vm.expectRevert(OrderKeeper.InvalidPrice.selector);
        orderKeeper.getAssetPrice(asset);
    }

    /// @notice Tests that a price exactly at the staleness threshold is
    ///         still accepted (rejection is strictly greater-than).
    function test_GetAssetPrice_ExactlyAtStalenessThreshold() public {
        _registerAssetFeed();

        vm.warp(block.timestamp + orderKeeper.PRICE_STALENESS_THRESHOLD());

        uint256 price = orderKeeper.getAssetPrice(asset);
        assertEq(price, 4_000e18);
    }

    /// @notice Tests decimal normalization for a feed reporting fewer than
    ///         PRICE_DECIMALS decimals (e.g. 8, as real Chainlink USD feeds do).
    function test_GetAssetPrice_NormalizesFewerDecimals() public {
        _registerAssetFeed();
        priceFeed.updateAnswer(1_234e8);

        assertEq(orderKeeper.getAssetPrice(asset), 1_234e18);
    }

    /// @notice Tests decimal normalization for a feed reporting more than
    ///         PRICE_DECIMALS decimals.
    function test_GetAssetPrice_NormalizesMoreDecimals() public {
        MockV3Aggregator wideFeed = new MockV3Aggregator(24, 5_000e24);
        vm.prank(owner);
        orderKeeper.addPriceFeed(asset, address(wideFeed));

        assertEq(orderKeeper.getAssetPrice(asset), 5_000e18);
    }

    /// @notice Tests decimal normalization for a feed already reporting
    ///         exactly PRICE_DECIMALS decimals (no scaling needed).
    function test_GetAssetPrice_NormalizesEqualDecimals() public {
        MockV3Aggregator equalFeed = new MockV3Aggregator(18, 3_000e18);
        vm.prank(owner);
        orderKeeper.addPriceFeed(asset, address(equalFeed));

        assertEq(orderKeeper.getAssetPrice(asset), 3_000e18);
    }

    // =============================================================
    //                  CHECK PRICE CONDITION TESTS
    // =============================================================

    /// @notice Tests a GreaterOrEqual condition that is currently met.
    function test_CheckPriceCondition_GreaterOrEqual_Met() public {
        _registerAssetFeed(); // price is $4,000

        OrderKeeper.Order memory order = OrderKeeper.Order({
            asset: asset, condition: OrderKeeper.PriceCondition.GreaterOrEqual, targetPrice: 3_500e18
        });

        assertTrue(orderKeeper.checkPriceCondition(order));
    }

    /// @notice Tests a GreaterOrEqual condition that is currently unmet.
    function test_CheckPriceCondition_GreaterOrEqual_NotMet() public {
        _registerAssetFeed(); // price is $4,000

        OrderKeeper.Order memory order = OrderKeeper.Order({
            asset: asset, condition: OrderKeeper.PriceCondition.GreaterOrEqual, targetPrice: 4_500e18
        });

        assertFalse(orderKeeper.checkPriceCondition(order));
    }

    /// @notice Tests that GreaterOrEqual treats an exact price match as met.
    function test_CheckPriceCondition_GreaterOrEqual_ExactMatch() public {
        _registerAssetFeed(); // price is $4,000

        OrderKeeper.Order memory order = OrderKeeper.Order({
            asset: asset, condition: OrderKeeper.PriceCondition.GreaterOrEqual, targetPrice: 4_000e18
        });

        assertTrue(orderKeeper.checkPriceCondition(order));
    }

    /// @notice Tests a LessOrEqual condition that is currently met.
    function test_CheckPriceCondition_LessOrEqual_Met() public {
        _registerAssetFeed(); // price is $4,000

        OrderKeeper.Order memory order =
            OrderKeeper.Order({asset: asset, condition: OrderKeeper.PriceCondition.LessOrEqual, targetPrice: 4_500e18});

        assertTrue(orderKeeper.checkPriceCondition(order));
    }

    /// @notice Tests a LessOrEqual condition that is currently unmet.
    function test_CheckPriceCondition_LessOrEqual_NotMet() public {
        _registerAssetFeed(); // price is $4,000

        OrderKeeper.Order memory order =
            OrderKeeper.Order({asset: asset, condition: OrderKeeper.PriceCondition.LessOrEqual, targetPrice: 3_500e18});

        assertFalse(orderKeeper.checkPriceCondition(order));
    }

    /// @notice Tests that checking a condition for an unsupported asset
    ///         reverts, same as getAssetPrice.
    function test_RevertWhen_CheckPriceConditionUnsupportedAsset() public {
        OrderKeeper.Order memory order =
            OrderKeeper.Order({asset: asset, condition: OrderKeeper.PriceCondition.GreaterOrEqual, targetPrice: 1});

        vm.expectRevert(abi.encodeWithSelector(OrderKeeper.UnsupportedAsset.selector, asset));
        orderKeeper.checkPriceCondition(order);
    }

    // =============================================================
    //                        FUZZ TESTS
    // =============================================================

    /// @notice Fuzz: GreaterOrEqual must hold iff currentPrice >= targetPrice,
    ///         across the full uint256 range.
    function testFuzz_CheckPriceCondition_GreaterOrEqual(uint256 currentPrice, uint256 targetPrice) public {
        currentPrice = bound(currentPrice, 1, uint256(type(int256).max));

        // Safe: bound() above caps currentPrice at int256.max.
        // forge-lint: disable-next-line(unsafe-typecast)
        MockV3Aggregator fuzzFeed = new MockV3Aggregator(PRICE_DECIMALS_FOR_FUZZ(), int256(currentPrice));
        vm.prank(owner);
        orderKeeper.addPriceFeed(asset, address(fuzzFeed));

        OrderKeeper.Order memory order = OrderKeeper.Order({
            asset: asset, condition: OrderKeeper.PriceCondition.GreaterOrEqual, targetPrice: targetPrice
        });

        assertEq(orderKeeper.checkPriceCondition(order), currentPrice >= targetPrice);
    }

    /// @notice Fuzz: LessOrEqual must hold iff currentPrice <= targetPrice,
    ///         across the full uint256 range.
    function testFuzz_CheckPriceCondition_LessOrEqual(uint256 currentPrice, uint256 targetPrice) public {
        currentPrice = bound(currentPrice, 1, uint256(type(int256).max));

        // Safe: bound() above caps currentPrice at int256.max.
        // forge-lint: disable-next-line(unsafe-typecast)
        MockV3Aggregator fuzzFeed = new MockV3Aggregator(PRICE_DECIMALS_FOR_FUZZ(), int256(currentPrice));
        vm.prank(owner);
        orderKeeper.addPriceFeed(asset, address(fuzzFeed));

        OrderKeeper.Order memory order = OrderKeeper.Order({
            asset: asset, condition: OrderKeeper.PriceCondition.LessOrEqual, targetPrice: targetPrice
        });

        assertEq(orderKeeper.checkPriceCondition(order), currentPrice <= targetPrice);
    }

    /// @dev Uses PRICE_DECIMALS as the mock feed's decimals so the fuzzed
    ///      currentPrice needs no normalization scaling, keeping the fuzz
    ///      assertion a direct, unscaled comparison.
    function PRICE_DECIMALS_FOR_FUZZ() internal pure returns (uint8) {
        return 18;
    }
}
