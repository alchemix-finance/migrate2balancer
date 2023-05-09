// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.19;

import "./utils/DSTestPlus.sol";
import "./utils/MigrationCalcs.sol";
import "lib/forge-std/src/console2.sol";

import "src/Migrator.sol";
import "src/interfaces/balancer/IManagedPool.sol";
import "src/interfaces/balancer/WeightedMath.sol";
import "src/interfaces/chainlink/AggregatorV3Interface.sol";

contract BaseTest is DSTestPlus {
    Migrator public migrator;
    MigrationCalcs public migrationCalcs;

    address public user;
    uint256 public userPrivateKey = 0xBEEF;
    uint256 public slippage = 10;
    uint256 public BPS = 10000;

    ERC20 public companionToken;
    IUniswapV2Pair public poolToken;

    IBasePool public balancerPoolToken = IBasePool(0xf16aEe6a71aF1A9Bc8F56975A4c2705ca7A782Bc);
    IRewardPool4626 public auraPool = IRewardPool4626(0x8B227E3D50117E80a02cd0c67Cd6F89A8b7B46d7);
    AggregatorV3Interface public wethPriceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    AggregatorV3Interface public tokenPriceFeed = AggregatorV3Interface(0x194a9AaF2e0b67c35915cD01101585A33Fe25CAa);

    // Constructor parameters
    ERC20 public weth = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public balancerVault = address(balancerPoolToken.getVault());
    address public router = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    
    function setUp() public {
        user = hevm.addr(userPrivateKey);

        // Get the UniV2 pool and companion token addresses given any balancer pool token
        (poolToken, companionToken) = getPairAddress(balancerPoolToken);
        
        migrationCalcs = new MigrationCalcs();

        migrator = new Migrator(address(weth), balancerVault, router);
    }

    /**
     * @notice Get the migration calculation parameters for a given migration
     * @param stakeBpt Whether to stake BPT or not
     * @param amount Amount of UniV2 LP tokens to migrate
     */
    function getMigrationCalcParams(bool stakeBpt, uint256 amount) internal view returns (MigrationCalcs.MigrationCalcParams memory) {
        MigrationCalcs.MigrationCalcParams memory migrationCalcParams = MigrationCalcs.MigrationCalcParams({
            stakeBpt:           stakeBpt,
            amount:             amount,
            slippage:           slippage,
            poolToken:          poolToken,
            balancerPoolToken:  balancerPoolToken,
            auraPool:           auraPool,
            wethPriceFeed:      wethPriceFeed,
            tokenPriceFeed:     tokenPriceFeed
        });

        return migrationCalcParams;
    }

    /**
     * @notice Get the UniV2 pool and companion token addresses for a given balancer pool
     * @param balancerToken Address of the balancer pool token
     */
    function getPairAddress(IBasePool balancerToken) internal view returns (IUniswapV2Pair, ERC20) {
        bytes32 poolId = balancerToken.getPoolId();
        (IERC20[] memory balancerPoolTokens, , ) = IVault(balancerVault).getPoolTokens(poolId);

        IERC20 companion;
        if (balancerPoolTokens[0] == IERC20(address(weth))) {
            companion = balancerPoolTokens[1];
        } else if (balancerPoolTokens[1] == IERC20(address(weth))) {
            companion = balancerPoolTokens[0];
        } else {
            // If neither token is WETH, then the migration will fail
            revert("Balancer pool must contain WETH");
        }

        address factory = address(IUniswapV2Factory(IUniswapV2Router02(router).factory()));
        address expectedPoolToken = IUniswapV2Factory(factory).getPair(address(companion), address(weth));

        // Validate the pool address
        require(expectedPoolToken != address(0), "Pool address verification failed");

        return (IUniswapV2Pair(expectedPoolToken), ERC20(address(companion)));
    }
}
