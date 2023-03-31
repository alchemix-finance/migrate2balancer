// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "lib/forge-std/src/console2.sol";
import "./utils/DSTestPlus.sol";
import "src/factories/MigratorFactory.sol";
import "src/interfaces/chainlink/AggregatorV3Interface.sol";
import "src/interfaces/balancer/IManagedPool.sol";
import "src/interfaces/balancer/WeightedMath.sol";

contract BaseTest is DSTestPlus {
    Migrator public migrator;
    MigratorFactory public migratorFactory;

    // Initialization parameters
    WETH public weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    ERC20 public token = ERC20(0xdBdb4d16EdA451D0503b854CF79D55697F90c8DF);
    ERC20 public balancerPoolToken = ERC20(0xf16aEe6a71aF1A9Bc8F56975A4c2705ca7A782Bc);
    ERC20 public auraDepositToken = ERC20(0x8B227E3D50117E80a02cd0c67Cd6F89A8b7B46d7);
    IUniswapV2Pair public sushiLpToken = IUniswapV2Pair(0xC3f279090a47e80990Fe3a9c30d24Cb117EF91a8);
    IUniswapV2Router02 public sushiRouter = IUniswapV2Router02(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);
    IVault public balancerVault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    // Test variables
    address public user;
    uint256 public userPrivateKey = 0xBEEF;
    uint256 public slippage = 10;
    uint256 public BPS = 10000;
    AggregatorV3Interface public wethPrice = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    AggregatorV3Interface public tokenPrice = AggregatorV3Interface(0x194a9AaF2e0b67c35915cD01101585A33Fe25CAa);

    IMigrator.InitializationParams public params =
        IMigrator.InitializationParams(
            address(weth),
            address(token),
            address(balancerPoolToken),
            address(sushiLpToken),
            address(auraDepositToken),
            address(sushiRouter),
            address(balancerVault)
        );

    /**
     * @notice Deploy MigratorFactory and create first Migrator
     */
    function setUp() public {
        user = hevm.addr(userPrivateKey);

        migratorFactory = new MigratorFactory();

        migrator = Migrator(payable(migratorFactory.createMigrator(params)));
    }

    /*
        Helper functions (only used for testing, should be done off-chain in UI)
    */

    /**
     * @notice All parameters that need to be calculated off-chain
     * @param _amount Amount of SLP tokens
     * @return amountTokenMin
     * @return amountWethMin
     * @return wethRequired
     * @return minAmountTokenOut
     * @return amountBptOut
     */
    function offChainParams(uint256 _amount) public view returns (uint256, uint256, uint256, uint256, uint256) {
        // Calculate min amount of Token and WETH from SLP
        (uint256 amountTokenMin, uint256 amountWethMin) = _calculateSlpAmounts(_amount);
        // Calculate amount of WETH given amount of Token to create 80/20 TOKEN/WETH balance
        uint256 wethRequired = _calculateWethRequired(amountTokenMin);
        // Calculate amount of Token out given the excess amount of WETH since we are rebalancing to 80/20 Token/WETH (amountWethMin is always > wethRequired)
        uint256 minAmountTokenOut = _calculateTokenAmountOut(amountWethMin - wethRequired);
        // Calculate amount of BPT out given Tokens and WETH (add original and predicted swapped amounts of token)
        uint256 amountBptOut = _calculateBptAmountOut(amountTokenMin + minAmountTokenOut, wethRequired);

        return (amountTokenMin, amountWethMin, wethRequired, minAmountTokenOut, amountBptOut);
    }

    /**
     * @notice Calculate the min amount of TOKEN and WETH for a given SLP amount
     * @param _slpAmount The amount of SLP
     * @return Return values for min amount out of TOKEN and WETH with unwrap slippage
     * @dev Calculation used for testing, in production values should be calculated in UI
     */
    function _calculateSlpAmounts(uint256 _slpAmount) internal view returns (uint256, uint256) {
        uint256 tokenPriceEth = _tokenPrice();
        uint256 wethPriceUsd = _wethPrice();
        uint256 slpSupply = sushiLpToken.totalSupply();
        (uint256 wethReserves, uint256 tokenReserves, ) = sushiLpToken.getReserves();

        // Convert reserves into current USD price
        uint256 tokenReservesUsd = ((tokenReserves * tokenPriceEth) * wethPriceUsd) / 1 ether;
        uint256 wethReservesUsd = wethReserves * wethPriceUsd;

        // Get amounts in USD given the amount of SLP with slippage
        uint256 amountTokenUsd = (((_slpAmount * tokenReservesUsd) / slpSupply) * (BPS - slippage)) / BPS;
        uint256 amountWethUsd = (((_slpAmount * wethReservesUsd) / slpSupply) * (BPS - slippage)) / BPS;

        // Return tokens denominated in ETH
        uint256 amountTokenMin = (amountTokenUsd * 1 ether) / (tokenPriceEth * wethPriceUsd);
        uint256 amountWethMin = (amountWethUsd) / wethPriceUsd;

        return (amountTokenMin, amountWethMin);
    }

    /**
     * @notice Given an amount of a token, calculate the amount of WETH to create an 80/20 TOKEN/WETH ratio
     * @param _tokenAmount Amount of Token
     */
    function _calculateWethRequired(uint256 _tokenAmount) internal view returns (uint256) {
        uint256[] memory normalizedWeights = IManagedPool(address(balancerPoolToken)).getNormalizedWeights();

        return (((_tokenAmount * _tokenPrice()) / 1 ether) * normalizedWeights[0]) / normalizedWeights[1];
    }

    /**
     * @notice Min amount of Token swapped for WETH
     * @param _wethAmount Amount of WETH to swap
     * @dev This is the excess WETH after we know expected rebalanced 80/20 amounts
     */
    function _calculateTokenAmountOut(uint256 _wethAmount) internal view returns (uint256) {
        uint256 minAmountTokenOut = ((((_wethAmount * _tokenPrice()) / (1 ether)) * (BPS - slippage)) / BPS);

        return minAmountTokenOut;
    }

    /**
     * @notice Given an amount of tokens in, calculate the expected BPT out
     * @param _wethAmountIn Amount of WETH
     * @param _tokenAmountIn Amount of Token
     */
    function _calculateBptAmountOut(uint256 _tokenAmountIn, uint256 _wethAmountIn) internal view returns (uint256) {
        bytes32 balancerPoolId = IBasePool(address(balancerPoolToken)).getPoolId();
        (, uint256[] memory balances, ) = balancerVault.getPoolTokens(balancerPoolId);
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
                IBasePool(address(balancerPoolToken)).getSwapFeePercentage()
            )
        );

        return amountOut;
    }

    /**
     * @notice Get the price of weth
     * @dev Make sure price is not stale or incorrect
     * @return Return the correct price
     */
    function _wethPrice() internal view returns (uint256) {
        (uint80 roundId, int256 price, , uint256 timestamp, uint80 answeredInRound) = wethPrice.latestRoundData();

        require(answeredInRound >= roundId, "Stale price");
        require(timestamp != 0, "Round not complete");
        require(price > 0, "Chainlink answer reporting 0");

        return uint256(price);
    }

    /**
     * @notice Get the price of a token
     * @dev Make sure price is not stale or incorrect
     * @return Return the correct price
     */
    function _tokenPrice() internal view returns (uint256) {
        (uint80 roundId, int256 price, , uint256 timestamp, uint80 answeredInRound) = tokenPrice.latestRoundData();

        require(answeredInRound >= roundId, "Stale price");
        require(timestamp != 0, "Round not complete");
        require(price > 0, "Chainlink answer reporting 0");

        return uint256(price);
    }
}
