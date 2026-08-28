// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {OrderKeeper} from "../src/OrderKeeper.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockUniswapV2Router} from "./mocks/MockUniswapV2Router.sol";

/// @title OrderKeeperHandler
/// @notice Fuzzed-action handler driving OrderKeeper's full order lifecycle
///         (create/cancel/execute) with bounded, always-valid inputs, while
///         tracking the expected sum of active (Pending) order amounts.
/// @dev Orders are always created with a trivially-satisfied condition
///      (GreaterOrEqual, targetPrice 1) and the mock router is configured to
///      always pay out generously, so executeOrder succeeds whenever it's
///      called on a valid, unexpired, Pending order — this exercises the
///      full lifecycle without needing to fuzz price movements too.
contract OrderKeeperHandler is Test {
    OrderKeeper public orderKeeper;
    address public asset;

    /// @notice Running total of amounts for orders still Pending.
    uint256 public ghost_pendingSum;

    address[] internal _actors;

    constructor(OrderKeeper orderKeeper_, address asset_) {
        orderKeeper = orderKeeper_;
        asset = asset_;
        for (uint256 i = 0; i < 5; i++) {
            _actors.push(makeAddr(string(abi.encodePacked("invariantActor", i))));
        }
    }

    function createOrder(uint256 actorSeed, uint256 amountSeed, uint256 slippageSeed) external {
        address actor = _actors[actorSeed % _actors.length];
        uint256 amount = bound(amountSeed, 0.01 ether, 10 ether);
        uint256 slippageBps = bound(slippageSeed, 0, orderKeeper.MAX_SLIPPAGE_BPS());
        vm.deal(actor, amount);

        vm.prank(actor);
        try orderKeeper.createOrder{value: amount}(
            asset, OrderKeeper.PriceCondition.GreaterOrEqual, 1, slippageBps, block.timestamp + 1 days
        ) {
            ghost_pendingSum += amount;
        } catch {}
    }

    function cancelOrder(uint256 orderIdSeed) external {
        if (orderKeeper.nextOrderId() == 0) return;
        uint256 orderId = orderIdSeed % orderKeeper.nextOrderId();
        (address orderOwner,,,, uint256 amount,,, OrderKeeper.OrderStatus status) = orderKeeper.orders(orderId);
        if (status != OrderKeeper.OrderStatus.Pending) return;

        vm.prank(orderOwner);
        try orderKeeper.cancelOrder(orderId) {
            ghost_pendingSum -= amount;
        } catch {}
    }

    function executeOrder(uint256 orderIdSeed, uint256 actorSeed) external {
        if (orderKeeper.nextOrderId() == 0) return;
        uint256 orderId = orderIdSeed % orderKeeper.nextOrderId();
        (,,,, uint256 amount,, uint256 expiry, OrderKeeper.OrderStatus status) = orderKeeper.orders(orderId);
        if (status != OrderKeeper.OrderStatus.Pending) return;
        if (block.timestamp > expiry) return;

        address executor = _actors[actorSeed % _actors.length];
        vm.prank(executor);
        try orderKeeper.executeOrder(orderId) {
            ghost_pendingSum -= amount;
        } catch {}
    }
}

/// @title OrderKeeperInvariantTest
/// @notice Solvency invariant: OrderKeeper's ETH balance must always equal
///         the sum of its currently-active (Pending) order amounts — per
///         CLAUDE.md Testing Expectations. Cancelled/Executed orders leave
///         no trace in the balance; nothing should ever get stuck or
///         double-counted across create/cancel/execute.
contract OrderKeeperInvariantTest is Test {
    OrderKeeper internal orderKeeper;
    OrderKeeperHandler internal handler;

    address internal owner = makeAddr("invariantOwner");
    address internal asset = makeAddr("invariantAsset");

    function setUp() public {
        MockV3Aggregator priceFeed = new MockV3Aggregator(8, 4_000e8);
        MockERC20 quoteTokenMock = new MockERC20("Mock USD", "mUSD", 6);
        MockUniswapV2Router router = new MockUniswapV2Router(quoteTokenMock);
        router.setAmountOut(type(uint128).max);

        // Not pranked as owner: initialOwner is set via the constructor's
        // Ownable(initialOwner) argument, not msg.sender, so the deployer's
        // identity is irrelevant here — and forge's `new` (CREATE) doesn't
        // count as "applying" a prank the way a call does, so a prank set
        // immediately before `new` and left unconsumed until the next
        // vm.prank() below throws "cannot overwrite a prank until it is
        // applied at least once" on stricter Foundry versions.
        orderKeeper = new OrderKeeper(owner, address(quoteTokenMock), address(router));

        vm.prank(owner);
        orderKeeper.addPriceFeed(asset, address(priceFeed));

        handler = new OrderKeeperHandler(orderKeeper, asset);

        targetContract(address(handler));
    }

    /// @notice The contract's ETH balance always equals the sum of amounts
    ///         still held by Pending orders.
    function invariant_SolvencyMatchesPendingOrders() public view {
        assertEq(address(orderKeeper).balance, handler.ghost_pendingSum());
    }
}
