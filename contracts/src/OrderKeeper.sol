// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/// @title OrderKeeper
/// @author Ricardo
/// @notice Trustless limit-order keeper: custodies order funds and verifies
///         price conditions on-chain against Chainlink before execution.
/// @dev This is a work in progress, built incrementally task by task. This
///      slice adds order custody and lifecycle (createOrder/cancelOrder) on
///      top of the oracle price verification already implemented. Orders
///      hold native ETH only for this MVP — no ERC20 deposits — and pay out
///      in a single global quoteToken once executed. executeOrder() and the
///      Uniswap swap itself land in a later task.
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
contract OrderKeeper is Ownable, ReentrancyGuard {
    // =============================================================
    //                        TYPES
    // =============================================================

    /// @notice Direction of an order's price condition.
    enum PriceCondition {
        GreaterOrEqual,
        LessOrEqual
    }

    /// @notice Lifecycle state of an order.
    enum OrderStatus {
        Pending,
        Executed,
        Cancelled
    }

    /// @notice A limit order: ETH deposited by owner, to be sold for
    ///         quoteToken once asset's USD price satisfies condition.
    /// @param owner The address that created and funded the order, and the
    ///        only address allowed to cancel it.
    /// @param asset The token whose USD price this order's condition
    ///        applies to (looked up in priceFeeds).
    /// @param condition Whether execution requires price >= or <= targetPrice.
    /// @param targetPrice The condition's threshold price, normalized to
    ///        PRICE_DECIMALS.
    /// @param amount The ETH amount deposited (wei), refunded on cancel or
    ///        swapped on execution.
    /// @param maxSlippageBps Maximum acceptable slippage for the eventual
    ///        swap, in basis points (e.g. 100 = 1%).
    /// @param expiry Unix timestamp after which the order can no longer be
    ///        executed.
    /// @param status The order's current lifecycle state.
    struct Order {
        address owner;
        address asset;
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

    /// @notice Keeper fee taken from an order's ETH amount on execution, in
    ///         basis points of MAX_SLIPPAGE_BPS (50 = 0.5%). Paid to whoever
    ///         calls executeOrder().
    uint256 public constant KEEPER_FEE_BPS = 50;

    /// @notice Chainlink price feed registered per asset, owner-managed.
    /// @dev Orders reference an asset already present here — never an
    ///      arbitrary caller-supplied feed address — so the set of trusted
    ///      feeds is controlled entirely by the owner, on-chain.
    mapping(address asset => AggregatorV3Interface feed) public priceFeeds;

    /// @notice The single token every executed order pays out in.
    /// @dev Set once at deployment; not per-order, per the project's
    ///      simplicity preference — every order sells `asset` for this token.
    address public immutable quoteToken;

    /// @notice quoteToken's decimals(), cached at construction so
    ///         executeOrder() doesn't re-query it on every execution.
    /// @dev Execution math assumes quoteToken is USD-pegged (1 quoteToken
    ///      == $1) — true for the stablecoin this contract is deployed with.
    uint8 public immutable quoteTokenDecimals;

    /// @notice The Uniswap V2 router used to swap ETH for quoteToken on
    ///         execution.
    IUniswapV2Router02 public immutable uniswapRouter;

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
    /// @param asset The token whose USD price the condition applies to.
    /// @param condition Whether execution requires price >= or <= targetPrice.
    /// @param targetPrice The condition's threshold price, normalized to
    ///        PRICE_DECIMALS.
    /// @param amount The ETH amount deposited (wei).
    /// @param maxSlippageBps Maximum acceptable slippage for the eventual swap.
    /// @param expiry Unix timestamp after which the order can no longer be
    ///        executed.
    event OrderCreated(
        uint256 indexed orderId,
        address indexed owner,
        address indexed asset,
        PriceCondition condition,
        uint256 targetPrice,
        uint256 amount,
        uint256 maxSlippageBps,
        uint256 expiry
    );

    /// @notice Emitted when an order is cancelled and its deposit refunded.
    /// @param orderId The id of the cancelled order.
    /// @param owner The address the refund was sent to.
    /// @param refundAmount The ETH amount refunded (wei).
    event OrderCancelled(uint256 indexed orderId, address indexed owner, uint256 refundAmount);

    /// @notice Emitted when an order is executed.
    /// @param orderId The id of the executed order.
    /// @param executor The address that called executeOrder() and received
    ///        the keeper fee.
    /// @param executionPrice asset's USD price at execution, normalized to
    ///        PRICE_DECIMALS — the value the condition was actually checked
    ///        against.
    /// @param keeperFee The ETH amount paid to executor.
    /// @param amountOut The quoteToken amount received by the order owner.
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

    /// @notice Thrown when createOrder is called with no ETH attached.
    error ZeroAmount();

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

    /// @notice Thrown when refunding a cancelled order's deposit fails.
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

    /// @notice Initializes the contract with its owner, payout token, and
    ///         Uniswap V2 router.
    /// @param initialOwner Address allowed to register price feeds.
    /// @param quoteToken_ The single token every executed order pays out in.
    /// @param uniswapRouter_ The Uniswap V2 router used to swap on execution.
    constructor(address initialOwner, address quoteToken_, address uniswapRouter_) Ownable(initialOwner) {
        if (quoteToken_ == address(0)) revert ZeroQuoteToken();
        if (uniswapRouter_ == address(0)) revert ZeroUniswapRouter();

        quoteToken = quoteToken_;
        quoteTokenDecimals = IERC20Metadata(quoteToken_).decimals();
        uniswapRouter = IUniswapV2Router02(uniswapRouter_);
    }

    // =============================================================
    //                      RECEIVE / FALLBACK
    // =============================================================

    /// @notice Rejects plain ETH transfers; ETH must be sent via createOrder().
    /// @dev Protects the solvency invariant (contract balance == sum of
    ///      active order amounts) from untracked deposits.
    receive() external payable {
        revert DirectEtherNotAccepted();
    }

    // =============================================================
    //                      EXTERNAL FUNCTIONS
    // =============================================================

    /// @notice Registers (or replaces) the Chainlink price feed for an asset.
    /// @dev Owner-only: this is the only way an asset becomes eligible for
    ///      orders, so the set of trusted feeds never depends on caller input.
    ///      Emits PriceFeedAdded.
    /// @param asset The token to register a feed for.
    /// @param feed The Chainlink AggregatorV3Interface address for asset.
    function addPriceFeed(address asset, address feed) external onlyOwner {
        if (asset == address(0)) revert ZeroAsset();
        if (feed == address(0)) revert ZeroPriceFeed();

        priceFeeds[asset] = AggregatorV3Interface(feed);

        emit PriceFeedAdded(asset, feed);
    }

    /// @notice Creates a new limit order, depositing ETH to be sold once the
    ///         price condition is met.
    /// @dev Follows checks-effects-interactions. There is no external call
    ///      in this function — msg.value is already received as part of the
    ///      call itself — so no reentrancy guard is needed here. Emits
    ///      OrderCreated.
    /// @param asset The token whose USD price the condition applies to; must
    ///        already have a registered feed (see addPriceFeed).
    /// @param condition Whether execution requires price >= or <= targetPrice.
    /// @param targetPrice The condition's threshold price, normalized to
    ///        PRICE_DECIMALS.
    /// @param maxSlippageBps Maximum acceptable slippage for the eventual
    ///        swap, in basis points (e.g. 100 = 1%). Must be <= MAX_SLIPPAGE_BPS.
    /// @param expiry Unix timestamp after which the order can no longer be
    ///        executed. Must be in the future.
    /// @return orderId The id of the newly created order.
    function createOrder(
        address asset,
        PriceCondition condition,
        uint256 targetPrice,
        uint256 maxSlippageBps,
        uint256 expiry
    ) external payable returns (uint256 orderId) {
        // CHECKS
        if (msg.value == 0) revert ZeroAmount();
        if (address(priceFeeds[asset]) == address(0)) revert UnsupportedAsset(asset);
        if (expiry <= block.timestamp) revert InvalidExpiry();
        if (maxSlippageBps > MAX_SLIPPAGE_BPS) revert InvalidSlippage(maxSlippageBps);

        // EFFECTS
        orderId = nextOrderId++;
        orders[orderId] = Order({
            owner: msg.sender,
            asset: asset,
            condition: condition,
            targetPrice: targetPrice,
            amount: msg.value,
            maxSlippageBps: maxSlippageBps,
            expiry: expiry,
            status: OrderStatus.Pending
        });

        emit OrderCreated(orderId, msg.sender, asset, condition, targetPrice, msg.value, maxSlippageBps, expiry);
    }

    /// @notice Cancels a pending order and refunds its deposited ETH to the
    ///         owner.
    /// @dev Follows checks-effects-interactions: status is set to Cancelled
    ///      before the refund is sent. nonReentrant guards against
    ///      reentrancy via the refund call. Emits OrderCancelled.
    /// @param orderId The order to cancel.
    function cancelOrder(uint256 orderId) external nonReentrant {
        // CHECKS
        Order storage order = orders[orderId];
        if (order.owner == address(0)) revert OrderNotFound(orderId);
        if (order.owner != msg.sender) revert NotOrderOwner(msg.sender, orderId);
        if (order.status != OrderStatus.Pending) revert OrderNotPending(orderId, order.status);

        // EFFECTS
        uint256 refundAmount = order.amount;
        order.status = OrderStatus.Cancelled;

        emit OrderCancelled(orderId, msg.sender, refundAmount);

        // INTERACTIONS
        (bool success,) = msg.sender.call{value: refundAmount}("");
        if (!success) revert RefundFailed();
    }

    /// @notice Executes a pending order once its price condition is
    ///         verified on-chain, swapping its ETH deposit for quoteToken
    ///         via Uniswap V2 and paying the caller a keeper fee.
    /// @dev This is the trust boundary described in README's Security
    ///      Considerations: permissionless by design (anyone may call this
    ///      — the keeper bot has no special privilege), but execution only
    ///      proceeds if this contract's own re-verified price — via
    ///      getAssetPrice(), never a caller-supplied value — actually
    ///      satisfies the order's condition. Follows checks-effects-
    ///      interactions: status is set to Executed, and the fee/swap
    ///      amounts are computed, before either external call. If the
    ///      keeper fee transfer or the swap reverts (e.g. slippage
    ///      exceeded), the entire call reverts and every state change here
    ///      unwinds, leaving the order Pending for a later retry — no
    ///      distinct failure status is needed. minAmountOut is derived from
    ///      the same oracle price the condition was checked against (not
    ///      Uniswap's own quote), scaled by the order's maxSlippageBps, so
    ///      slippage tolerance is measured against the trusted price source.
    /// @param orderId The order to execute.
    /// @return amountOut The quoteToken amount received by the order owner.
    function executeOrder(uint256 orderId) external nonReentrant returns (uint256 amountOut) {
        // CHECKS
        Order storage order = orders[orderId];
        if (order.owner == address(0)) revert OrderNotFound(orderId);
        if (order.status != OrderStatus.Pending) revert OrderNotPending(orderId, order.status);
        if (block.timestamp > order.expiry) revert OrderExpired(orderId, order.expiry);

        uint256 executionPrice = getAssetPrice(order.asset);
        bool met = order.condition == PriceCondition.GreaterOrEqual
            ? executionPrice >= order.targetPrice
            : executionPrice <= order.targetPrice;
        if (!met) revert ConditionNotMet(orderId);

        // EFFECTS
        uint256 keeperFee = (order.amount * KEEPER_FEE_BPS) / MAX_SLIPPAGE_BPS;
        uint256 swapAmount = order.amount - keeperFee;
        uint256 amountOutMin = _minAmountOut(swapAmount, executionPrice, order.maxSlippageBps);
        address[] memory path = _swapPath(order.asset);
        address orderOwner = order.owner;
        order.status = OrderStatus.Executed;

        // INTERACTIONS
        (bool feeSuccess,) = msg.sender.call{value: keeperFee}("");
        if (!feeSuccess) revert KeeperFeeTransferFailed();

        uint256[] memory amounts =
            uniswapRouter.swapExactETHForTokens{value: swapAmount}(amountOutMin, path, orderOwner, block.timestamp);
        amountOut = amounts[amounts.length - 1];

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
    /// @param asset The token to price.
    /// @return price Current asset price, normalized to PRICE_DECIMALS.
    function getAssetPrice(address asset) public view returns (uint256 price) {
        AggregatorV3Interface feed = priceFeeds[asset];
        if (address(feed) == address(0)) revert UnsupportedAsset(asset);

        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();

        if (answer <= 0) revert InvalidPrice();
        if (updatedAt == 0 || block.timestamp - updatedAt > PRICE_STALENESS_THRESHOLD) {
            revert InvalidPrice();
        }

        price = _normalizePrice(answer, feed.decimals());
    }

    /// @notice Checks whether an order's price condition currently holds.
    /// @dev Read-only — does not move funds or change state. This is the
    ///      piece an eventual executeOrder() gates on: the contract
    ///      independently re-verifies price here rather than trusting a
    ///      value supplied by a keeper bot.
    /// @param order The order whose condition to check.
    /// @return met True if the current asset price satisfies order.condition
    ///         against order.targetPrice.
    function checkPriceCondition(Order memory order) public view returns (bool met) {
        uint256 currentPrice = getAssetPrice(order.asset);

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
    /// @return met True if the current asset price satisfies the order's
    ///         condition.
    function checkPriceCondition(uint256 orderId) external view returns (bool met) {
        Order memory order = orders[orderId];
        if (order.owner == address(0)) revert OrderNotFound(orderId);

        met = checkPriceCondition(order);
    }

    // =============================================================
    //                      INTERNAL FUNCTIONS
    // =============================================================

    /// @notice Computes the minimum acceptable swap output for executeOrder.
    /// @dev Derives a fair-value output from executionPrice (the same
    ///      oracle price the condition was checked against, not Uniswap's
    ///      own quote), then applies maxSlippageBps as the allowed
    ///      deviation. Assumes quoteToken is USD-pegged (1 quoteToken == $1).
    /// @param swapAmount The ETH amount being swapped (wei).
    /// @param executionPrice asset's USD price, normalized to PRICE_DECIMALS.
    /// @param maxSlippageBps The order's maximum acceptable slippage.
    /// @return amountOutMin The minimum quoteToken amount the swap must return.
    function _minAmountOut(uint256 swapAmount, uint256 executionPrice, uint256 maxSlippageBps)
        internal
        view
        returns (uint256 amountOutMin)
    {
        uint256 fairValueOut =
            (swapAmount * executionPrice * (10 ** quoteTokenDecimals)) / (10 ** (uint256(PRICE_DECIMALS) + 18));
        amountOutMin = fairValueOut - (fairValueOut * maxSlippageBps) / MAX_SLIPPAGE_BPS;
    }

    /// @notice Builds the two-hop Uniswap V2 swap path from asset to quoteToken.
    /// @param asset The token being sold.
    /// @return path The [asset, quoteToken] path for swapExactETHForTokens.
    function _swapPath(address asset) internal view returns (address[] memory path) {
        path = new address[](2);
        path[0] = asset;
        path[1] = quoteToken;
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
