// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import {MonolithCompounder as Strategy} from "./Strategy.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract StrategyFactory {

    event NewStrategy(address indexed strategy, address indexed asset);

    address public immutable emergencyAdmin;
    address public immutable management;
    address public immutable performanceFeeRecipient;
    address public immutable keeper;

    /// @notice Track the deployments. asset => strategy
    mapping(address => address) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }

    modifier onlyManagement() {
        require(msg.sender == management, "!management");
        _;
    }

    /**
     * @notice Deploy a new Strategy.
     * @param _asset The gov token for the strategy to use.
     * @param _name The name of the strategy.
     * @param _staking The staked gov token.
     * @return . The address of the new strategy.
     */
    function newStrategy(
        address _asset,
        string calldata _name,
        address _staking
    ) external virtual onlyManagement returns (address) {
        // tokenized strategies available setters.
        IStrategyInterface _newStrategy = IStrategyInterface(address(new Strategy(_asset, _name, _staking)));

        _newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        _newStrategy.setKeeper(keeper);

        _newStrategy.setPendingManagement(management);

        _newStrategy.setEmergencyAdmin(emergencyAdmin);

        emit NewStrategy(address(_newStrategy), _asset);

        deployments[_asset] = address(_newStrategy);
        return address(_newStrategy);
    }

}
