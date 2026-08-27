// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {OrderKeeper} from "../src/OrderKeeper.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockUniswapV2Router} from "./mocks/MockUniswapV2Router.sol";

/// @title OrderKeeperTest
/// @notice Unit tests for OrderKeeper's oracle verification and order
///         lifecycle (createOrder/cancelOrder/executeOrder).
contract OrderKeeperTest is Test {
    // =============================================================
    //                           CONSTANTS
    // =============================================================

    uint8 internal constant FEED_DECIMALS = 8;
    int256 internal constant INITIAL_PRICE = 4_000e8; // $4,000, normalizes to 4_000e18
    uint256 internal constant NORMALIZED_INITIAL_PRICE = 4_000e18;
    uint8 internal constant QUOTE_TOKEN_DECIMALS = 6; // mimics USDC
    uint256 internal constant ORDER_AMOUNT = 1 ether;
    uint256 internal constant DEFAULT_SLIPPAGE_BPS = 100; // 1%
    uint256 internal constant USER_STARTING_BALANCE = 10 ether;

    // At ORDER_AMOUNT=1 ether, DEFAULT_SLIPPAGE_BPS=100, and price $4,000:
    // keeperFee = 1e18 * 50/10000 = 5e15; swapAmount = 0.995e18;
    // fairValueOut = 0.995e18 * 4000e18 * 1e6 / 1e36 = 3_980_000_000;
    // amountOutMin = fairValueOut * 9900/10000 = 3_940_200_000.
    uint256 internal constant EXPECTED_FAIR_VALUE_OUT = 3_980_000_000;
    uint256 internal constant EXPECTED_AMOUNT_OUT_MIN = 3_940_200_000;

    // =============================================================
    //                       STATE VARIABLES
    // =============================================================

    OrderKeeper internal orderKeeper;
    MockV3Aggregator internal priceFeed;
    MockERC20 internal quoteTokenMock;
    MockUniswapV2Router internal router;

    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");
    address internal user = makeAddr("user");
    address internal asset = makeAddr("asset"); // stand-in token address (e.g. WETH)

    /// @dev Lets this contract itself receive the keeper fee when a test
    ///      calls executeOrder() without vm.prank-ing a different caller.
    receive() external payable {}

    // =============================================================
    //                            SETUP
    // =============================================================

    /// @notice Sets up the test environment before each test.
    function setUp() public {
        priceFeed = new MockV3Aggregator(FEED_DECIMALS, INITIAL_PRICE);
        quoteTokenMock = new MockERC20("Mock USD", "mUSD", QUOTE_TOKEN_DECIMALS);
        router = new MockUniswapV2Router(quoteTokenMock);

        vm.prank(owner);
        orderKeeper = new OrderKeeper(owner, address(quoteTokenMock), address(router));

        vm.deal(user, USER_STARTING_BALANCE);
    }

    /// @notice Registers `asset` with the mock feed, as owner.
    function _registerAssetFeed() internal {
        vm.prank(owner);
        orderKeeper.addPriceFeed(asset, address(priceFeed));
    }

    /// @notice Builds an in-memory Order for checkPriceCondition tests that
    ///         don't go through createOrder — fields beyond
    ///         asset/condition/targetPrice are irrelevant to that check, so
    ///         they're filled with representative defaults.
    function _buildOrder(OrderKeeper.PriceCondition condition, uint256 targetPrice)
        internal
        view
        returns (OrderKeeper.Order memory order)
    {
        order = OrderKeeper.Order({
            owner: user,
            asset: asset,
            condition: condition,
            targetPrice: targetPrice,
            amount: ORDER_AMOUNT,
            maxSlippageBps: DEFAULT_SLIPPAGE_BPS,
            expiry: block.timestamp + 1 days,
            status: OrderKeeper.OrderStatus.Pending
        });
    }

    /// @notice Registers `asset`'s feed and creates a default order as `user`.
    function _createDefaultOrder() internal returns (uint256 orderId) {
        _registerAssetFeed();
        vm.prank(user);
        orderId = orderKeeper.createOrder{value: ORDER_AMOUNT}(
            asset, OrderKeeper.PriceCondition.GreaterOrEqual, 3_500e18, DEFAULT_SLIPPAGE_BPS, block.timestamp + 1 days
        );
    }

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    /// @notice Tests that the contract is initialized with the given owner,
    ///         quote token, and Uniswap router.
    function test_Constructor() public view {
        assertEq(orderKeeper.owner(), owner);
        assertEq(orderKeeper.quoteToken(), address(quoteTokenMock));
        assertEq(orderKeeper.quoteTokenDecimals(), QUOTE_TOKEN_DECIMALS);
        assertEq(address(orderKeeper.uniswapRouter()), address(router));
        assertEq(orderKeeper.weth(), router.WETH());
    }

    /// @notice Tests that construction reverts on a zero quote token address.
    function test_RevertWhen_ConstructorZeroQuoteToken() public {
        vm.expectRevert(OrderKeeper.ZeroQuoteToken.selector);
        new OrderKeeper(owner, address(0), address(router));
    }

    /// @notice Tests that construction reverts on a zero Uniswap router address.
    function test_RevertWhen_ConstructorZeroUniswapRouter() public {
        vm.expectRevert(OrderKeeper.ZeroUniswapRouter.selector);
        new OrderKeeper(owner, address(quoteTokenMock), address(0));
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
    //             CHECK PRICE CONDITION TESTS (by struct)
    // =============================================================

    /// @notice Tests a GreaterOrEqual condition that is currently met.
    function test_CheckPriceCondition_GreaterOrEqual_Met() public {
        _registerAssetFeed(); // price is $4,000
        OrderKeeper.Order memory order = _buildOrder(OrderKeeper.PriceCondition.GreaterOrEqual, 3_500e18);

        assertTrue(orderKeeper.checkPriceCondition(order));
    }

    /// @notice Tests a GreaterOrEqual condition that is currently unmet.
    function test_CheckPriceCondition_GreaterOrEqual_NotMet() public {
        _registerAssetFeed(); // price is $4,000
        OrderKeeper.Order memory order = _buildOrder(OrderKeeper.PriceCondition.GreaterOrEqual, 4_500e18);

        assertFalse(orderKeeper.checkPriceCondition(order));
    }

    /// @notice Tests that GreaterOrEqual treats an exact price match as met.
    function test_CheckPriceCondition_GreaterOrEqual_ExactMatch() public {
        _registerAssetFeed(); // price is $4,000
        OrderKeeper.Order memory order = _buildOrder(OrderKeeper.PriceCondition.GreaterOrEqual, 4_000e18);

        assertTrue(orderKeeper.checkPriceCondition(order));
    }

    /// @notice Tests a LessOrEqual condition that is currently met.
    function test_CheckPriceCondition_LessOrEqual_Met() public {
        _registerAssetFeed(); // price is $4,000
        OrderKeeper.Order memory order = _buildOrder(OrderKeeper.PriceCondition.LessOrEqual, 4_500e18);

        assertTrue(orderKeeper.checkPriceCondition(order));
    }

    /// @notice Tests a LessOrEqual condition that is currently unmet.
    function test_CheckPriceCondition_LessOrEqual_NotMet() public {
        _registerAssetFeed(); // price is $4,000
        OrderKeeper.Order memory order = _buildOrder(OrderKeeper.PriceCondition.LessOrEqual, 3_500e18);

        assertFalse(orderKeeper.checkPriceCondition(order));
    }

    /// @notice Tests that checking a condition for an unsupported asset
    ///         reverts, same as getAssetPrice.
    function test_RevertWhen_CheckPriceConditionUnsupportedAsset() public {
        OrderKeeper.Order memory order = _buildOrder(OrderKeeper.PriceCondition.GreaterOrEqual, 1);

        vm.expectRevert(abi.encodeWithSelector(OrderKeeper.UnsupportedAsset.selector, asset));
        orderKeeper.checkPriceCondition(order);
    }

    // =============================================================
    //           CHECK PRICE CONDITION TESTS (by orderId)
    // =============================================================

    /// @notice Tests that checking by orderId matches checking by struct.
    function test_CheckPriceCondition_ByOrderId_Met() public {
        uint256 orderId = _createDefaultOrder(); // condition: GreaterOrEqual 3_500e18, price is $4,000

        assertTrue(orderKeeper.checkPriceCondition(orderId));
    }

    /// @notice Tests that checking by orderId reflects an unmet condition.
    function test_CheckPriceCondition_ByOrderId_NotMet() public {
        _registerAssetFeed();
        vm.prank(user);
        uint256 orderId = orderKeeper.createOrder{value: ORDER_AMOUNT}(
            asset, OrderKeeper.PriceCondition.GreaterOrEqual, 4_500e18, DEFAULT_SLIPPAGE_BPS, block.timestamp + 1 days
        );

        assertFalse(orderKeeper.checkPriceCondition(orderId));
    }

    /// @notice Tests that checking a non-existent orderId reverts.
    function test_RevertWhen_CheckPriceConditionByOrderIdNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(OrderKeeper.OrderNotFound.selector, 0));
        orderKeeper.checkPriceCondition(uint256(0));
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

        OrderKeeper.Order memory order = _buildOrder(OrderKeeper.PriceCondition.GreaterOrEqual, targetPrice);

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

        OrderKeeper.Order memory order = _buildOrder(OrderKeeper.PriceCondition.LessOrEqual, targetPrice);

        assertEq(orderKeeper.checkPriceCondition(order), currentPrice <= targetPrice);
    }

    /// @dev Uses PRICE_DECIMALS as the mock feed's decimals so the fuzzed
    ///      currentPrice needs no normalization scaling, keeping the fuzz
    ///      assertion a direct, unscaled comparison.
    function PRICE_DECIMALS_FOR_FUZZ() internal pure returns (uint8) {
        return 18;
    }

    /// @notice Fuzz: _minAmountOut's oracle-derived scaling and the
    ///         keeper-fee formula both hold across a wide range of
    ///         realistic order amounts, oracle prices, and slippage
    ///         tolerances. Uses OrderKeeperHarness to call _minAmountOut
    ///         directly, isolating its pure math from the full order
    ///         lifecycle (oracle reads, Uniswap router, state transitions)
    ///         that going through executeOrder() would otherwise require.
    /// @dev Bounds: amount 0.0001-100 ETH (order.amount is msg.value, so
    ///      always > 0 by createOrder's own ZeroAmount check); executionPrice
    ///      $1-$1,000,000 normalized (realistic oracle range, matching this
    ///      file's other price-bound tests); maxSlippageBps 1-MAX_SLIPPAGE_BPS
    ///      (0 is untested here — 0% slippage tolerance is a degenerate,
    ///      not realistic, case already implicitly exercised by
    ///      test_ExecuteOrder_AcceptsExactAmountOutMin's boundary).
    function testFuzz_MinAmountOutAndKeeperFee(uint256 amount, uint256 executionPrice, uint256 maxSlippageBps) public {
        amount = bound(amount, 0.0001 ether, 100 ether);
        executionPrice = bound(executionPrice, 1e18, 1_000_000e18);
        maxSlippageBps = bound(maxSlippageBps, 1, orderKeeper.MAX_SLIPPAGE_BPS());

        OrderKeeperHarness harness = new OrderKeeperHarness(owner, address(quoteTokenMock), address(router));

        // --- keeperFee invariant: exact formula, no under/overflow, never
        // exceeds the order amount itself. ---
        uint256 keeperFee = (amount * harness.KEEPER_FEE_BPS()) / harness.MAX_SLIPPAGE_BPS();
        assertEq(keeperFee, (amount * 50) / 10_000);
        assertLe(keeperFee, amount);

        uint256 swapAmount = amount - keeperFee;

        // --- minAmountOut invariants ---
        uint256 minAmountOut = harness.exposed_minAmountOut(swapAmount, executionPrice, maxSlippageBps);

        // Unslippaged oracle-derived fair value, computed independently
        // here (mirrors _minAmountOut's own internal fairValueOut calc) as
        // the ceiling minAmountOut must never exceed — minAmountOut is
        // fairValueOut minus a slippage cut, so it can never be more than
        // fairValueOut itself, for any maxSlippageBps.
        uint256 fairValueOut = (swapAmount * executionPrice * (10 ** harness.quoteTokenDecimals()))
            / (10 ** (uint256(harness.PRICE_DECIMALS()) + 18));
        assertLe(minAmountOut, fairValueOut);

        // minAmountOut is never zero for a non-zero swapAmount — except at
        // exactly 100% slippage tolerance (MAX_SLIPPAGE_BPS), where a
        // caller has explicitly said they'll accept any output including
        // zero. That's correct behavior, not a bug, so it's excluded here
        // rather than asserted away.
        if (maxSlippageBps < harness.MAX_SLIPPAGE_BPS()) {
            assertGt(minAmountOut, 0);
        }
    }

    // =============================================================
    //                     CREATE ORDER TESTS
    // =============================================================

    /// @notice Tests that a valid order is created, funded, and emits
    ///         OrderCreated.
    function test_CreateOrder() public {
        _registerAssetFeed();
        uint256 expiry = block.timestamp + 1 days;

        vm.expectEmit(true, true, true, true, address(orderKeeper));
        emit OrderKeeper.OrderCreated(
            0,
            user,
            asset,
            OrderKeeper.PriceCondition.GreaterOrEqual,
            3_500e18,
            ORDER_AMOUNT,
            DEFAULT_SLIPPAGE_BPS,
            expiry
        );

        vm.prank(user);
        uint256 orderId = orderKeeper.createOrder{value: ORDER_AMOUNT}(
            asset, OrderKeeper.PriceCondition.GreaterOrEqual, 3_500e18, DEFAULT_SLIPPAGE_BPS, expiry
        );

        assertEq(orderId, 0);
        assertEq(address(orderKeeper).balance, ORDER_AMOUNT);

        (
            address orderOwner,
            address orderAsset,
            OrderKeeper.PriceCondition condition,
            uint256 targetPrice,
            uint256 amount,
            uint256 maxSlippageBps,
            uint256 orderExpiry,
            OrderKeeper.OrderStatus status
        ) = orderKeeper.orders(orderId);

        assertEq(orderOwner, user);
        assertEq(orderAsset, asset);
        assertEq(uint8(condition), uint8(OrderKeeper.PriceCondition.GreaterOrEqual));
        assertEq(targetPrice, 3_500e18);
        assertEq(amount, ORDER_AMOUNT);
        assertEq(maxSlippageBps, DEFAULT_SLIPPAGE_BPS);
        assertEq(orderExpiry, expiry);
        assertEq(uint8(status), uint8(OrderKeeper.OrderStatus.Pending));
    }

    /// @notice Tests that successive orders get incrementing ids.
    function test_CreateOrder_IncrementsOrderId() public {
        uint256 firstId = _createDefaultOrder();
        uint256 secondId = _createDefaultOrder();

        assertEq(firstId, 0);
        assertEq(secondId, 1);
        assertEq(orderKeeper.nextOrderId(), 2);
    }

    /// @notice Tests that creating an order with no ETH attached reverts.
    function test_RevertWhen_CreateOrderZeroAmount() public {
        _registerAssetFeed();

        vm.prank(user);
        vm.expectRevert(OrderKeeper.ZeroAmount.selector);
        orderKeeper.createOrder(
            asset, OrderKeeper.PriceCondition.GreaterOrEqual, 3_500e18, DEFAULT_SLIPPAGE_BPS, block.timestamp + 1 days
        );
    }

    /// @notice Tests that creating an order for an unsupported asset reverts.
    function test_RevertWhen_CreateOrderUnsupportedAsset() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OrderKeeper.UnsupportedAsset.selector, asset));
        orderKeeper.createOrder{value: ORDER_AMOUNT}(
            asset, OrderKeeper.PriceCondition.GreaterOrEqual, 3_500e18, DEFAULT_SLIPPAGE_BPS, block.timestamp + 1 days
        );
    }

    /// @notice Tests that creating an order with a non-future expiry reverts.
    function test_RevertWhen_CreateOrderInvalidExpiry() public {
        _registerAssetFeed();

        vm.prank(user);
        vm.expectRevert(OrderKeeper.InvalidExpiry.selector);
        orderKeeper.createOrder{value: ORDER_AMOUNT}(
            asset, OrderKeeper.PriceCondition.GreaterOrEqual, 3_500e18, DEFAULT_SLIPPAGE_BPS, block.timestamp
        );
    }

    /// @notice Tests that creating an order with slippage above
    ///         MAX_SLIPPAGE_BPS reverts.
    function test_RevertWhen_CreateOrderInvalidSlippage() public {
        _registerAssetFeed();
        uint256 tooMuchSlippage = orderKeeper.MAX_SLIPPAGE_BPS() + 1;

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OrderKeeper.InvalidSlippage.selector, tooMuchSlippage));
        orderKeeper.createOrder{value: ORDER_AMOUNT}(
            asset, OrderKeeper.PriceCondition.GreaterOrEqual, 3_500e18, tooMuchSlippage, block.timestamp + 1 days
        );
    }

    /// @notice Tests that sending ETH directly to the contract reverts.
    function test_RevertWhen_DirectEtherTransfer() public {
        vm.prank(user);
        vm.expectRevert(OrderKeeper.DirectEtherNotAccepted.selector);
        // vm.expectRevert intercepts and asserts the revert from the
        // low-level call itself; once matched, Foundry reports the call as
        // successful to the caller, so `success` is expected to be true here.
        (bool success,) = address(orderKeeper).call{value: 1 ether}("");
        assertTrue(success);
    }

    // =============================================================
    //                     CANCEL ORDER TESTS
    // =============================================================

    /// @notice Tests that the owner can cancel a pending order and is
    ///         refunded, and that OrderCancelled is emitted.
    function test_CancelOrder() public {
        uint256 orderId = _createDefaultOrder();
        uint256 balanceBefore = user.balance;

        vm.expectEmit(true, true, false, true, address(orderKeeper));
        emit OrderKeeper.OrderCancelled(orderId, user, ORDER_AMOUNT);

        vm.prank(user);
        orderKeeper.cancelOrder(orderId);

        assertEq(user.balance, balanceBefore + ORDER_AMOUNT);
        assertEq(address(orderKeeper).balance, 0);

        (,,,,,,, OrderKeeper.OrderStatus status) = orderKeeper.orders(orderId);
        assertEq(uint8(status), uint8(OrderKeeper.OrderStatus.Cancelled));
    }

    /// @notice Tests that cancelling a non-existent order reverts.
    function test_RevertWhen_CancelOrderNotFound() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OrderKeeper.OrderNotFound.selector, 0));
        orderKeeper.cancelOrder(0);
    }

    /// @notice Tests that only the order's owner can cancel it.
    function test_RevertWhen_CancelOrderNotOwner() public {
        uint256 orderId = _createDefaultOrder();

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(OrderKeeper.NotOrderOwner.selector, stranger, orderId));
        orderKeeper.cancelOrder(orderId);
    }

    /// @notice Tests that an already-cancelled order cannot be cancelled again.
    function test_RevertWhen_CancelOrderAlreadyCancelled() public {
        uint256 orderId = _createDefaultOrder();

        vm.prank(user);
        orderKeeper.cancelOrder(orderId);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(OrderKeeper.OrderNotPending.selector, orderId, OrderKeeper.OrderStatus.Cancelled)
        );
        orderKeeper.cancelOrder(orderId);
    }

    /// @notice Tests that a refund transfer failure (owner rejects ETH)
    ///         reverts the whole cancellation, leaving the order Pending.
    function test_RevertWhen_CancelOrderRefundFails() public {
        RevertingReceiver receiver = new RevertingReceiver();
        vm.deal(address(receiver), ORDER_AMOUNT);
        _registerAssetFeed();

        uint256 orderId = receiver.createOrderOn{value: ORDER_AMOUNT}(
            orderKeeper, asset, OrderKeeper.PriceCondition.GreaterOrEqual, 3_500e18, DEFAULT_SLIPPAGE_BPS
        );

        vm.expectRevert(OrderKeeper.RefundFailed.selector);
        receiver.cancelOrderOn(orderKeeper, orderId);

        (,,,,,,, OrderKeeper.OrderStatus status) = orderKeeper.orders(orderId);
        assertEq(uint8(status), uint8(OrderKeeper.OrderStatus.Pending));
    }

    // =============================================================
    //                     EXECUTE ORDER TESTS
    // =============================================================

    /// @notice Tests a full successful execution: keeper fee paid to the
    ///         executor, quoteToken paid to the order owner, status
    ///         Executed, and OrderExecuted emitted with real swap results.
    function test_ExecuteOrder() public {
        uint256 orderId = _createDefaultOrder(); // 1 ether, GreaterOrEqual 3_500e18, 1% slippage
        router.setAmountOut(EXPECTED_FAIR_VALUE_OUT);

        uint256 expectedFee = (ORDER_AMOUNT * orderKeeper.KEEPER_FEE_BPS()) / orderKeeper.MAX_SLIPPAGE_BPS();
        uint256 strangerBalanceBefore = stranger.balance;

        vm.expectEmit(true, true, false, true, address(orderKeeper));
        emit OrderKeeper.OrderExecuted(
            orderId, stranger, NORMALIZED_INITIAL_PRICE, expectedFee, EXPECTED_FAIR_VALUE_OUT
        );

        vm.prank(stranger);
        uint256 amountOut = orderKeeper.executeOrder(orderId);

        assertEq(amountOut, EXPECTED_FAIR_VALUE_OUT);
        assertEq(quoteTokenMock.balanceOf(user), EXPECTED_FAIR_VALUE_OUT);
        assertEq(stranger.balance, strangerBalanceBefore + expectedFee);
        assertEq(address(orderKeeper).balance, 0);

        (,,,,,,, OrderKeeper.OrderStatus status) = orderKeeper.orders(orderId);
        assertEq(uint8(status), uint8(OrderKeeper.OrderStatus.Executed));
    }

    /// @notice Tests that any address — not the contract owner, not the
    ///         order owner — may call executeOrder (permissionless by design).
    function test_ExecuteOrder_AnyoneCanCall() public {
        uint256 orderId = _createDefaultOrder();
        router.setAmountOut(EXPECTED_FAIR_VALUE_OUT);
        address randomCaller = makeAddr("randomCaller");

        vm.prank(randomCaller);
        orderKeeper.executeOrder(orderId);

        (,,,,,,, OrderKeeper.OrderStatus status) = orderKeeper.orders(orderId);
        assertEq(uint8(status), uint8(OrderKeeper.OrderStatus.Executed));
        assertGt(randomCaller.balance, 0);
    }

    /// @notice Tests that executeOrder() always swaps WETH for quoteToken,
    ///         never order.asset — asset is used solely for the oracle
    ///         lookup. Registers a price feed under an address that is
    ///         deliberately NOT the router's WETH, and confirms execution
    ///         still succeeds and the actual swap path sent to the router
    ///         is [weth, quoteToken], not [asset, quoteToken].
    function test_ExecuteOrder_SwapsWethRegardlessOfAsset() public {
        address differentAsset = makeAddr("differentAsset"); // deliberately != orderKeeper.weth()
        assertNotEq(differentAsset, orderKeeper.weth());

        vm.prank(owner);
        orderKeeper.addPriceFeed(differentAsset, address(priceFeed));

        vm.prank(user);
        uint256 orderId = orderKeeper.createOrder{value: ORDER_AMOUNT}(
            differentAsset,
            OrderKeeper.PriceCondition.GreaterOrEqual,
            3_500e18,
            DEFAULT_SLIPPAGE_BPS,
            block.timestamp + 1 days
        );
        router.setAmountOut(EXPECTED_FAIR_VALUE_OUT);

        uint256 amountOut = orderKeeper.executeOrder(orderId);

        assertEq(amountOut, EXPECTED_FAIR_VALUE_OUT);
        assertEq(quoteTokenMock.balanceOf(user), EXPECTED_FAIR_VALUE_OUT);

        address[] memory lastPath = router.getLastPath();
        assertEq(lastPath.length, 2);
        assertEq(lastPath[0], orderKeeper.weth());
        assertNotEq(lastPath[0], differentAsset);
        assertEq(lastPath[1], address(quoteTokenMock));

        (,,,,,,, OrderKeeper.OrderStatus status) = orderKeeper.orders(orderId);
        assertEq(uint8(status), uint8(OrderKeeper.OrderStatus.Executed));
    }

    /// @notice Tests that executing a non-existent order reverts.
    function test_RevertWhen_ExecuteOrderNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(OrderKeeper.OrderNotFound.selector, 0));
        orderKeeper.executeOrder(0);
    }

    /// @notice Tests that an already-executed order cannot be executed again.
    function test_RevertWhen_ExecuteOrderAlreadyExecuted() public {
        uint256 orderId = _createDefaultOrder();
        router.setAmountOut(EXPECTED_FAIR_VALUE_OUT);
        orderKeeper.executeOrder(orderId);

        vm.expectRevert(
            abi.encodeWithSelector(OrderKeeper.OrderNotPending.selector, orderId, OrderKeeper.OrderStatus.Executed)
        );
        orderKeeper.executeOrder(orderId);
    }

    /// @notice Tests that a cancelled order cannot be executed.
    function test_RevertWhen_ExecuteOrderCancelled() public {
        uint256 orderId = _createDefaultOrder();
        vm.prank(user);
        orderKeeper.cancelOrder(orderId);

        vm.expectRevert(
            abi.encodeWithSelector(OrderKeeper.OrderNotPending.selector, orderId, OrderKeeper.OrderStatus.Cancelled)
        );
        orderKeeper.executeOrder(orderId);
    }

    /// @notice Tests that executing an order past its expiry reverts.
    function test_RevertWhen_ExecuteOrderExpired() public {
        uint256 orderId = _createDefaultOrder();
        (,,,,,, uint256 expiry,) = orderKeeper.orders(orderId);

        vm.warp(expiry + 1);

        vm.expectRevert(abi.encodeWithSelector(OrderKeeper.OrderExpired.selector, orderId, expiry));
        orderKeeper.executeOrder(orderId);
    }

    /// @notice Tests that executing an order whose price condition doesn't
    ///         currently hold reverts, and leaves the order Pending.
    function test_RevertWhen_ExecuteOrderConditionNotMet() public {
        _registerAssetFeed();
        vm.prank(user);
        uint256 orderId = orderKeeper.createOrder{value: ORDER_AMOUNT}(
            asset, OrderKeeper.PriceCondition.GreaterOrEqual, 4_500e18, DEFAULT_SLIPPAGE_BPS, block.timestamp + 1 days
        ); // price is $4,000, condition requires >= $4,500

        vm.expectRevert(abi.encodeWithSelector(OrderKeeper.ConditionNotMet.selector, orderId));
        orderKeeper.executeOrder(orderId);

        (,,,,,,, OrderKeeper.OrderStatus status) = orderKeeper.orders(orderId);
        assertEq(uint8(status), uint8(OrderKeeper.OrderStatus.Pending));
    }

    /// @notice Tests that a swap output one below the computed amountOutMin
    ///         reverts the whole call, leaving the order Pending for retry —
    ///         no distinct Failed status.
    function test_RevertWhen_ExecuteOrderSlippageExceeded() public {
        uint256 orderId = _createDefaultOrder();
        router.setAmountOut(EXPECTED_AMOUNT_OUT_MIN - 1);

        vm.expectRevert(bytes("MockUniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"));
        orderKeeper.executeOrder(orderId);

        (,,,,,,, OrderKeeper.OrderStatus status) = orderKeeper.orders(orderId);
        assertEq(uint8(status), uint8(OrderKeeper.OrderStatus.Pending));
    }

    /// @notice Tests that a swap output exactly at amountOutMin is accepted
    ///         (the check is >=, not >).
    function test_ExecuteOrder_AcceptsExactAmountOutMin() public {
        uint256 orderId = _createDefaultOrder();
        router.setAmountOut(EXPECTED_AMOUNT_OUT_MIN);

        orderKeeper.executeOrder(orderId);

        (,,,,,,, OrderKeeper.OrderStatus status) = orderKeeper.orders(orderId);
        assertEq(uint8(status), uint8(OrderKeeper.OrderStatus.Executed));
    }

    /// @notice Tests that a keeper fee transfer failure (caller rejects ETH)
    ///         reverts the whole execution, leaving the order Pending.
    function test_RevertWhen_ExecuteOrderKeeperFeeTransferFails() public {
        uint256 orderId = _createDefaultOrder();
        router.setAmountOut(EXPECTED_FAIR_VALUE_OUT);

        RevertingReceiver receiver = new RevertingReceiver();

        vm.prank(address(receiver));
        vm.expectRevert(OrderKeeper.KeeperFeeTransferFailed.selector);
        orderKeeper.executeOrder(orderId);

        (,,,,,,, OrderKeeper.OrderStatus status) = orderKeeper.orders(orderId);
        assertEq(uint8(status), uint8(OrderKeeper.OrderStatus.Pending));
    }
}

/// @notice Minimal contract that owns orders on OrderKeeper's behalf and
///         rejects any ETH sent to it, to exercise cancelOrder()'s
///         RefundFailed path.
contract RevertingReceiver {
    function createOrderOn(
        OrderKeeper keeper,
        address asset,
        OrderKeeper.PriceCondition condition,
        uint256 targetPrice,
        uint256 maxSlippageBps
    ) external payable returns (uint256 orderId) {
        orderId = keeper.createOrder{value: msg.value}(
            asset, condition, targetPrice, maxSlippageBps, block.timestamp + 1 days
        );
    }

    function cancelOrderOn(OrderKeeper keeper, uint256 orderId) external {
        keeper.cancelOrder(orderId);
    }

    receive() external payable {
        revert("RevertingReceiver: no ETH accepted");
    }
}

/// @notice Test-only harness exposing OrderKeeper's internal _minAmountOut
///         for direct fuzz testing of its pure math, isolated from the
///         full order lifecycle (oracle reads, Uniswap router, state
///         transitions) that would otherwise be required to observe it.
contract OrderKeeperHarness is OrderKeeper {
    constructor(address initialOwner, address quoteToken_, address uniswapRouter_)
        OrderKeeper(initialOwner, quoteToken_, uniswapRouter_)
    {}

    /// @notice Exposes _minAmountOut for testing.
    function exposed_minAmountOut(uint256 swapAmount, uint256 executionPrice, uint256 maxSlippageBps)
        external
        view
        returns (uint256)
    {
        return _minAmountOut(swapAmount, executionPrice, maxSlippageBps);
    }
}
