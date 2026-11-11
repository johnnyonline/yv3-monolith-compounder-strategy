// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

/// @notice Monolith CoinDAO revenue router
interface IRevenueRouter {

    function lender() external view returns (address);

    function govStakingBps() external view returns (uint16);

    function distribute() external returns (uint256, uint256);

}

/// @notice Monolith market
interface IMonolithLender {

    function coin() external view returns (address);

    function vault() external view returns (address);

    function psmVault() external view returns (address);

    function psmAssetDecimals() external view returns (uint256);

    function freePsmAssets() external view returns (uint256);

    function totalPaidDebt() external view returns (uint256);

    function lastBorrowRateMantissa() external view returns (uint88);

    function feeBps() external view returns (uint16);

    function cachedGlobalFeeBps() external view returns (uint16);

}
