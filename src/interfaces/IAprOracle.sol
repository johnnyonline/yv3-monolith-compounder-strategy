// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface IAprOracle {

    /// @notice Register a strategy-specific APR oracle in the central AprOracle
    /// @param _strategy The strategy to set the oracle for
    /// @param _oracle The APR oracle contract
    function setOracle(
        address _strategy,
        address _oracle
    ) external;

    function oracles(
        address _strategy
    ) external view returns (address);

    function getStrategyApr(
        address _strategy,
        int256 _debtChange
    ) external view returns (uint256);

}
