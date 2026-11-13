// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, ERC20} from "./utils/Setup.sol";

contract AuctionTest is Setup {

    function setUp() public virtual override {
        super.setUp();
    }

    function test_kickAuction(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Earn ~2% in rewards
        uint256 _rewards = _amount / 50;
        earn(_rewards);

        vm.prank(user);
        vm.expectRevert("!keeper");
        strategy.kickAuction(address(rewardsToken));

        // Keeper claims and kicks without a report
        vm.prank(keeper);
        strategy.kickAuction(address(rewardsToken));

        assertEq(strategy.claimableRewards(), 0, "!claimable");
        assertEq(strategy.balanceOfRewards(), 0, "!rewards");
        assertApproxEqRel(auction.available(address(rewardsToken)), _rewards, 1e15, "!kicked");

        // Can't sell `asset`
        airdrop(asset, address(strategy), 1e18);
        vm.prank(keeper);
        vm.expectRevert("!asset");
        strategy.kickAuction(address(asset));
    }

    function test_kickAuction_belowMinAmountToSell(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Earn less than the min amount to sell
        earn(strategy.minAmountToSell(address(rewardsToken)) / 2);

        // Claims but doesn't kick
        vm.prank(keeper);
        strategy.kickAuction(address(rewardsToken));

        assertGt(strategy.balanceOfRewards(), 0, "!rewards");
        assertEq(rewardsToken.balanceOf(address(auction)), 0, "!auction");
    }

    function test_kickAuction_relist(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Report kicks the first lot
        uint256 _rewards = _amount / 50;
        earn(_rewards);
        vm.prank(keeper);
        strategy.report();

        // Report claims the second lot but can't add it to the live auction
        earn(_rewards);
        vm.prank(keeper);
        strategy.report();

        assertApproxEqRel(strategy.balanceOfRewards(), _rewards, 1e15, "!rewards");
        assertApproxEqRel(auction.available(address(rewardsToken)), _rewards, 1e15, "!live");

        // First lot goes unsold
        skip(1 days + 1);
        assertFalse(auction.isActive(address(rewardsToken)), "!ended");

        // Keeper relists both lots, plus whatever it claims on the way
        uint256 _lots = strategy.balanceOfRewards() + rewardsToken.balanceOf(address(auction));
        vm.prank(keeper);
        strategy.kickAuction(address(rewardsToken));

        assertEq(strategy.balanceOfRewards(), 0, "!rewards");
        assertGe(auction.available(address(rewardsToken)), _lots, "!kicked");
    }

    function test_kickAuction_relistUnsold(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Report kicks a lot
        earn(_amount / 50);
        vm.prank(keeper);
        strategy.report();
        uint256 _lot = rewardsToken.balanceOf(address(auction));

        // Rewards stop: shut down and unstake everything
        vm.startPrank(emergencyAdmin);
        strategy.shutdownStrategy();
        strategy.emergencyWithdraw(type(uint256).max);
        vm.stopPrank();

        // The lot goes unsold
        skip(1 days + 1);
        assertFalse(auction.isActive(address(rewardsToken)), "!ended");

        // Report relists it with no new rewards
        vm.prank(keeper);
        strategy.report();

        assertEq(auction.kicked(address(rewardsToken)), block.timestamp, "!relisted");
        assertEq(auction.available(address(rewardsToken)), _lot, "!lot");

        // Goes unsold again, keeper relists it too
        skip(1 days + 1);
        vm.prank(keeper);
        strategy.kickAuction(address(rewardsToken));

        assertEq(auction.kicked(address(rewardsToken)), block.timestamp, "!relisted");
        assertEq(auction.available(address(rewardsToken)), _lot, "!lot");
    }

    function test_kickAuction_onlyStrategy() public {
        airdrop(rewardsToken, address(auction), 1_000e18);

        vm.expectRevert("!governance");
        auction.kick(address(rewardsToken));
    }

    function test_enableAuctionToken() public {
        ERC20 _weth = ERC20(tokenAddrs["WETH"]);

        vm.prank(user);
        vm.expectRevert("!management");
        strategy.enableAuctionToken(address(_weth), 1e18);

        vm.prank(management);
        vm.expectRevert("!asset");
        strategy.enableAuctionToken(address(asset), 1e18);

        vm.prank(management);
        strategy.enableAuctionToken(address(_weth), 1e18);

        assertEq(strategy.minAmountToSell(address(_weth)), 1e18);

        // Sells tokens sent by mistake
        airdrop(_weth, address(strategy), 2e18);
        vm.prank(keeper);
        strategy.kickAuction(address(_weth));

        assertEq(auction.available(address(_weth)), 2e18, "!kicked");
    }

    function test_auctionSetters() public {
        vm.startPrank(user);
        vm.expectRevert("!management");
        strategy.setMinimumAuctionPrice(2e18);
        vm.expectRevert("!management");
        strategy.setAuctionStartingPrice(1_000e18);
        vm.expectRevert("!management");
        strategy.setAuctionStepDecayRate(30);
        vm.stopPrank();

        vm.startPrank(management);
        strategy.setMinimumAuctionPrice(2e18);
        strategy.setAuctionStartingPrice(1_000e18);
        strategy.setAuctionStepDecayRate(30);
        vm.stopPrank();

        assertEq(auction.minimumPrice(), 2e18);
        assertEq(auction.startingPrice(), 1_000e18);
        assertEq(auction.stepDecayRate(), 30);
    }

    function test_auctionSetters_whileLive(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Report kicks the rewards
        earn(_amount / 50);
        vm.prank(keeper);
        strategy.report();

        vm.startPrank(management);
        vm.expectRevert("active auction");
        strategy.setMinimumAuctionPrice(2e18);
        vm.expectRevert("active auction");
        strategy.setAuctionStartingPrice(1_000e18);
        vm.expectRevert("active auction");
        strategy.setAuctionStepDecayRate(30);
        vm.stopPrank();
    }

}
