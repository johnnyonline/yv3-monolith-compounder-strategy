// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseHealthCheck} from "@periphery/Bases/HealthCheck/IBaseHealthCheck.sol";

interface IStrategyInterface is IBaseHealthCheck {

    // ===============================================================
    // Views
    // ===============================================================

    function STAKING() external view returns (address);

    function REWARDS_TOKEN() external view returns (address);

    function AUCTION_FACTORY() external view returns (address);

    function auction() external view returns (address);

    function minAmountToSell(
        address _token
    ) external view returns (uint256);

    function balanceOfAsset() external view returns (uint256);

    function balanceOfStake() external view returns (uint256);

    function balanceOfRewards() external view returns (uint256);

    function claimableRewards() external view returns (uint256);

    // ===============================================================
    // Management
    // ===============================================================

    function setMinAmountToSell(
        address _token,
        uint256 _minAmountToSell
    ) external;

    function enableAuctionToken(
        address _token,
        uint256 _minAmountToSell
    ) external;

    function setMinimumAuctionPrice(
        uint256 _minimumPrice
    ) external;

    function setAuctionStartingPrice(
        uint256 _startingPrice
    ) external;

    function setAuctionStepDecayRate(
        uint256 _stepDecayRate
    ) external;

    function delegate(
        address _delegatee
    ) external;

    // ===============================================================
    // Keepers
    // ===============================================================

    function claimRewards() external;

    function kickAuction(
        address _token
    ) external;

}
