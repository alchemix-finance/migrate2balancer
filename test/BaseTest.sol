// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "./utils/DSTestPlus.sol";
import "lib/forge-std/src/console2.sol";

import "src/Migrator.sol";

import "src/interfaces/balancer/IManagedPool.sol";
import "src/interfaces/balancer/WeightedMath.sol";
import "src/interfaces/chainlink/AggregatorV3Interface.sol";

contract BaseTest is DSTestPlus {
    Migrator public migrator;

    // Test variables
    address public user;
    uint256 public userPrivateKey = 0xBEEF;
    uint256 public slippage = 10;
    uint256 public BPS = 10000;

    ERC20 public companionToken;
    IUniswapV2Pair public lpToken;

    IBasePool public balancerPoolToken = IBasePool(0xf16aEe6a71aF1A9Bc8F56975A4c2705ca7A782Bc);
    IRewardPool4626 public auraPool = IRewardPool4626(0x8B227E3D50117E80a02cd0c67Cd6F89A8b7B46d7);
    AggregatorV3Interface public wethPriceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    AggregatorV3Interface public tokenPriceFeed = AggregatorV3Interface(0x194a9AaF2e0b67c35915cD01101585A33Fe25CAa);

    // Constructor parameters
    ERC20 public weth = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public router = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    bytes32 public initHash = hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303";

    function setUp() public {
        user = hevm.addr(userPrivateKey);

        // Set the companion token given any LP token
        (lpToken, companionToken) = getPairAddress(address(balancerPoolToken));

        migrator = new Migrator(address(weth), balancerVault, router, initHash);
    }

    /*
        Helper functions used for testing, these should be done off-chain in production
    */

    /**
     * @notice Get the parameters required for the migration
     * @param _amount amount of LP tokens to migrate
     * @param _stakeBpt whether to stake the BPT in the Aura pool
     */
    function getMigrationParams(
        uint256 _amount,
        bool _stakeBpt
    ) internal view returns (IMigrator.MigrationParams memory) {
        // Calculate min amount of Token and WETH from LP
        (uint256 amountTokenMin, uint256 amountWethMin) = calculateLpAmounts(_amount);
        // Calculate amount of WETH given amount of Token to create 80/20 TOKEN/WETH balance
        uint256 wethRequired = calculateWethRequired(amountTokenMin);
        // Calculate amount of Tokens out given the excess amount of WETH due to 80/20 TOKEN/WETH rebalance (amountWethMin is always > wethRequired)
        uint256 minAmountTokenOut = calculateTokenAmountOut(amountWethMin - wethRequired);
        // Calculate amount of BPT out given Tokens and WETH (add original and predicted swapped amounts of companion token)
        uint256 amountBptOut = calculateBptAmountOut(amountTokenMin + minAmountTokenOut, wethRequired);
        // Calculate amount of auraBPT out given BPT
        uint256 amountAuraBptOut = calculateAuraBptAmountOut(amountBptOut);

        IMigrator.MigrationParams memory migrationParams = IMigrator.MigrationParams({
            balancerPoolToken:          balancerPoolToken,
            auraPool:                   auraPool,
            poolTokensIn:               _amount,
            amountCompanionMinimumOut:  amountTokenMin,
            amountWETHMinimumOut:       amountWethMin,
            wethRequired:               wethRequired,
            minAmountTokenOut:          minAmountTokenOut,
            amountBalancerLiquidityOut: amountBptOut,
            amountAuraSharesMinimum:    amountAuraBptOut,
            stake:                      _stakeBpt
        });

        return migrationParams;
    }

    /**
     * @notice Calculate the min amount of TOKEN and WETH for a given LP amount
     * @param _lpAmount The amount of LP
     * @return Return values for min amount out of TOKEN and WETH with unwrap slippage
     * @dev Calculation used for testing, in production values should be calculated in UI
     */
    function calculateLpAmounts(uint256 _lpAmount) internal view returns (uint256, uint256) {
        uint256 tokenPriceEth = tokenPrice();
        uint256 wethPriceUsd = wethPrice();
        uint256 lpSupply = lpToken.totalSupply();
        (uint256 wethReserves, uint256 tokenReserves, ) = lpToken.getReserves();

        // Convert reserves into current USD price
        uint256 tokenReservesUsd = ((tokenReserves * tokenPriceEth) * wethPriceUsd) / 1 ether;
        uint256 wethReservesUsd = wethReserves * wethPriceUsd;

        // Get amounts in USD given the amount of LP with slippage
        uint256 amountTokenUsd = (((_lpAmount * tokenReservesUsd) / lpSupply) * (BPS - slippage)) / BPS;
        uint256 amountWethUsd = (((_lpAmount * wethReservesUsd) / lpSupply) * (BPS - slippage)) / BPS;

        // Return tokens denominated in ETH
        uint256 amountTokenMin = (amountTokenUsd * 1 ether) / (tokenPriceEth * wethPriceUsd);
        uint256 amountWethMin = (amountWethUsd) / wethPriceUsd;

        return (amountTokenMin, amountWethMin);
    }

    /**
     * @notice Given an amount of a companion token, calculate the amount of WETH to create an 80/20 TOKEN/WETH ratio
     * @param _tokenAmount Amount of Token
     */
    function calculateWethRequired(uint256 _tokenAmount) internal view returns (uint256) {
        uint256[] memory normalizedWeights = IManagedPool(address(balancerPoolToken)).getNormalizedWeights();

        return (((_tokenAmount * tokenPrice()) / 1 ether) * normalizedWeights[0]) / normalizedWeights[1];
    }

    /**
     * @notice Min amount of Token swapped for WETH
     * @param _wethAmount Amount of WETH to swap
     * @dev This is the excess WETH after we know expected rebalanced 80/20 amounts
     */
    function calculateTokenAmountOut(uint256 _wethAmount) internal view returns (uint256) {
        uint256 minAmountTokenOut = ((((_wethAmount * tokenPrice()) / (1 ether)) * (BPS - slippage)) / BPS);

        return minAmountTokenOut;
    }

    /**
     * @notice Given an amount of tokens in, calculate the expected BPT out
     * @param _wethAmountIn Amount of WETH
     * @param _tokenAmountIn Amount of Token
     */
    function calculateBptAmountOut(uint256 _tokenAmountIn, uint256 _wethAmountIn) internal view returns (uint256) {
        bytes32 balancerPoolId = balancerPoolToken.getPoolId();

        (, uint256[] memory balances, ) = IVault(balancerVault).getPoolTokens(balancerPoolId);
        uint256[] memory normalizedWeights = IManagedPool(address(balancerPoolToken)).getNormalizedWeights();

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = _wethAmountIn;
        amountsIn[1] = _tokenAmountIn;

        uint256 amountOut = (
            WeightedMath._calcBptOutGivenExactTokensIn(
                balances,
                normalizedWeights,
                amountsIn,
                ERC20(address(balancerPoolToken)).totalSupply(),
                balancerPoolToken.getSwapFeePercentage()
            )
        );

        return amountOut;
    }

    /**
     * @notice Given an amount of BPT in, calculate the expected auraBPT out
     * @param _bptAmountIn Amount of BPT
     */
    function calculateAuraBptAmountOut(uint256 _bptAmountIn) internal view returns (uint256) {
        uint256 amountOut = IRewardPool4626(address(auraPool)).previewDeposit(_bptAmountIn);

        return amountOut;
    }

    /**
     * @notice Get the price of WETH
     * @dev Make sure price is not stale or incorrect
     * @return Return the correct price
     */
    function wethPrice() internal view returns (uint256) {
        (uint80 roundId, int256 price, , uint256 timestamp, uint80 answeredInRound) = wethPriceFeed.latestRoundData();

        require(answeredInRound >= roundId, "Stale price");
        require(timestamp != 0, "Round not complete");
        require(price > 0, "Chainlink answer reporting 0");

        return uint256(price);
    }

    /**
     * @notice Get the price of a companion token
     * @dev Make sure price is not stale or incorrect
     * @return Return the correct price
     */
    function tokenPrice() internal view returns (uint256) {
        (uint80 roundId, int256 price, , uint256 timestamp, uint80 answeredInRound) = tokenPriceFeed.latestRoundData();

        require(answeredInRound >= roundId, "Stale price");
        require(timestamp != 0, "Round not complete");
        require(price > 0, "Chainlink answer reporting 0");

        return uint256(price);
    }

    /**
     * @notice Get the UniV2 pool and companion token addresses for a given balancer pool
     * @param balancerToken Address of the balancer pool token
     */
    function getPairAddress(address balancerToken) internal view returns (IUniswapV2Pair, ERC20) {
        bytes32 poolId = IBasePool(balancerToken).getPoolId();
        (IERC20[] memory balancerPoolTokens /* uint256[] memory balances */ /* uint256 lastChangeBlock */, , ) = IVault(
            balancerVault
        ).getPoolTokens(poolId);

        IERC20 companion;
        if (balancerPoolTokens[0] == IERC20(address(weth))) {
            companion = balancerPoolTokens[1];
        } else if (balancerPoolTokens[1] == IERC20(address(weth))) {
            companion = balancerPoolTokens[0];
        } else {
            // If neither token is WETH, then the migration will fail
            revert("Balancer pool must contain WETH");
        }

        address tokenA = address(companion);
        address tokenB = address(weth);

        // Sort the tokens
        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }

        address factory = address(IUniswapV2Factory(IUniswapV2Router02(router).factory()));
        address poolToken = IUniswapV2Factory(factory).getPair(tokenA, tokenB);

        // Get the expected pool address
        address expectedPoolAddress = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            factory,
            keccak256(abi.encodePacked(tokenA, tokenB)),
            initHash
        )))));

        // Verify the pool address
        require(expectedPoolAddress == poolToken, "Pool address verification failed");

        return (IUniswapV2Pair(poolToken), ERC20(address(companion)));
    }
}
