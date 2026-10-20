// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {HamsterToken} from "../src/HamsterToken.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/// @notice Unit tests for HamsterToken: metadata, the single mint, every ERC-20 action's success and
/// failure paths, and the absence of any privileged function.
contract HamsterTokenTest is Test {
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

    // ----------------------------------------------------------------------------------------
    // Metadata and supply
    // ----------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "HAMSTER");
        assertEq(token.symbol(), "HAMSTER");
        assertEq(token.decimals(), 18);
        assertEq(token.NAME(), "HAMSTER");
        assertEq(token.SYMBOL(), "HAMSTER");
        assertEq(token.DECIMALS(), 18);
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.INITIAL_HOLDER(), deployer);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), alice, SUPPLY);
        vm.prank(alice);
        HamsterToken fresh = new HamsterToken();
        assertEq(fresh.balanceOf(alice), SUPPLY);
    }

    /// @dev The supply is minted to whoever runs the constructor, so a factory that deploys it holds it.
    function test_supplyGoesToWhoeverDeploysIncludingAContract() public {
        DeployerProbe factory = new DeployerProbe();
        HamsterToken deployed = factory.deploy(bytes32(uint256(7)));
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.INITIAL_HOLDER(), address(factory));
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_creationCodeTakesNoConstructorArguments() public {
        // Deploying the bare creation code with nothing appended must succeed.
        bytes memory code = type(HamsterToken).creationCode;
        address created;
        assembly ("memory-safe") {
            created := create(0, add(code, 32), mload(code))
        }
        assertTrue(created != address(0), "bare creation code failed");
        assertEq(HamsterToken(created).balanceOf(address(this)), SUPPLY);
    }

    // ----------------------------------------------------------------------------------------
    // transfer
    // ----------------------------------------------------------------------------------------

    function test_transfer_movesBalanceAndEmits() public {
        uint256 amount = 1_234 ether;
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(deployer, alice, amount);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transfer_wholeBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_transfer_zeroAmountSucceeds() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transfer_toSelfKeepsBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.prank(alice);
        assertTrue(token.transfer(alice, 10 ether));
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function test_transfer_revertsOnInsufficientBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 5 ether);
        vm.expectRevert(abi.encodeWithSelector(HamsterToken.InsufficientBalance.selector, alice, 5 ether, 5 ether + 1));
        vm.prank(alice);
        token.transfer(bob, 5 ether + 1);
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transfer_revertsFromEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(HamsterToken.InsufficientBalance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transfer(alice, 1);
    }

    function test_transfer_revertsToZeroAddress() public {
        vm.expectRevert(HamsterToken.InvalidRecipient.selector);
        vm.prank(deployer);
        token.transfer(address(0), 1 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    // ----------------------------------------------------------------------------------------
    // approve / allowance
    // ----------------------------------------------------------------------------------------

    function test_approve_setsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval(alice, spender, 42);
        vm.prank(alice);
        assertTrue(token.approve(spender, 42));
        assertEq(token.allowance(alice, spender), 42);
    }

    function test_approve_overwritesPreviousAllowance() public {
        vm.startPrank(alice);
        token.approve(spender, 42);
        token.approve(spender, 7);
        token.approve(spender, 0);
        vm.stopPrank();
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_approve_doesNotRequireABalance() public {
        vm.prank(bob);
        assertTrue(token.approve(spender, SUPPLY));
        assertEq(token.allowance(bob, spender), SUPPLY);
    }

    function test_approve_revertsForZeroSpender() public {
        vm.expectRevert(HamsterToken.InvalidSpender.selector);
        vm.prank(alice);
        token.approve(address(0), 1);
    }

    // ----------------------------------------------------------------------------------------
    // transferFrom
    // ----------------------------------------------------------------------------------------

    function _fund(address who, uint256 amount) internal {
        vm.prank(deployer);
        token.transfer(who, amount);
    }

    function test_transferFrom_spendsAllowanceAndEmitsBoth() public {
        _fund(alice, 100 ether);
        vm.prank(alice);
        token.approve(spender, 60 ether);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval(alice, spender, 20 ether);
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(alice, bob, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 40 ether));

        assertEq(token.balanceOf(alice), 60 ether);
        assertEq(token.balanceOf(bob), 40 ether);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(alice, spender), 20 ether);
    }

    function test_transferFrom_exactAllowanceLeavesZero() public {
        _fund(alice, 10 ether);
        vm.prank(alice);
        token.approve(spender, 10 ether);
        vm.prank(spender);
        token.transferFrom(alice, bob, 10 ether);
        assertEq(token.allowance(alice, spender), 0);
        vm.expectRevert(abi.encodeWithSelector(HamsterToken.InsufficientAllowance.selector, alice, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
    }

    function test_transferFrom_infiniteAllowanceIsNotDecremented() public {
        _fund(alice, 10 ether);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(alice, bob, 4 ether);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(bob), 4 ether);
    }

    function test_transferFrom_revertsWithoutAllowance() public {
        _fund(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(HamsterToken.InsufficientAllowance.selector, alice, spender, 0, 1 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1 ether);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function test_transferFrom_revertsAboveAllowance() public {
        _fund(alice, 10 ether);
        vm.prank(alice);
        token.approve(spender, 3 ether);
        vm.expectRevert(
            abi.encodeWithSelector(HamsterToken.InsufficientAllowance.selector, alice, spender, 3 ether, 3 ether + 1)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 3 ether + 1);
        assertEq(token.allowance(alice, spender), 3 ether);
    }

    function test_transferFrom_revertsAboveBalanceEvenWithAllowance() public {
        _fund(alice, 2 ether);
        vm.prank(alice);
        token.approve(spender, 5 ether);
        vm.expectRevert(abi.encodeWithSelector(HamsterToken.InsufficientBalance.selector, alice, 2 ether, 3 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 3 ether);
        // A failed transfer leaves the allowance untouched.
        assertEq(token.allowance(alice, spender), 5 ether);
    }

    function test_transferFrom_revertsToZeroAddress() public {
        _fund(alice, 2 ether);
        vm.prank(alice);
        token.approve(spender, 2 ether);
        vm.expectRevert(HamsterToken.InvalidRecipient.selector);
        vm.prank(spender);
        token.transferFrom(alice, address(0), 1 ether);
    }

    function test_transferFrom_ownerCannotPullWithoutSelfAllowance() public {
        _fund(alice, 2 ether);
        vm.expectRevert(abi.encodeWithSelector(HamsterToken.InsufficientAllowance.selector, alice, alice, 0, 1 ether));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1 ether);
    }

    // ----------------------------------------------------------------------------------------
    // No privileged party
    // ----------------------------------------------------------------------------------------

    /// @dev Every common admin or mint selector is unknown to the token: calls revert, nothing changes.
    function test_noMintOrAdminFunctionExists() public {
        address attacker = makeAddr("attacker");
        string[12] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "owner()",
            "setOwner(address)",
            "transferOwnership(address)",
            "renounceOwnership()",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);
            vm.prank(attacker);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(deployer);
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(attacker), 0, signatures[i]);
        }
    }

    /// @dev Nothing freezes, blocks, pauses, locks, seizes or burns a holder, not even the deployer.
    function test_noPrivilegedCallMovesOrFreezesAHolder() public {
        _fund(alice, SUPPLY / 1_000);
        uint256 held = token.balanceOf(alice);
        string[13] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, true);
            vm.prank(deployer);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        vm.prank(deployer);
        (bool moved,) = address(token).call(abi.encodeWithSelector(IERC20.transferFrom.selector, alice, deployer, 1));
        assertFalse(moved, "the deployer pulled without an allowance");
        assertEq(token.balanceOf(alice), held);
        vm.prank(alice);
        assertTrue(token.transfer(bob, held / 2));
        assertEq(token.balanceOf(bob), held / 2);
    }

    function test_rejectsEtherAndUnknownCalldata() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "accepted ether");
        vm.prank(alice);
        (ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok, "accepted unknown calldata");
    }

    // ----------------------------------------------------------------------------------------
    // Bytecode
    // ----------------------------------------------------------------------------------------

    function test_runtimeFitsEip170() public view {
        uint256 size = address(token).code.length;
        assertGt(size, 0);
        assertLe(size, 24_576);
    }

    /// @dev The same reachable-opcode scan the launch floor runs: PUSH data is skipped, and only
    /// instructions reachable from the start or a JUMPDEST count.
    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "runtime code contains DELEGATECALL");
                assertTrue(op != 0xF2, "runtime code contains CALLCODE");
                assertTrue(op != 0xFF, "runtime code contains SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ----------------------------------------------------------------------------------------
    // Fuzz
    // ----------------------------------------------------------------------------------------

    function testFuzz_transfer_conservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != deployer);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(deployer) + token.balanceOf(to), token.totalSupply());
    }

    function testFuzz_transfer_revertsAboveBalance(uint256 funded, uint256 amount) public {
        funded = bound(funded, 0, SUPPLY - 1);
        amount = bound(amount, funded + 1, SUPPLY);
        _fund(alice, funded);
        vm.expectRevert(abi.encodeWithSelector(HamsterToken.InsufficientBalance.selector, alice, funded, amount));
        vm.prank(alice);
        token.transfer(bob, amount);
    }

    function testFuzz_transferFrom_withinAllowanceAndBalance(uint256 funded, uint256 allowed, uint256 amount) public {
        funded = bound(funded, 0, SUPPLY);
        allowed = bound(allowed, 0, type(uint256).max - 1);
        amount = bound(amount, 0, funded < allowed ? funded : allowed);
        _fund(alice, funded);
        vm.prank(alice);
        token.approve(spender, allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.balanceOf(alice), funded - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.allowance(alice, spender), allowed - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFrom_revertsAboveAllowance(uint256 allowed, uint256 amount) public {
        allowed = bound(allowed, 0, SUPPLY - 1);
        amount = bound(amount, allowed + 1, SUPPLY);
        _fund(alice, SUPPLY);
        vm.prank(alice);
        token.approve(spender, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(HamsterToken.InsufficientAllowance.selector, alice, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
    }

    function testFuzz_approve_setsExactly(address who, address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.prank(who);
        assertTrue(token.approve(to, amount));
        assertEq(token.allowance(who, to), amount);
    }
}

/// @notice Stands in for a factory: deploys the token through CREATE2 and so becomes `msg.sender`
/// of its constructor.
contract DeployerProbe {
    function deploy(bytes32 salt) external returns (HamsterToken) {
        return new HamsterToken{salt: salt}();
    }
}
