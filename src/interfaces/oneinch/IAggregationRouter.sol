// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

interface IAggregationRouter {
    struct SwapDescription {
        IERC20 srcToken;
        IERC20 dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }
}
