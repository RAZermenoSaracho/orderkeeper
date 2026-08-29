// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {OrderKeeper} from "../src/OrderKeeper.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockUniswapV2Router} from "./mocks/MockUniswapV2Router.sol";

/// @title OrderKeeperHandler
/// @notice Fuzzed-action handler driving OrderKeeper's full order lifecycle
///         (create/cancel/execute) in BOTH directions with bounded,
///         always-valid inputs, tracking the expected custodied balance of
///         each deposit asset separately.
/// @dev Orders are always created with a trivially-satisfied condition
///      (GreaterOrEqual, targetPrice 1) and the mock router is configured to
///      pay out generously in both directions, so executeOrder succeeds
///      whenever it's called on a valid, unexpired, Pending order — this
///      exercises the full lifecycle without needing to fuzz price movements
///      too.
///
///      Two ghost totals rather than one: Sell orders custody ETH, Buy
///      orders custody quoteToken, and conflating them would let a bug in
///      one asset's accounting be masked by the other.
contract OrderKeeperHandler is Test {
    OrderKeeper public orderKeeper;
    MockERC20 public quoteToken;

    /// @notice Running total of ETH held for orders still Pending (Sell side).
    uint256 public ghost_pendingEth;

    /// @notice Running total of quoteToken held for orders still Pending
    ///         (Buy side).
    uint256 public ghost_pendingQuote;

    address[] internal _actors;

    constructor(OrderKeeper orderKeeper_, MockERC20 quoteToken_) {
        orderKeeper = orderKeeper_;
        quoteToken = quoteToken_;
        for (uint256 i = 0; i < 5; i++) {
            _actors.push(makeAddr(string(abi.encodePacked("invariantActor", i))));
        }
    }

    /// @notice Creates a Sell order, depositing ETH.
    function createSellOrder(uint256 actorSeed, uint256 amountSeed, uint256 slippageSeed) external {
        address actor = _actors[actorSeed % _actors.length];
        uint256 amount = bound(amountSeed, 0.01 ether, 10 ether);
        uint256 slippageBps = bound(slippageSeed, 0, orderKeeper.MAX_SLIPPAGE_BPS());
        vm.deal(actor, amount);

        vm.prank(actor);
        try orderKeeper.createOrder{value: amount}(
            OrderKeeper.OrderSide.Sell,
            OrderKeeper.PriceCondition.GreaterOrEqual,
            1,
            amount,
            slippageBps,
            block.timestamp + 1 days
        ) {
            ghost_pendingEth += amount;
        } catch {}
    }

    /// @notice Creates a Buy order, depositing quoteToken (minted and
    ///         approved first, mirroring the real approve-then-create flow).
    function createBuyOrder(uint256 actorSeed, uint256 amountSeed, uint256 slippageSeed) external {
        address actor = _actors[actorSeed % _actors.length];
        uint256 amount = bound(amountSeed, 1e6, 100_000e6);
        uint256 slippageBps = bound(slippageSeed, 0, orderKeeper.MAX_SLIPPAGE_BPS());

        quoteToken.mint(actor, amount);
        vm.prank(actor);
        quoteToken.approve(address(orderKeeper), amount);

        vm.prank(actor);
        try orderKeeper.createOrder(
            OrderKeeper.OrderSide.Buy,
            OrderKeeper.PriceCondition.GreaterOrEqual,
            1,
            amount,
            slippageBps,
            block.timestamp + 1 days
        ) {
            ghost_pendingQuote += amount;
        } catch {}
    }

    function cancelOrder(uint256 orderIdSeed) external {
        if (orderKeeper.nextOrderId() == 0) return;
        uint256 orderId = orderIdSeed % orderKeeper.nextOrderId();
        (address orderOwner, OrderKeeper.OrderSide side,,, uint256 amount,,, OrderKeeper.OrderStatus status) =
            orderKeeper.orders(orderId);
        if (status != OrderKeeper.OrderStatus.Pending) return;

        vm.prank(orderOwner);
        try orderKeeper.cancelOrder(orderId) {
            _releasePending(side, amount);
        } catch {}
    }

    function executeOrder(uint256 orderIdSeed, uint256 actorSeed) external {
        if (orderKeeper.nextOrderId() == 0) return;
        uint256 orderId = orderIdSeed % orderKeeper.nextOrderId();
        (, OrderKeeper.OrderSide side,,, uint256 amount,, uint256 expiry, OrderKeeper.OrderStatus status) =
            orderKeeper.orders(orderId);
        if (status != OrderKeeper.OrderStatus.Pending) return;
        if (block.timestamp > expiry) return;

        address executor = _actors[actorSeed % _actors.length];
        vm.prank(executor);
        try orderKeeper.executeOrder(orderId) {
            _releasePending(side, amount);
        } catch {}
    }

    /// @notice Drops an order's deposit from the pending total for its side.
    /// @dev Both cancel and execute release the full deposited amount: the
    ///      keeper fee is carved out of that same amount, so nothing is left
    ///      behind in either path.
    function _releasePending(OrderKeeper.OrderSide side, uint256 amount) private {
        if (side == OrderKeeper.OrderSide.Sell) {
            ghost_pendingEth -= amount;
        } else {
            ghost_pendingQuote -= amount;
        }
    }
}

/// @title OrderKeeperInvariantTest
/// @notice Solvency invariant, now per custodied asset: OrderKeeper's ETH
///         balance must always equal the sum of active Sell order amounts,
///         and its quoteToken balance the sum of active Buy order amounts —
///         per CLAUDE.md Testing Expectations. Cancelled/Executed orders
///         leave no trace in either balance; nothing should ever get stuck
///         or double-counted across create/cancel/execute, in either
///         direction.
contract OrderKeeperInvariantTest is Test {
    OrderKeeper internal orderKeeper;
    OrderKeeperHandler internal handler;
    MockERC20 internal quoteTokenMock;

    address internal owner = makeAddr("invariantOwner");

    function setUp() public {
        MockV3Aggregator priceFeed = new MockV3Aggregator(8, 4_000e8);
        quoteTokenMock = new MockERC20("Mock USD", "mUSD", 6);
        MockUniswapV2Router router = new MockUniswapV2Router(quoteTokenMock);
        router.setAmountOut(type(uint128).max);
        router.setEthAmountOut(1 wei);

        // The mock pays Buy orders out in real ETH, so it needs a balance to
        // pay from — the real router funds this by unwrapping WETH.
        vm.deal(address(router), 1_000 ether);

        // Not pranked as owner: initialOwner is set via the constructor's
        // Ownable(initialOwner) argument, not msg.sender, so the deployer's
        // identity is irrelevant here — and forge's `new` (CREATE) doesn't
        // count as "applying" a prank the way a call does, so a prank set
        // immediately before `new` and left unconsumed until the next
        // vm.prank() below throws "cannot overwrite a prank until it is
        // applied at least once" on stricter Foundry versions.
        orderKeeper = new OrderKeeper(owner, address(quoteTokenMock), address(router));

        // Read weth() before the prank, not inside the pranked call's
        // arguments: an argument-position call consumes the prank itself,
        // leaving addPriceFeed to run unpranked and revert on Ownable.
        address wethAddress = orderKeeper.weth();

        vm.prank(owner);
        orderKeeper.addPriceFeed(wethAddress, address(priceFeed));

        handler = new OrderKeeperHandler(orderKeeper, quoteTokenMock);

        targetContract(address(handler));
    }

    /// @notice The contract's ETH balance always equals the sum of amounts
    ///         still held by Pending Sell orders.
    function invariant_EthSolvencyMatchesPendingSellOrders() public view {
        assertEq(address(orderKeeper).balance, handler.ghost_pendingEth());
    }

    /// @notice The contract's quoteToken balance always equals the sum of
    ///         amounts still held by Pending Buy orders.
    function invariant_QuoteSolvencyMatchesPendingBuyOrders() public view {
        assertEq(quoteTokenMock.balanceOf(address(orderKeeper)), handler.ghost_pendingQuote());
    }

    /// @notice The contract never accumulates swap output.
    /// @dev Both directions send their output straight to the order owner,
    ///      never via this contract. Sell output is quoteToken (already
    ///      covered above, since any Sell-side quoteToken would break that
    ///      assertion) and Buy output is ETH — so a Buy order that wrongly
    ///      routed its ETH here would show up as ETH in excess of the
    ///      pending Sell total, which invariant_EthSolvency... would catch.
    ///      Asserted explicitly anyway: it fails closer to the real cause
    ///      than a solvency mismatch would.
    function invariant_NoStrandedRouterAllowance() public view {
        assertEq(quoteTokenMock.allowance(address(orderKeeper), address(orderKeeper.uniswapRouter())), 0);
    }
}
