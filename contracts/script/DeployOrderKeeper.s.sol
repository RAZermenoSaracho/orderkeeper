// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {OrderKeeper} from "../src/OrderKeeper.sol";
import {DemoUSDC} from "../src/DemoUSDC.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/// @title DeployOrderKeeper
/// @notice Foundry deployment script for OrderKeeper on Sepolia.
/// @dev Deploys OrderKeeper, deploys a testnet-only quote token (DemoUSDC —
///      see that contract for why), registers the real Chainlink ETH/USD
///      feed, and seeds initial WETH/DemoUSDC Uniswap V2 liquidity, since no
///      real WETH/stablecoin pair exists yet on this router (verified via
///      getPair() returning address(0) for both Circle's official USDC and
///      a third-party test USDC). Reads PRIVATE_KEY, CHAINLINK_ETH_USD_FEED,
///      and UNISWAP_ROUTER_ADDRESS from the environment (see
///      CLAUDE.md's Environment Variables and ../.env.example).
///      INITIAL_LIQUIDITY_ETH is optional, defaulting to
///      DEFAULT_INITIAL_LIQUIDITY_ETH. Run with:
///        forge script script/DeployOrderKeeper.s.sol --rpc-url sepolia --broadcast
contract DeployOrderKeeper is Script {
    /// @notice Default ETH amount seeded as initial Uniswap liquidity, used
    ///         when the INITIAL_LIQUIDITY_ETH environment variable is not set.
    uint256 public constant DEFAULT_INITIAL_LIQUIDITY_ETH = 1 ether;

    /// @notice Buffer added to block.timestamp when computing the Uniswap
    ///         deadline passed to addLiquidityETH.
    /// @dev Foundry scripts simulate the entire run() in one pass, fixing
    ///      block.timestamp once and baking it into every transaction's
    ///      calldata before any of them are broadcast. Under --slow (which
    ///      waits for each of the preceding transactions to confirm before
    ///      sending the next), real wall-clock time elapses between that
    ///      simulation and this specific transaction actually being mined —
    ///      a bare `block.timestamp` deadline can lapse before it's even
    ///      broadcast. This buffer must comfortably exceed the total
    ///      confirmation time of every transaction before this one.
    uint256 public constant DEADLINE_BUFFER = 30 minutes;

    /// @notice Deploys OrderKeeper and its supporting testnet setup.
    /// @return orderKeeper The deployed OrderKeeper instance.
    /// @return quoteToken The deployed DemoUSDC instance.
    function run() external returns (OrderKeeper orderKeeper, DemoUSDC quoteToken) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address priceFeed = vm.envAddress("CHAINLINK_ETH_USD_FEED");
        address uniswapRouterAddr = vm.envAddress("UNISWAP_ROUTER_ADDRESS");
        uint256 initialLiquidityEth = vm.envOr("INITIAL_LIQUIDITY_ETH", DEFAULT_INITIAL_LIQUIDITY_ETH);

        address deployer = vm.addr(deployerPrivateKey);
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapRouterAddr);
        address weth = router.WETH();

        vm.startBroadcast(deployerPrivateKey);

        quoteToken = new DemoUSDC();
        orderKeeper = new OrderKeeper(deployer, address(quoteToken), uniswapRouterAddr);
        orderKeeper.addPriceFeed(weth, priceFeed);

        _seedLiquidity(orderKeeper, router, quoteToken, weth, deployer, initialLiquidityEth);

        vm.stopBroadcast();

        _writeDeploymentRecord(address(orderKeeper), address(quoteToken), weth, uniswapRouterAddr, priceFeed);
    }

    /// @notice Mints DemoUSDC priced at the live Chainlink rate and adds it
    ///         with liquidityEth as the pool's initial Uniswap V2 liquidity.
    /// @dev The quoteToken amount is derived from orderKeeper.getAssetPrice()
    ///      at deploy time — not a hardcoded historical price — so the pool
    ///      starts priced consistently with the oracle it will later be
    ///      checked against. amountTokenMin/amountETHMin are 0: this is a
    ///      brand-new pair with no existing price to be sandwiched against,
    ///      so there's no slippage to protect against on this specific call.
    function _seedLiquidity(
        OrderKeeper orderKeeper,
        IUniswapV2Router02 router,
        DemoUSDC quoteToken,
        address weth,
        address deployer,
        uint256 liquidityEth
    ) internal {
        uint256 ethPriceUsd = orderKeeper.getAssetPrice(weth);
        uint256 quoteTokenAmount =
            (liquidityEth * ethPriceUsd) / (10 ** (18 + uint256(orderKeeper.PRICE_DECIMALS()) - quoteToken.decimals()));

        quoteToken.mint(deployer, quoteTokenAmount);
        quoteToken.approve(address(router), quoteTokenAmount);

        router.addLiquidityETH{value: liquidityEth}(
            address(quoteToken), quoteTokenAmount, 0, 0, deployer, block.timestamp + DEADLINE_BUFFER
        );
    }

    /// @notice Writes deployed addresses to ../deployments/sepolia.json, per
    ///         the convention documented in that directory's README.
    /// @dev Transaction-level detail (hashes, gas used) already lives in
    ///      Foundry's own broadcast/ artifacts — this file is a quick-
    ///      reference summary of addresses, not a replacement for them.
    function _writeDeploymentRecord(
        address orderKeeperAddr,
        address quoteTokenAddr,
        address weth,
        address uniswapRouterAddr,
        address priceFeed
    ) internal {
        string memory json = "deployment";
        vm.serializeUint(json, "chainId", block.chainid);
        vm.serializeAddress(json, "OrderKeeper", orderKeeperAddr);
        vm.serializeAddress(json, "quoteToken", quoteTokenAddr);
        vm.serializeAddress(json, "weth", weth);
        vm.serializeAddress(json, "uniswapRouter", uniswapRouterAddr);
        vm.serializeAddress(json, "priceFeed", priceFeed);
        string memory finalJson = vm.serializeUint(json, "deployedAt", block.timestamp);

        vm.writeJson(finalJson, "../deployments/sepolia.json");
    }
}
