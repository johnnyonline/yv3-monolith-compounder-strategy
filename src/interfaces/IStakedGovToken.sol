// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

/// @notice Monolith CoinDAO staked governance token (e.g. sSWAN)
interface IStakedGovToken {

    function underlying() external view returns (address);

    function rewardsToken() external view returns (address);

    function revenueRouter() external view returns (address);

    function rewardPerToken() external view returns (uint256);

    function balanceOf(
        address _account
    ) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function earned(
        address _account
    ) external view returns (uint256);

    function delegates(
        address _account
    ) external view returns (address);

    function getVotes(
        address _account
    ) external view returns (uint256);

    function depositFor(
        address _account,
        uint256 _value
    ) external returns (bool);

    function withdrawTo(
        address _account,
        uint256 _value
    ) external returns (bool);

    function getReward() external;

    function harvestAndGetReward() external;

    function delegate(
        address _delegatee
    ) external;

}
