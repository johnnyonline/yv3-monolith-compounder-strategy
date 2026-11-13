// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import "../../../script/Deploy.s.sol";

import {ERC20} from "../../Strategy.sol";
import {Auction} from "@periphery/Auctions/Auction.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {IStakedGovToken} from "../../interfaces/IStakedGovToken.sol";
import {IRevenueRouter} from "../../interfaces/IMonolith.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {

    function governance() external view returns (address);

    function set_protocol_fee_bps(
        uint16
    ) external;

    function set_protocol_fee_recipient(
        address
    ) external;

}

interface IFixedReportTrigger {

    function setMinReportDelay(
        address _strategy,
        uint256 _minReportDelay
    ) external;

    function getReportDelay(
        address _strategy
    ) external view returns (uint256);

}

contract Setup is Deploy, Test, IEvents {

    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    ERC20 public rewardsToken;
    IStrategyInterface public strategy;
    IStakedGovToken public staking;
    StrategyFactory public strategyFactory;
    IVault public vault;
    MonolithSwanAprOracle public oracle;
    Auction public auction;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);
    address public taker = address(6);

    // Address of the real deployed Factory
    address public factory;

    // Sends revenue to the staked gov token
    address public revenueRouter;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Takers wait for the auction to come down to about the market price, in SWAN per swanUSD
    uint256 public marketPrice = 3e18;

    // Fuzz from 10k SWAN up to 1M SWAN. ~230k SWAN is staked at the fork block
    uint256 public maxFuzzAmount = 1_000_000e18;
    uint256 public minFuzzAmount = 10_000e18;

    function setUp() public virtual {
        uint256 _blockNumber = 26_391_500; // Caching for faster tests
        vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), _blockNumber));

        _setTokenAddrs();

        // Set asset
        asset = ERC20(tokenAddrs["SWAN"]);
        rewardsToken = ERC20(tokenAddrs["swanUSD"]);

        // Set decimals
        decimals = asset.decimals();

        // Flush pending revenue so tests control what the strategy earns
        revenueRouter = IStakedGovToken(SSWAN).revenueRouter();
        IRevenueRouter(revenueRouter).distribute();

        // Set script vars
        s_management = management;
        s_performanceFeeRecipient = performanceFeeRecipient;
        s_keeper = keeper;
        s_emergencyAdmin = emergencyAdmin;
        s_roleManager = management;

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        factory = strategy.FACTORY();
        strategyFactory = s_factory;
        vault = s_vault;
        oracle = s_oracle;
        auction = Auction(strategy.auction());
        staking = IStakedGovToken(strategy.STAKING());

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(strategyFactory), "strategyFactory");
        vm.label(address(vault), "vault");
        vm.label(address(oracle), "oracle");
        vm.label(address(auction), "auction");
        vm.label(address(asset), "asset");
        vm.label(address(rewardsToken), "rewardsToken");
        vm.label(address(staking), "staking");
        vm.label(revenueRouter, "revenueRouter");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
        vm.label(taker, "taker");
    }

    function setUpStrategy() public returns (address) {
        // notify deployment script that this is a test
        isTest = true;
        // deploy and initialize contracts
        run();
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = s_newStrategy;

        vm.startPrank(management);
        _strategy.acceptManagement();
        // Only the vault can deposit, let `user` in too to test the strategy directly
        _strategy.setAllowed(user, true);
        vm.stopPrank();

        return address(_strategy);
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // Distribute enough revenue to the staked gov token for the strategy to earn ~`_rewards`
    function earn(
        uint256 _rewards
    ) public {
        airdrop(rewardsToken, revenueRouter, _rewards * staking.totalSupply() / strategy.balanceOfStake());
        IRevenueRouter(revenueRouter).distribute();
    }

    // Taker waits for about the market price, then buys the whole lot paying `asset` to the strategy
    function take() public returns (uint256 _paid) {
        while (auction.price(address(rewardsToken)) > marketPrice) skip(1 hours);
        _paid = auction.getAmountNeeded(address(rewardsToken));
        airdrop(asset, taker, _paid);
        vm.startPrank(taker);
        asset.approve(address(auction), _paid);
        auction.take(address(rewardsToken));
        vm.stopPrank();
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(address(_strategy));
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(
        ERC20 _asset,
        address _to,
        uint256 _amount
    ) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(
        uint16 _protocolFee,
        uint16 _performanceFee
    ) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["SWAN"] = 0xD0a32F6d4850F9D6DF7d4F8f84af1Fcd3Cf993CC;
        tokenAddrs["swanUSD"] = 0x9BF2B2F57A2968A0E81546Ed50cBbbb7C9d6e05E;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    }

}
