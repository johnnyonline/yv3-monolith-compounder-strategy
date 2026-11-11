// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, IRevenueRouter} from "./utils/Setup.sol";

contract OracleTest is Setup {

    function setUp() public virtual override {
        super.setUp();
    }

    function test_setupOracleOK() public {
        assertEq(oracle.governance(), management);
        assertEq(oracle.poolIds(address(strategy)), 0x8f685c4188141352435483577d706d36d3259f45619fe0c6341d3f72dc8d7232);
    }

    function test_price() public {
        // ~2.65 SWAN per swanUSD in the pool at the fork block
        uint256 _price = oracle.price(address(strategy));
        assertGt(_price, 2e18, "!price");
        assertLt(_price, 3.5e18, "!price");

        vm.prank(user);
        vm.expectRevert("!keeper");
        oracle.setManualPrice(address(strategy), 4e18);

        // Manual price wins while set
        vm.prank(management);
        oracle.setManualPrice(address(strategy), 4e18);

        assertEq(oracle.price(address(strategy)), 4e18);

        // Back to the pool
        vm.prank(management);
        oracle.setManualPrice(address(strategy), 0);

        assertEq(oracle.price(address(strategy)), _price);
    }

    function test_setKeeper() public {
        // The deployer can set prices from the start
        assertTrue(oracle.keepers(vm.addr(42069)));

        vm.prank(user);
        vm.expectRevert("!governance");
        oracle.setKeeper(keeper, true);

        vm.prank(keeper);
        vm.expectRevert("!keeper");
        oracle.setManualPrice(address(strategy), 4e18);

        // Keepers can set prices
        vm.prank(management);
        oracle.setKeeper(keeper, true);

        vm.prank(keeper);
        oracle.setManualPrice(address(strategy), 4e18);

        assertEq(oracle.price(address(strategy)), 4e18);

        // Until removed
        vm.prank(management);
        oracle.setKeeper(keeper, false);

        vm.prank(keeper);
        vm.expectRevert("!keeper");
        oracle.setManualPrice(address(strategy), 0);
    }

    function test_setPool() public {
        vm.prank(user);
        vm.expectRevert("!governance");
        oracle.setPool(address(strategy), 6_000, 60, address(0));

        // No such pool
        vm.prank(management);
        vm.expectRevert("!pool");
        oracle.setPool(address(strategy), 500, 10, address(0));
    }

    function test_revenue() public {
        // Mostly ~3.4M USDS in sUSDS at the fork block, plus a little interest
        uint256 _revenue = oracle.revenue(IRevenueRouter(revenueRouter).lender());
        console2.log("yearly revenue, swanUSD", _revenue / 1e18);
        assertGt(_revenue, 100_000e18, "!revenue");
        assertLt(_revenue, 160_000e18, "!revenue");
    }

    function test_apr() public {
        // ~150%, like the Monolith UI
        uint256 _apr = oracle.aprAfterDebtChange(address(strategy), 0);
        console2.log("apr, bps", _apr / 1e14);
        assertApproxEqRel(_apr, 1.5e18, 0.1e18, "!apr");

        // Doubling the staked supply halves it
        int256 _supply = int256(staking.totalSupply());
        assertApproxEqRel(oracle.aprAfterDebtChange(address(strategy), _supply), _apr / 2, 1e15, "!apr");

        // A manual price scales it
        uint256 _doublePrice = 2 * oracle.price(address(strategy));
        vm.prank(management);
        oracle.setManualPrice(address(strategy), _doublePrice);

        assertApproxEqRel(oracle.aprAfterDebtChange(address(strategy), 0), 2 * _apr, 1e15, "!apr");

        // Can't take out more than is staked
        vm.expectRevert("!delta");
        oracle.aprAfterDebtChange(address(strategy), -_supply);
    }

    function test_apr_afterDeposit(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // What the oracle expects for the deposit
        uint256 _expected = oracle.aprAfterDebtChange(address(strategy), int256(_amount));

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertApproxEqRel(oracle.aprAfterDebtChange(address(strategy), 0), _expected, 1e15, "!apr");
    }

}
