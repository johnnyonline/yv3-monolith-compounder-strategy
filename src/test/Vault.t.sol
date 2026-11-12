// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup} from "./utils/Setup.sol";

contract VaultTest is Setup {

    function setUp() public virtual override {
        super.setUp();
    }

    function test_setupVaultOK() public {
        assertEq(vault.apiVersion(), "3.1.1");
        assertEq(vault.asset(), address(asset));
        assertEq(vault.profitMaxUnlockTime(), 3 days);
        assertEq(vault.deposit_limit(), type(uint256).max);
        assertTrue(vault.auto_allocate());
        assertEq(vault.future_role_manager(), management);
        assertEq(vault.roles(keeper), 32);
        assertEq(vault.roles(vm.addr(42069)), 0);
        address[] memory _queue = vault.get_default_queue();
        assertEq(_queue.length, 1);
        assertEq(_queue[0], address(strategy));
        assertEq(vault.strategies(address(strategy)).max_debt, type(uint256).max);
    }

    function test_vaultOperation(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into the vault, which allocates it all to the strategy
        airdrop(asset, user, _amount);
        vm.startPrank(user);
        asset.approve(address(vault), _amount);
        vault.deposit(_amount, user);
        vm.stopPrank();

        assertEq(vault.strategies(address(strategy)).current_debt, _amount, "!debt");
        assertEq(strategy.balanceOfStake(), _amount, "!staked");

        // Earn ~2% in rewards
        earn(_amount / 50);

        // Strategy kicks the rewards, then books and restakes the proceeds. Its profit unlocks right away
        vm.prank(keeper);
        strategy.report();
        take();
        vm.prank(keeper);
        (uint256 profit,) = strategy.report();
        assertGt(profit, 0, "!profit");

        // Vault picks it up and unlocks it over 3 days
        vm.prank(keeper);
        (uint256 gain, uint256 loss) = vault.process_report(address(strategy));
        assertApproxEqAbs(gain, profit, 1, "!gain");
        assertEq(loss, 0, "!loss");

        skip(vault.profitMaxUnlockTime());

        // Withdraw all funds
        uint256 _shares = vault.balanceOf(user);
        vm.prank(user);
        vault.redeem(_shares, user, user);

        assertApproxEqAbs(asset.balanceOf(user), _amount + profit, 2, "!final balance");
    }

}
