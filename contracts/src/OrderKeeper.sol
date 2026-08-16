// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title OrderKeeper
/// @author Ricardo
/// @notice Trustless limit-order keeper: custodies order funds and verifies
///         price conditions on-chain against Chainlink before execution.
/// @dev This is a work in progress, built incrementally task by task. This
///      slice covers only oracle price verification — the multi-pair feed
///      registry, price normalization, and the read path an eventual
///      executeOrder() will gate on. Order creation, fund custody, and the
///      Uniswap swap itself are not implemented yet; the Order struct below
///      intentionally carries only the fields price verification needs.
///
///      Price verification pattern (staleness check + decimal normalization)
///      is reused from Module 13's RWAAssetToken.sol, which proved it against
///      a live Sepolia Chainlink feed.
contract OrderKeeper is Ownable {
    // =============================================================
    //                        TYPES
    // =============================================================

    /// @notice Direction of an order's price condition.
    enum PriceCondition {
        GreaterOrEqual,
        LessOrEqual
    }

    /// @notice Minimal order shape needed for price verification.
    /// @dev More fields (owner, amounts, tokenOut, status) land when
    ///      createOrder()/cancelOrder()/executeOrder() are implemented.
    /// @param asset The token whose USD price this order's condition
    ///        applies to (looked up in priceFeeds).
    /// @param condition Whether execution requires price >= or <= targetPrice.
    /// @param targetPrice The condition's threshold price, normalized to
    ///        PRICE_DECIMALS.
    struct Order {
        address asset;
        PriceCondition condition;
        uint256 targetPrice;
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

    /// @notice Chainlink price feed registered per asset, owner-managed.
    /// @dev Orders reference an asset already present here — never an
    ///      arbitrary caller-supplied feed address — so the set of trusted
    ///      feeds is controlled entirely by the owner, on-chain.
    mapping(address asset => AggregatorV3Interface feed) public priceFeeds;

    // =============================================================
    //                           EVENTS
    // =============================================================

    /// @notice Emitted when the owner registers or replaces an asset's feed.
    /// @param asset The token the feed prices.
    /// @param feed The Chainlink AggregatorV3Interface address for asset.
    event PriceFeedAdded(address indexed asset, address indexed feed);

    // =============================================================
    //                           ERRORS
    // =============================================================

    /// @notice Thrown when addPriceFeed is called with a zero asset address.
    error ZeroAsset();

    /// @notice Thrown when addPriceFeed is called with a zero feed address.
    error ZeroPriceFeed();

    /// @notice Thrown when no feed is registered for the requested asset.
    /// @param asset The asset that has no registered feed.
    error UnsupportedAsset(address asset);

    /// @notice Thrown when the Chainlink price is invalid, zero/negative, or stale.
    error InvalidPrice();

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    /// @notice Initializes the contract with its owner.
    /// @param initialOwner Address allowed to register price feeds.
    constructor(address initialOwner) Ownable(initialOwner) {}

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
    /// @dev Pure read — does not move funds or change state. This is the
    ///      piece an eventual executeOrder() gates on: the contract
    ///      independently re-verifies price here rather than trusting a
    ///      value supplied by a keeper bot.
    /// @param order The order whose condition to check.
    /// @return met True if the current asset price satisfies order.condition
    ///         against order.targetPrice.
    function checkPriceCondition(Order calldata order) public view returns (bool met) {
        uint256 currentPrice = getAssetPrice(order.asset);

        met = order.condition == PriceCondition.GreaterOrEqual
            ? currentPrice >= order.targetPrice
            : currentPrice <= order.targetPrice;
    }

    // =============================================================
    //                      INTERNAL FUNCTIONS
    // =============================================================

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
