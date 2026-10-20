// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {HamsterToken} from "../src/HamsterToken.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/// @notice Stands in for the launch factory: deploys the token in the same call it moves the
/// swarm's share and the pool share out, as `launchCustom` does in one transaction.
contract LaunchFlowProbe {
    HamsterToken public token;

    function launch(address distributor, address pool, address remainderTo, uint256 poolBps)
        external
        returns (HamsterToken t)
    {
        t = new HamsterToken();
        token = t;
        uint256 supply = t.totalSupply();
        uint256 swarm = (supply * 1_000) / 10_000;
        uint256 seed = (supply * poolBps) / 10_000;
        require(t.transfer(distributor, swarm), "swarm transfer");
        require(t.transfer(pool, seed), "seed transfer");
        require(t.transfer(remainderTo, t.balanceOf(address(this))), "remainder transfer");
    }
}

/// @notice Edge cases the main unit file does not pin: the maximum values, the allowance boundary
/// just below "unlimited", self-allowances, event shapes, and the launch flows arriving exact.
contract HamsterTokenEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    HamsterToken internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    function setUp() public {
        vm.prank(deployer);
        token = new HamsterToken();
    }

    function _fund(address who, uint256 amount) internal {
        vm.prank(deployer);
        token.transfer(who, amount);
    }

    // ----------------------------------------------------------------------------------------
    // Maximum values
    // ----------------------------------------------------------------------------------------

    function test_transfer_uint256MaxReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(HamsterToken.InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(deployer);
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transfer_oneWeiOverSupplyReverts() public {
        vm.expectRevert(abi.encodeWithSelector(HamsterToken.InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1));
        vm.prank(deployer);
        token.transfer(alice, SUPPLY + 1);
    }

    function test_transferFrom_uint256MaxWithUnlimitedAllowanceReverts() public {
        _fund(alice, 5 ether);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(HamsterToken.InsufficientBalance.selector, alice, 5 ether, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, type(uint256).max);
        assertEq(token.allowance(alice, spender), type(uint256).max);
    }

    function test_transferFrom_wholeSupplyThroughAllowance() public {
        vm.prank(deployer);
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, SUPPLY));
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    // ----------------------------------------------------------------------------------------
    // Allowance boundary
    // ----------------------------------------------------------------------------------------

    /// @dev Only exactly `type(uint256).max` is unlimited; one below it is an ordinary allowance.
    function test_transferFrom_allowanceJustBelowMaxIsDecremented() public {
        _fund(alice, 10 ether);
        uint256 allowed = type(uint256).max - 1;
        vm.prank(alice);
        token.approve(spender, allowed);
        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval(alice, spender, allowed - 3 ether);
        vm.prank(spender);
        token.transferFrom(alice, bob, 3 ether);
        assertEq(token.allowance(alice, spender), allowed - 3 ether);
    }

    /// @dev An unlimited allowance emits only the Transfer, no Approval, on spend.
    function test_transferFrom_unlimitedAllowanceEmitsNoApproval() public {
        _fund(alice, 10 ether);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.recordLogs();
        vm.prank(spender);
        token.transferFrom(alice, bob, 1 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "expected a single Transfer log");
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
    }

    function test_transferFrom_zeroAmountWithoutAllowanceSucceeds() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_transferFrom_zeroAmountToZeroAddressReverts() public {
        vm.expectRevert(HamsterToken.InvalidRecipient.selector);
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
    }

    function test_transfer_zeroAmountToZeroAddressReverts() public {
        vm.expectRevert(HamsterToken.InvalidRecipient.selector);
        vm.prank(alice);
        token.transfer(address(0), 0);
    }

    function test_transferFrom_withSelfAllowance() public {
        _fund(alice, 4 ether);
        vm.startPrank(alice);
        token.approve(alice, 3 ether);
        assertTrue(token.transferFrom(alice, bob, 3 ether));
        vm.stopPrank();
        assertEq(token.balanceOf(bob), 3 ether);
        assertEq(token.allowance(alice, alice), 0);
    }

    function test_transferFrom_toOwnerKeepsBalanceButSpendsAllowance() public {
        _fund(alice, 4 ether);
        vm.prank(alice);
        token.approve(spender, 4 ether);
        vm.prank(spender);
        token.transferFrom(alice, alice, 4 ether);
        assertEq(token.balanceOf(alice), 4 ether);
        assertEq(token.allowance(alice, spender), 0);
    }

    /// @dev A spender's allowance is per owner: one owner's approval cannot be spent against another.
    function test_allowanceIsScopedToOwnerAndSpender() public {
        _fund(alice, 5 ether);
        _fund(bob, 5 ether);
        vm.prank(alice);
        token.approve(spender, 5 ether);
        vm.expectRevert(abi.encodeWithSelector(HamsterToken.InsufficientAllowance.selector, bob, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(bob, spender, 1);
        vm.expectRevert(abi.encodeWithSelector(HamsterToken.InsufficientAllowance.selector, alice, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, bob, 1);
    }

    function test_approve_revertsForZeroSpenderEvenWithZeroAmount() public {
        vm.expectRevert(HamsterToken.InvalidSpender.selector);
        vm.prank(alice);
        token.approve(address(0), 0);
    }

    function test_approve_fromZeroAddressCallerIsHarmless() public {
        // Nobody can sign as the zero address on chain, but the code must not treat it specially.
        vm.prank(address(0));
        token.approve(spender, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(HamsterToken.InsufficientBalance.selector, address(0), 0, 1 ether));
        vm.prank(spender);
        token.transferFrom(address(0), bob, 1 ether);
    }

    // ----------------------------------------------------------------------------------------
    // Launch flows
    // ----------------------------------------------------------------------------------------

    /// @dev Deploy and distribute in one call, as the factory does: every flow arrives exact and the
    /// factory ends empty, so the 10% swarm share, the pool seed and the remainder are whole.
    function test_launchFlowsArriveExactInOneTransaction() public {
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool");
        address requester = makeAddr("requester");
        LaunchFlowProbe factory = new LaunchFlowProbe();
        HamsterToken t = factory.launch(distributor, pool, requester, 5_000);

        assertEq(t.INITIAL_HOLDER(), address(factory));
        assertEq(t.balanceOf(distributor), 100_000_000 ether);
        assertEq(t.balanceOf(pool), 500_000_000 ether);
        assertEq(t.balanceOf(requester), 400_000_000 ether);
        assertEq(t.balanceOf(address(factory)), 0);
        assertEq(t.totalSupply(), SUPPLY);

        // The distributor can pay every claim out whole.
        vm.prank(distributor);
        t.transfer(alice, 60_000_000 ether);
        vm.prank(distributor);
        t.transfer(bob, 40_000_000 ether);
        assertEq(t.balanceOf(distributor), 0);
        assertEq(t.balanceOf(alice) + t.balanceOf(bob), 100_000_000 ether);
    }

    /// @dev The initial holder has no privilege after it has handed its balance on.
    function test_initialHolderHasNoPowerAfterDistributing() public {
        _fund(alice, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(HamsterToken.InsufficientAllowance.selector, alice, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        vm.expectRevert(abi.encodeWithSelector(HamsterToken.InsufficientBalance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transfer(alice, 1);
    }

    // ----------------------------------------------------------------------------------------
    // Property fuzz
    // ----------------------------------------------------------------------------------------

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferBetweenThirdParties(uint256 funded, uint256 amount, uint256 toSeed) public {
        funded = bound(funded, 0, SUPPLY);
        amount = bound(amount, 0, funded);
        address to = toSeed % 2 == 0 ? bob : alice; // includes the self-transfer case
        _fund(alice, funded);
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(alice);
        assertTrue(token.transfer(to, amount));
        if (to == alice) {
            assertEq(token.balanceOf(alice), aliceBefore);
        } else {
            assertEq(token.balanceOf(alice), aliceBefore - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        }
        assertEq(token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(deployer), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_failedTransferFromChangesNothing(uint256 funded, uint256 allowed, uint256 amount) public {
        funded = bound(funded, 0, SUPPLY);
        allowed = bound(allowed, 0, type(uint256).max - 1);
        uint256 limit = funded < allowed ? funded : allowed;
        amount = bound(amount, limit + 1, type(uint256).max);
        _fund(alice, funded);
        vm.prank(alice);
        token.approve(spender, allowed);

        vm.prank(spender);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (alice, bob, amount)));
        assertFalse(ok, "transferFrom above balance or allowance succeeded");
        assertEq(token.balanceOf(alice), funded);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), allowed);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_unlimitedAllowanceNeverDecreases(uint256 a, uint256 b) public {
        _fund(alice, SUPPLY / 2);
        a = bound(a, 0, SUPPLY / 4);
        b = bound(b, 0, SUPPLY / 4);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        token.transferFrom(alice, bob, a);
        token.transferFrom(alice, bob, b);
        vm.stopPrank();
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(bob), a + b);
    }
}
