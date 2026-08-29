// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/// @title OrderKeeper
/// @author Ricardo
/// @notice Trustless bidirectional limit-order keeper for a single trading
///         pair (ETH/WETH against quoteToken): custodies order funds and
///         verifies price conditions on-chain against Chainlink before
///         execution.
/// @dev Supports both directions of one fixed pair:
///
///      - Sell orders deposit native ETH and swap WETH -> quoteToken once
///        ETH's price satisfies the condition (typically GreaterOrEqual —
///        "sell when ETH rises to my target").
///      - Buy orders deposit quoteToken and swap quoteToken -> WETH once
///        ETH's price satisfies the condition (typically LessOrEqual —
///        "buy when ETH falls to my target").
///
///      Both sides gate on the same value: ETH's USD price, read via
///      getAssetPrice(weth). There is no per-order asset selector — an
///      earlier revision carried one, but it only ever chose which feed
///      the condition read, never what was actually traded, so it was
///      removed in favour of honestly supporting one real pair in both
///      directions.
///
///      Price verification pattern (staleness check + decimal normalization)
///      is reused from Module 13's RWAAssetToken.sol, which proved it against
///      a live Sepolia Chainlink feed.
///
///      executeOrder() re-verifies the price condition on-chain — never
///      trusting a caller-supplied value — before swapping via Uniswap V2
///      and paying the caller a keeper fee. It is intentionally
///      permissionless: WHO calls it is not the security boundary, WHAT it
///      independently checks before moving funds is.
///
///      Fee-on-transfer and rebasing tokens are NOT supported as
///      quoteToken: custody accounting assumes the amount received equals
///      the amount transferred.
contract OrderKeeper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =============================================================
    //                        TYPES
    // =============================================================

    /// @notice Direction of an order's price condition.
    enum PriceCondition {
        GreaterOrEqual,
        LessOrEqual
    }

    /// @notice Which way an order trades the pair.
    /// @dev Sell deposits ETH and receives quoteToken; Buy deposits
    ///      quoteToken and receives ETH. Determines the deposit asset, the
    ///      refund asset, the keeper fee's denomination, and the swap path
    ///      direction — but never which price the condition reads, which is
    ///      always ETH's.
    enum OrderSide {
        Sell,
        Buy
    }

    /// @notice Lifecycle state of an order.
    enum OrderStatus {
        Pending,
        Executed,
        Cancelled
    }

    /// @notice A limit order on the ETH/quoteToken pair, in either direction.
    /// @param owner The address that created and funded the order, and the
    ///        only address allowed to cancel it.
    /// @param side Sell (deposit ETH, receive quoteToken) or Buy (deposit
    ///        quoteToken, receive ETH).
    /// @param condition Whether execution requires ETH's price >= or <=
    ///        targetPrice.
    /// @param targetPrice The condition's threshold price, normalized to
    ///        PRICE_DECIMALS.
    /// @param amount The deposited amount, refunded on cancel or swapped on
    ///        execution. Denominated in wei for Sell orders, in quoteToken
    ///        base units for Buy orders.
    /// @param maxSlippageBps Maximum acceptable slippage for the eventual
    ///        swap, in basis points (e.g. 100 = 1%).
    /// @param expiry Unix timestamp after which the order can no longer be
    ///        executed.
    /// @param status The order's current lifecycle state.
    struct Order {
        address owner;
        OrderSide side;
        PriceCondition condition;
        uint256 targetPrice;
        uint256 amount;
        uint256 maxSlippageBps;
        uint256 expiry;
        OrderStatus status;
    }

    // =============================================================
    //                        STATE VARIABLES
    // =============================================================

    /// @notice Number of decimals every price is normalized to, regardless
    ///         of how many decimals the underlying Chainlink feed reports.
    uint8 public constant PRICE_DECIMALS = 18;

    /// @notice Maximum age of a Chainlink round before its price is rejected
    ///         as stale.
    uint256 public constant PRICE_STALENESS_THRESHOLD = 1 hours;

    /// @notice Denominator for maxSlippageBps and KEEPER_FEE_BPS —
    ///         10_000 basis points = 100%.
    uint256 public constant MAX_SLIPPAGE_BPS = 10_000;

    /// @notice Keeper fee taken from an order's deposited amount on
    ///         execution, in basis points of MAX_SLIPPAGE_BPS (50 = 0.5%).
    ///         Paid to whoever calls executeOrder().
    /// @dev Denominated in whatever the order deposited — ETH for Sell
    ///      orders, quoteToken for Buy orders — so the fee never requires
    ///      its own swap.
    uint256 public constant KEEPER_FEE_BPS = 50;

    /// @notice Chainlink price feed registered per asset, owner-managed.
    /// @dev In practice only weth's feed is required, since every order's
    ///      condition reads ETH's price. Kept as a mapping (rather than a
    ///      single immutable feed) so the feed can be re-pointed after
    ///      deployment without redeploying — the same owner-controlled,
    ///      never-caller-supplied trust model as before.
    mapping(address asset => AggregatorV3Interface feed) public priceFeeds;

    /// @notice The ERC20 side of the pair: what Sell orders receive and what
    ///         Buy orders deposit.
    /// @dev Execution math assumes quoteToken is USD-pegged (1 quoteToken
    ///      == $1) — true for the stablecoin this contract is deployed with.
    address public immutable quoteToken;

    /// @notice quoteToken's decimals(), cached at construction so
    ///         executeOrder() doesn't re-query it on every execution.
    uint8 public immutable quoteTokenDecimals;

    /// @notice The Uniswap V2 router used to swap on execution.
    IUniswapV2Router02 public immutable uniswapRouter;

    /// @notice The router's WETH address — the non-quoteToken side of every
    ///         swap, and the asset whose Chainlink price gates every order.
    /// @dev Queried from uniswapRouter at construction rather than passed
    ///      separately, so it can never drift from what the router itself
    ///      requires as path[0] (Sell) or path[1] (Buy).
    address public immutable weth;

    /// @notice The id that will be assigned to the next created order.
    uint256 public nextOrderId;

    /// @notice All orders by id.
    mapping(uint256 orderId => Order order) public orders;

    // =============================================================
    //                           EVENTS
    // =============================================================

    /// @notice Emitted when the owner registers or replaces an asset's feed.
    /// @param asset The token the feed prices.
    /// @param feed The Chainlink AggregatorV3Interface address for asset.
    event PriceFeedAdded(address indexed asset, address indexed feed);

    /// @notice Emitted when a new order is created and funded.
    /// @param orderId The id of the newly created order.
    /// @param owner The address that created and funded the order.
    /// @param side Sell (deposited ETH) or Buy (deposited quoteToken).
    /// @param condition Whether execution requires ETH's price >= or <=
    ///        targetPrice.
    /// @param targetPrice The condition's threshold price, normalized to
    ///        PRICE_DECIMALS.
    /// @param amount The deposited amount — wei for Sell, quoteToken base
    ///        units for Buy.
    /// @param maxSlippageBps Maximum acceptable slippage for the eventual swap.
    /// @param expiry Unix timestamp after which the order can no longer be
    ///        executed.
    event OrderCreated(
        uint256 indexed orderId,
        address indexed owner,
        OrderSide side,
        PriceCondition condition,
        uint256 targetPrice,
        uint256 amount,
        uint256 maxSlippageBps,
        uint256 expiry
    );

    /// @notice Emitted when an order is cancelled and its deposit refunded.
    /// @param orderId The id of the cancelled order.
    /// @param owner The address the refund was sent to.
    /// @param refundAmount The amount refunded, in the order's deposit asset.
    event OrderCancelled(uint256 indexed orderId, address indexed owner, uint256 refundAmount);

    /// @notice Emitted when an order is executed.
    /// @param orderId The id of the executed order.
    /// @param executor The address that called executeOrder() and received
    ///        the keeper fee.
    /// @param executionPrice ETH's USD price at execution, normalized to
    ///        PRICE_DECIMALS — the value the condition was actually checked
    ///        against.
    /// @param keeperFee The fee paid to executor, in the order's deposit asset.
    /// @param amountOut The amount received by the order owner — quoteToken
    ///        for Sell orders, wei for Buy orders.
    event OrderExecuted(
        uint256 indexed orderId, address indexed executor, uint256 executionPrice, uint256 keeperFee, uint256 amountOut
    );

    // =============================================================
    //                           ERRORS
    // =============================================================

    /// @notice Thrown when addPriceFeed is called with a zero asset address.
    error ZeroAsset();

    /// @notice Thrown when addPriceFeed is called with a zero feed address.
    error ZeroPriceFeed();

    /// @notice Thrown when the quoteToken supplied at construction is zero.
    error ZeroQuoteToken();

    /// @notice Thrown when the uniswapRouter supplied at construction is zero.
    error ZeroUniswapRouter();

    /// @notice Thrown when no feed is registered for the requested asset.
    /// @param asset The asset that has no registered feed.
    error UnsupportedAsset(address asset);

    /// @notice Thrown when the Chainlink price is invalid, zero/negative, or stale.
    error InvalidPrice();

    /// @notice Thrown when createOrder is called with a zero deposit amount.
    error ZeroAmount();

    /// @notice Thrown when createOrder's attached ETH doesn't match the
    ///         order's side: Sell requires msg.value == amount, Buy requires
    ///         msg.value == 0 (its deposit is pulled as quoteToken instead).
    /// @param side The side that was requested.
    /// @param sent The msg.value actually attached.
    /// @param expected The msg.value that side requires.
    error InvalidEthValue(OrderSide side, uint256 sent, uint256 expected);

    /// @notice Thrown when createOrder is given an expiry that is not in
    ///         the future.
    error InvalidExpiry();

    /// @notice Thrown when createOrder is given a slippage tolerance above
    ///         MAX_SLIPPAGE_BPS.
    /// @param maxSlippageBps The invalid slippage value supplied.
    error InvalidSlippage(uint256 maxSlippageBps);

    /// @notice Thrown when referencing an order id that was never created.
    /// @param orderId The order id that does not exist.
    error OrderNotFound(uint256 orderId);

    /// @notice Thrown when the caller is not the order's owner.
    /// @param caller The address that attempted the action.
    /// @param orderId The order it attempted the action on.
    error NotOrderOwner(address caller, uint256 orderId);

    /// @notice Thrown when an action requires a Pending order but it isn't one.
    /// @param orderId The order acted on.
    /// @param status The order's actual current status.
    error OrderNotPending(uint256 orderId, OrderStatus status);

    /// @notice Thrown when refunding a cancelled Sell order's ETH fails.
    error RefundFailed();

    /// @notice Thrown when ETH is sent directly to the contract instead of
    ///         via createOrder().
    error DirectEtherNotAccepted();

    /// @notice Thrown when executeOrder is called past the order's expiry.
    /// @param orderId The order that has expired.
    /// @param expiry The timestamp it expired at.
    error OrderExpired(uint256 orderId, uint256 expiry);

    /// @notice Thrown when executeOrder is called but the price condition
    ///         does not currently hold.
    /// @param orderId The order whose condition was not met.
    error ConditionNotMet(uint256 orderId);

    /// @notice Thrown when paying the keeper fee to the executor fails.
    error KeeperFeeTransferFailed();

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    /// @notice Initializes the contract with its owner, quote token, and
    ///         Uniswap V2 router.
    /// @param initialOwner Address allowed to register price feeds.
    /// @param quoteToken_ The ERC20 side of the pair.
    /// @param uniswapRouter_ The Uniswap V2 router used to swap on execution.
    constructor(address initialOwner, address quoteToken_, address uniswapRouter_) Ownable(initialOwner) {
        if (quoteToken_ == address(0)) revert ZeroQuoteToken();
        if (uniswapRouter_ == address(0)) revert ZeroUniswapRouter();

        quoteToken = quoteToken_;
        quoteTokenDecimals = IERC20Metadata(quoteToken_).decimals();
        uniswapRouter = IUniswapV2Router02(uniswapRouter_);
        weth = uniswapRouter.WETH();
    }

    // =============================================================
    //                      RECEIVE / FALLBACK
    // =============================================================

    /// @notice Rejects plain ETH transfers; ETH must be sent via createOrder().
    /// @dev Protects the solvency invariant (ETH balance == sum of active
    ///      Sell order amounts) from untracked deposits. Buy orders never
    ///      route ETH through this contract: swapExactTokensForETH unwraps
    ///      WETH inside the router and sends ETH straight to the order
    ///      owner, so this staying strict does not break execution.
    receive() external payable {
        revert DirectEtherNotAccepted();
    }

    // =============================================================
    //                      EXTERNAL FUNCTIONS
    // =============================================================

    /// @notice Registers (or replaces) the Chainlink price feed for an asset.
    /// @dev Owner-only: the set of trusted feeds never depends on caller
    ///      input. In practice weth is the only asset that needs one.
    ///      Emits PriceFeedAdded.
    /// @param asset The token to register a feed for.
    /// @param feed The Chainlink AggregatorV3Interface address for asset.
    function addPriceFeed(address asset, address feed) external onlyOwner {
        if (asset == address(0)) revert ZeroAsset();
        if (feed == address(0)) revert ZeroPriceFeed();

        priceFeeds[asset] = AggregatorV3Interface(feed);

        emit PriceFeedAdded(asset, feed);
    }

    /// @notice Creates a new limit order in either direction, depositing the
    ///         funds to be swapped once ETH's price condition is met.
    /// @dev Follows checks-effects-interactions, with the deposit pull as
    ///      the only interaction. nonReentrant is mandatory here for Buy
    ///      orders: safeTransferFrom hands control to quoteToken, which an
    ///      earlier ETH-only revision of this function did not have to
    ///      account for. Emits OrderCreated.
    /// @param side Sell to deposit ETH (attach it as msg.value), Buy to
    ///        deposit quoteToken (approve this contract for amount first).
    /// @param condition Whether execution requires ETH's price >= or <=
    ///        targetPrice.
    /// @param targetPrice The condition's threshold price, normalized to
    ///        PRICE_DECIMALS.
    /// @param amount The deposit: wei for Sell (must equal msg.value),
    ///        quoteToken base units for Buy (msg.value must be zero).
    /// @param maxSlippageBps Maximum acceptable slippage for the eventual
    ///        swap, in basis points. Must be <= MAX_SLIPPAGE_BPS.
    /// @param expiry Unix timestamp after which the order can no longer be
    ///        executed. Must be in the future.
    /// @return orderId The id of the newly created order.
    function createOrder(
        OrderSide side,
        PriceCondition condition,
        uint256 targetPrice,
        uint256 amount,
        uint256 maxSlippageBps,
        uint256 expiry
    ) external payable nonReentrant returns (uint256 orderId) {
        // CHECKS
        if (amount == 0) revert ZeroAmount();
        // Sell funds itself from msg.value; Buy funds itself from a
        // quoteToken pull, so any ETH attached to a Buy would be stranded.
        uint256 expectedValue = side == OrderSide.Sell ? amount : 0;
        if (msg.value != expectedValue) revert InvalidEthValue(side, msg.value, expectedValue);
        if (address(priceFeeds[weth]) == address(0)) revert UnsupportedAsset(weth);
        // Expiry windows here are minutes-to-hours scale; the ~seconds of
        // drift a miner could apply to block.timestamp is irrelevant at
        // that granularity.
        // slither-disable-next-line timestamp
        if (expiry <= block.timestamp) revert InvalidExpiry();
        if (maxSlippageBps > MAX_SLIPPAGE_BPS) revert InvalidSlippage(maxSlippageBps);

        // EFFECTS
        orderId = nextOrderId++;
        orders[orderId] = Order({
            owner: msg.sender,
            side: side,
            condition: condition,
            targetPrice: targetPrice,
            amount: amount,
            maxSlippageBps: maxSlippageBps,
            expiry: expiry,
            status: OrderStatus.Pending
        });

        emit OrderCreated(orderId, msg.sender, side, condition, targetPrice, amount, maxSlippageBps, expiry);

        // INTERACTIONS
        if (side == OrderSide.Buy) {
            IERC20(quoteToken).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    /// @notice Cancels a pending order and refunds its deposit to the owner.
    /// @dev Follows checks-effects-interactions: status is set to Cancelled
    ///      before the refund is sent. nonReentrant guards against
    ///      reentrancy via the refund. Refund asset follows the order's
    ///      side — ETH for Sell, quoteToken for Buy. Emits OrderCancelled.
    /// @param orderId The order to cancel.
    function cancelOrder(uint256 orderId) external nonReentrant {
        // CHECKS
        Order storage order = orders[orderId];
        if (order.owner == address(0)) revert OrderNotFound(orderId);
        if (order.owner != msg.sender) revert NotOrderOwner(msg.sender, orderId);
        if (order.status != OrderStatus.Pending) revert OrderNotPending(orderId, order.status);

        // EFFECTS
        uint256 refundAmount = order.amount;
        OrderSide side = order.side;
        order.status = OrderStatus.Cancelled;

        emit OrderCancelled(orderId, msg.sender, refundAmount);

        // INTERACTIONS
        if (side == OrderSide.Sell) {
            // msg.sender is already validated to equal order.owner above (the
            // NotOrderOwner check) — the refund recipient is never arbitrary.
            // slither-disable-next-line low-level-calls
            (bool success,) = msg.sender.call{value: refundAmount}("");
            if (!success) revert RefundFailed();
        } else {
            IERC20(quoteToken).safeTransfer(msg.sender, refundAmount);
        }
    }

    /// @notice Executes a pending order once ETH's price condition is
    ///         verified on-chain, swapping its deposit via Uniswap V2 and
    ///         paying the caller a keeper fee.
    /// @dev This is the trust boundary described in README's Security
    ///      Considerations: permissionless by design (anyone may call this
    ///      — the keeper bot has no special privilege), but execution only
    ///      proceeds if this contract's own re-verified price — via
    ///      getAssetPrice(weth), never a caller-supplied value — actually
    ///      satisfies the order's condition. Follows checks-effects-
    ///      interactions: status is set to Executed, and the fee/swap
    ///      amounts are computed, before any external call. If the fee
    ///      transfer or the swap reverts (e.g. slippage exceeded), the
    ///      entire call reverts and every state change here unwinds,
    ///      leaving the order Pending for a later retry. minAmountOut is
    ///      derived from the same oracle price the condition was checked
    ///      against (not Uniswap's own quote), scaled by the order's
    ///      maxSlippageBps.
    /// @param orderId The order to execute.
    /// @return amountOut The amount received by the order owner —
    ///         quoteToken for Sell orders, wei for Buy orders.
    function executeOrder(uint256 orderId) external nonReentrant returns (uint256 amountOut) {
        // CHECKS
        Order storage order = orders[orderId];
        if (order.owner == address(0)) revert OrderNotFound(orderId);
        if (order.status != OrderStatus.Pending) revert OrderNotPending(orderId, order.status);
        // Expiry windows here are minutes-to-hours scale; the ~seconds of
        // drift a miner could apply to block.timestamp is irrelevant at
        // that granularity.
        // slither-disable-next-line timestamp
        if (block.timestamp > order.expiry) revert OrderExpired(orderId, order.expiry);

        uint256 executionPrice = getAssetPrice(weth);
        bool met = order.condition == PriceCondition.GreaterOrEqual
            ? executionPrice >= order.targetPrice
            : executionPrice <= order.targetPrice;
        if (!met) revert ConditionNotMet(orderId);

        // EFFECTS
        OrderSide side = order.side;
        uint256 keeperFee = (order.amount * KEEPER_FEE_BPS) / MAX_SLIPPAGE_BPS;
        uint256 swapAmount = order.amount - keeperFee;
        uint256 amountOutMin = _minAmountOut(side, swapAmount, executionPrice, order.maxSlippageBps);
        address orderOwner = order.owner;
        order.status = OrderStatus.Executed;

        // INTERACTIONS
        amountOut = _payFeeAndSwap(side, keeperFee, swapAmount, amountOutMin, orderOwner);

        emit OrderExecuted(orderId, msg.sender, executionPrice, keeperFee, amountOut);
    }

    // =============================================================
    //                      PUBLIC FUNCTIONS
    // =============================================================

    /// @notice Returns the current USD price of asset, normalized to
    ///         PRICE_DECIMALS.
    /// @dev Reads the latest round from asset's registered Chainlink feed,
    ///      rejects non-positive or stale prices, and normalizes the result.
    ///      Reverts with UnsupportedAsset if no feed is registered for asset.
    /// @param asset The token to price. Every order gates on weth.
    /// @return price Current asset price, normalized to PRICE_DECIMALS.
    function getAssetPrice(address asset) public view returns (uint256 price) {
        AggregatorV3Interface feed = priceFeeds[asset];
        if (address(feed) == address(0)) revert UnsupportedAsset(asset);

        // roundId and answeredInRound are intentionally unused — the
        // updatedAt staleness check below already covers the relevant
        // risk (a round too old to trust), without needing to also compare
        // roundId against answeredInRound.
        // slither-disable-next-line unused-return
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();

        if (answer <= 0) revert InvalidPrice();
        // PRICE_STALENESS_THRESHOLD is 1 hour; the ~seconds of drift a
        // miner could apply to block.timestamp is irrelevant at that
        // granularity.
        // slither-disable-next-line timestamp
        if (updatedAt == 0 || block.timestamp - updatedAt > PRICE_STALENESS_THRESHOLD) {
            revert InvalidPrice();
        }

        price = _normalizePrice(answer, feed.decimals());
    }

    /// @notice Checks whether an order's price condition currently holds.
    /// @dev Read-only — does not move funds or change state. This is the
    ///      piece executeOrder() gates on: the contract independently
    ///      re-verifies ETH's price here rather than trusting a value
    ///      supplied by a keeper bot. Both sides read the same price; only
    ///      the comparison direction differs, via order.condition.
    /// @param order The order whose condition to check.
    /// @return met True if ETH's current price satisfies order.condition
    ///         against order.targetPrice.
    function checkPriceCondition(Order memory order) public view returns (bool met) {
        uint256 currentPrice = getAssetPrice(weth);

        met = order.condition == PriceCondition.GreaterOrEqual
            ? currentPrice >= order.targetPrice
            : currentPrice <= order.targetPrice;
    }

    /// @notice Checks whether a stored order's price condition currently holds.
    /// @dev Convenience overload for callers that only have an orderId —
    ///      e.g. keeper-bot's eth_call, or executeOrder() internally — so
    ///      they don't need to reconstruct the full Order struct off-chain
    ///      just to check a condition. Reverts with OrderNotFound if orderId
    ///      was never created.
    /// @param orderId The id of the order to check.
    /// @return met True if ETH's current price satisfies the order's
    ///         condition.
    function checkPriceCondition(uint256 orderId) external view returns (bool met) {
        Order memory order = orders[orderId];
        if (order.owner == address(0)) revert OrderNotFound(orderId);

        met = checkPriceCondition(order);
    }

    // =============================================================
    //                      INTERNAL FUNCTIONS
    // =============================================================

    /// @notice Pays the keeper fee and performs the swap for the given side.
    /// @dev Split out of executeOrder() to keep that function's stack
    ///      shallow — an earlier revision hit stack-too-deep before the
    ///      helper extraction, and adding the side branch would reintroduce
    ///      it. Fee and swap are both denominated in the deposit asset, so
    ///      neither requires a conversion.
    /// @param side The order's side.
    /// @param keeperFee The fee to pay msg.sender, in the deposit asset.
    /// @param swapAmount The post-fee amount to swap.
    /// @param amountOutMin The minimum acceptable swap output.
    /// @param orderOwner The address the swap output is sent to.
    /// @return amountOut The swap's final output amount.
    function _payFeeAndSwap(
        OrderSide side,
        uint256 keeperFee,
        uint256 swapAmount,
        uint256 amountOutMin,
        address orderOwner
    ) internal returns (uint256 amountOut) {
        address[] memory path = _swapPath(side);
        uint256[] memory amounts;

        if (side == OrderSide.Sell) {
            // executeOrder is permissionless by design (see its NatSpec):
            // the fee recipient is deliberately whoever triggers execution,
            // not a fixed or pre-validated address.
            // slither-disable-next-line arbitrary-send-eth,low-level-calls
            (bool feeSuccess,) = msg.sender.call{value: keeperFee}("");
            if (!feeSuccess) revert KeeperFeeTransferFailed();

            // Deadline is this same block — the swap either lands now or
            // reverts with everything else.
            // slither-disable-next-line timestamp
            amounts =
                uniswapRouter.swapExactETHForTokens{value: swapAmount}(amountOutMin, path, orderOwner, block.timestamp);
        } else {
            IERC20(quoteToken).safeTransfer(msg.sender, keeperFee);
            // forceApprove (not approve) for tokens that require allowance
            // to be zeroed before being re-set. Set to exactly swapAmount,
            // which the router consumes in full, leaving no standing
            // allowance behind.
            IERC20(quoteToken).forceApprove(address(uniswapRouter), swapAmount);

            // slither-disable-next-line timestamp
            amounts = uniswapRouter.swapExactTokensForETH(swapAmount, amountOutMin, path, orderOwner, block.timestamp);
        }

        amountOut = amounts[amounts.length - 1];
    }

    /// @notice Computes the minimum acceptable swap output for executeOrder.
    /// @dev Derives a fair-value output from executionPrice (the same
    ///      oracle price the condition was checked against, not Uniswap's
    ///      own quote), then applies maxSlippageBps as the allowed
    ///      deviation. Assumes quoteToken is USD-pegged (1 quoteToken == $1),
    ///      so the two directions are exact inverses of each other: Sell
    ///      multiplies by the ETH price, Buy divides by it. Each is computed
    ///      as one combined fraction with a single final division, rather
    ///      than rounding a fair-value intermediate before applying the
    ///      slippage cut, which would lose avoidable precision.
    /// @param side The order's side, selecting the conversion direction.
    /// @param swapAmount The amount being swapped, in the deposit asset.
    /// @param executionPrice ETH's USD price, normalized to PRICE_DECIMALS.
    /// @param maxSlippageBps The order's maximum acceptable slippage.
    /// @return amountOutMin The minimum output amount the swap must return.
    function _minAmountOut(OrderSide side, uint256 swapAmount, uint256 executionPrice, uint256 maxSlippageBps)
        internal
        view
        returns (uint256 amountOutMin)
    {
        uint256 slippageNumerator = MAX_SLIPPAGE_BPS - maxSlippageBps;
        // 1e36: PRICE_DECIMALS (the price's scale) + 18 (wei's scale).
        uint256 ethScale = 10 ** (uint256(PRICE_DECIMALS) + 18);
        uint256 quoteScale = 10 ** quoteTokenDecimals;

        if (side == OrderSide.Sell) {
            // wei in -> quoteToken out: multiply by the ETH price.
            amountOutMin =
                (swapAmount * executionPrice * quoteScale * slippageNumerator) / (ethScale * MAX_SLIPPAGE_BPS);
        } else {
            // quoteToken in -> wei out: divide by the ETH price.
            amountOutMin =
                (swapAmount * ethScale * slippageNumerator) / (executionPrice * quoteScale * MAX_SLIPPAGE_BPS);
        }
    }

    /// @notice Builds the two-hop Uniswap V2 swap path for the given side.
    /// @dev One fixed pair, traded in whichever direction the order needs:
    ///      [weth, quoteToken] to sell, [quoteToken, weth] to buy. Uniswap
    ///      V2 requires path[0] to be the router's own WETH for
    ///      swapExactETHForTokens, and path[last] to be it for
    ///      swapExactTokensForETH — both satisfied by construction here.
    /// @param side The order's side.
    /// @return path The swap path for that direction.
    function _swapPath(OrderSide side) internal view returns (address[] memory path) {
        path = new address[](2);
        if (side == OrderSide.Sell) {
            path[0] = weth;
            path[1] = quoteToken;
        } else {
            path[0] = quoteToken;
            path[1] = weth;
        }
    }

    /// @notice Normalizes a raw Chainlink price to PRICE_DECIMALS.
    /// @param rawPrice The raw, positive price returned by the feed.
    /// @param feedDecimals The number of decimals the feed reports prices in.
    /// @return normalizedPrice The price scaled to PRICE_DECIMALS.
    function _normalizePrice(int256 rawPrice, uint8 feedDecimals) internal pure returns (uint256 normalizedPrice) {
        // Safe: getAssetPrice() only calls this after checking rawPrice > 0.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 price = uint256(rawPrice);

        if (feedDecimals < PRICE_DECIMALS) {
            normalizedPrice = price * (10 ** (PRICE_DECIMALS - feedDecimals));
        } else if (feedDecimals > PRICE_DECIMALS) {
            normalizedPrice = price / (10 ** (feedDecimals - PRICE_DECIMALS));
        } else {
            normalizedPrice = price;
        }
    }
}
