// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "./utils/DSTestPlus.sol";
import "src/Migrator.sol";
import "src/interfaces/IMigrator.sol";

contract BaseTest is DSTestPlus {
    Migrator public migrator;

    // Initialization params
    uint256 public alchemixPoolId = 2;
    uint256 public sushiPoolId = 0;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public alcx = 0xdBdb4d16EdA451D0503b854CF79D55697F90c8DF;
    address public sushi = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
    address public bpt = 0xf16aEe6a71aF1A9Bc8F56975A4c2705ca7A782Bc;
    address public slp = 0xC3f279090a47e80990Fe3a9c30d24Cb117EF91a8;
    address public auraPool = 0x8B227E3D50117E80a02cd0c67Cd6F89A8b7B46d7;
    address public alchemixStakingPool = 0xAB8e74017a8Cc7c15FFcCd726603790d26d7DeCa;
    address public sushiStakingPool = 0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d;
    address public priceFeed = 0x194a9AaF2e0b67c35915cD01101585A33Fe25CAa;
    address public sushiRouter = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    function setUp() public {
        IMigrator.InitializationParams memory params = IMigrator.InitializationParams(
            alchemixPoolId,
            sushiPoolId,
            weth,
            alcx,
            sushi,
            bpt,
            slp,
            auraPool,
            alchemixStakingPool,
            sushiStakingPool,
            priceFeed,
            sushiRouter,
            balancerVault
        );

        migrator = new Migrator(params);
    }
}
