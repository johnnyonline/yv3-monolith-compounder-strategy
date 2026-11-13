// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface ICommonReportTrigger {

    /// @notice Set a custom report trigger contract for a strategy
    /// @param _strategy The strategy to set the trigger for
    /// @param _trigger The custom trigger contract
    function setCustomStrategyTrigger(
        address _strategy,
        address _trigger
    ) external;

    function customStrategyTrigger(
        address _strategy
    ) external view returns (address);

    function strategyReportTrigger(
        address _strategy
    ) external view returns (bool, bytes memory);

    function vaultReportTrigger(
        address _vault,
        address _strategy
    ) external view returns (bool, bytes memory);

}
