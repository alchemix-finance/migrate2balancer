// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.7.0 <0.9.0;

import "./IVault.sol";

interface IBalancerPoolToken {
    function getVault() external view returns (IVault);
}
