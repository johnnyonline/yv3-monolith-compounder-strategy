// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

contract OperationTest is Setup {

    function setUp() public virtual override {
        super.setUp();
    }

    function test_setupStrategyOK() public {
        console2.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        assertEq(strategy.emergencyAdmin(), emergencyAdmin);
        assertEq(strategy.profitMaxUnlockTime(), 0);
        assertEq(strategy.performanceFee(), 0);
        assertFalse(strategy.open());
        assertTrue(strategy.allowed(address(vault)));
        assertEq(strategy.maxDeposit(address(vault)), type(uint256).max);
        assertEq(strategy.maxDeposit(address(69)), 0);
        assertEq(strategyFactory.deployments(address(asset)), address(strategy));
        assertEq(strategy.STAKING(), SSWAN);
        assertEq(staking.underlying(), address(asset));
        assertEq(strategy.REWARDS_TOKEN(), address(rewardsToken));
        assertEq(strategy.minAmountToSell(address(rewardsToken)), 100e18);
        assertEq(asset.allowance(address(strategy), address(staking)), type(uint256).max);

        // Own auction, selling rewards for `asset` to the strategy
        assertEq(strategy.AUCTION_FACTORY(), 0x55B3830B4D85e6868c73f00A2e857e9AdbF89568);
        assertEq(auction.want(), address(asset));
        assertEq(auction.receiver(), address(strategy));
        assertEq(auction.governance(), address(strategy));
        assertTrue(auction.governanceOnlyKick());
        (, uint64 _scaler,) = auction.auctions(address(rewardsToken));
        assertEq(_scaler, 1, "!enabled");
        assertEq(auction.startingPrice(), 100_000e18);
        assertEq(auction.minimumPrice(), 1e18);
        assertEq(auction.stepDecayRate(), 50);
    }

    function test_newStrategy() public {
        // Only the factory's management can deploy
        vm.prank(user);
        vm.expectRevert("!management");
        strategyFactory.newStrategy(address(asset), "Test", address(staking));

        // The staked gov token must wrap `asset`
        vm.prank(strategyFactory.management());
        vm.expectRevert("!staking");
        strategyFactory.newStrategy(address(rewardsToken), "Test", address(staking));
    }

    function test_operation(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertEq(strategy.balanceOfStake(), _amount, "!staked");
        assertEq(strategy.balanceOfAsset(), 0, "!idle");

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function test_profitableReport(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn ~2% in rewards
        uint256 _rewards = _amount / 50;
        earn(_rewards);
        assertApproxEqRel(strategy.claimableRewards(), _rewards, 1e15, "!claimable");

        // Report claims the rewards and kicks them
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");
        assertEq(strategy.claimableRewards(), 0, "!claimable");
        assertEq(strategy.balanceOfRewards(), 0, "!rewards");
        assertApproxEqRel(auction.available(address(rewardsToken)), _rewards, 1e15, "!kicked");

        // Taker pays `asset` to the strategy
        uint256 _paid = take();
        assertEq(strategy.balanceOfAsset(), _paid, "!paid");

        // Next report books and restakes it. SWAN is worth less than swanUSD
        vm.prank(keeper);
        (profit, loss) = strategy.report();

        assertEq(profit, _paid, "!profit");
        assertGt(profit, _rewards, "!profit");
        assertEq(loss, 0, "!loss");
        assertEq(strategy.balanceOfAsset(), 0, "!idle");
        assertEq(strategy.balanceOfStake(), _amount + profit, "!staked");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGt(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function test_profitableReport_withFees(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Set protocol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn ~2% in rewards, kick and sell them
        earn(_amount / 50);
        vm.prank(keeper);
        strategy.report();
        uint256 _paid = take();

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertEq(profit, _paid, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee. Profit isn't locked, so fee shares are priced after it
        uint256 expectedFee = (profit * 1_000) / MAX_BPS;
        uint256 expectedShares = strategy.balanceOf(performanceFeeRecipient);

        assertApproxEqAbs(expectedShares, strategy.convertToShares(expectedFee), 1, "!fee shares");

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        vm.prank(performanceFeeRecipient);
        strategy.redeem(expectedShares, performanceFeeRecipient, performanceFeeRecipient);

        checkStrategyTotals(strategy, 0, 0, 0);

        assertApproxEqAbs(asset.balanceOf(performanceFeeRecipient), expectedFee, 2, "!perf fee out");
    }

    function test_report_belowMinAmountToSell(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Earn less than the min amount to sell
        uint256 _minAmountToSell = strategy.minAmountToSell(address(rewardsToken));
        earn(_minAmountToSell / 2);

        // Report claims but doesn't kick
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");
        assertApproxEqRel(strategy.balanceOfRewards(), _minAmountToSell / 2, 1e15, "!rewards");
        assertEq(rewardsToken.balanceOf(address(auction)), 0, "!auction");

        // Earn some more
        earn(_minAmountToSell);

        // Report kicks it all
        vm.prank(keeper);
        strategy.report();

        assertEq(strategy.balanceOfRewards(), 0, "!rewards");
        assertApproxEqRel(auction.available(address(rewardsToken)), _minAmountToSell * 3 / 2, 1e15, "!kicked");
    }

    function test_claimRewards(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Earn some rewards
        earn(1_000e18);

        vm.prank(user);
        vm.expectRevert("!keeper");
        strategy.claimRewards();

        vm.prank(keeper);
        strategy.claimRewards();

        assertApproxEqRel(strategy.balanceOfRewards(), 1_000e18, 1e15, "!rewards");
        assertEq(strategy.claimableRewards(), 0, "!claimable");
    }

    function test_delegate(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Delegated to the deployer on deployment
        address _deployer = vm.addr(42069);
        assertEq(staking.delegates(address(strategy)), _deployer, "!delegates");

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(staking.getVotes(_deployer), _amount, "!votes");

        vm.prank(user);
        vm.expectRevert("!management");
        strategy.delegate(user);

        // Management can redelegate
        vm.prank(management);
        strategy.delegate(management);

        assertEq(staking.delegates(address(strategy)), management, "!delegates");
        assertEq(staking.getVotes(management), _amount, "!votes");
        assertEq(staking.getVotes(_deployer), 0, "!votes");
    }

    function test_setMinAmountToSell(
        uint256 _minAmountToSell
    ) public {
        vm.prank(user);
        vm.expectRevert("!management");
        strategy.setMinAmountToSell(address(rewardsToken), _minAmountToSell);

        vm.prank(management);
        strategy.setMinAmountToSell(address(rewardsToken), _minAmountToSell);

        assertEq(strategy.minAmountToSell(address(rewardsToken)), _minAmountToSell);
    }

    function test_tendTrigger(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(keeper);
        strategy.report();

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);
    }

}
