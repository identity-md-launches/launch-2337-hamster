// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {HamsterToken} from "../src/HamsterToken.sol";

/// @notice Drives the token with random transfers, approvals and transferFroms among a fixed set of
/// actors. Reverting calls are allowed (fail_on_revert = false): the invariants are about state.
contract HamsterHandler is Test {
    HamsterToken public immutable token;
    address[] public actors;
    uint256 public ghostTransferred;

    constructor(HamsterToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        token.transfer(to, amount);
        ghostTransferred += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        vm.prank(_actor(ownerSeed));
        token.approve(_actor(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 cap = token.balanceOf(owner);
        uint256 allowed = token.allowance(owner, spender);
        if (allowed < cap) cap = allowed;
        amount = bound(amount, 0, cap);
        vm.prank(spender);
        token.transferFrom(owner, _actor(toSeed), amount);
        ghostTransferred += amount;
    }

    /// @dev Calls that should always revert: to the zero address, and above balance. Included so the
    /// invariants are checked after failures too.
    function transferToZero(uint256 fromSeed, uint256 amount) external {
        vm.prank(_actor(fromSeed));
        token.transfer(address(0), amount);
    }

    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 extra) external {
        address from = _actor(fromSeed);
        extra = bound(extra, 1, 1 ether);
        vm.prank(from);
        token.transfer(_actor(toSeed), token.balanceOf(from) + extra);
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }
}

contract HamsterTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    HamsterToken internal token;
    HamsterHandler internal handler;
    address internal deployer = makeAddr("deployer");

    function setUp() public {
        vm.prank(deployer);
        token = new HamsterToken();

        address[] memory actors = new address[](5);
        actors[0] = deployer;
        actors[1] = makeAddr("a");
        actors[2] = makeAddr("b");
        actors[3] = makeAddr("c");
        actors[4] = makeAddr("d");
        handler = new HamsterHandler(token, actors);

        // Seed three actors so transferFrom paths have something to move from the start.
        vm.startPrank(deployer);
        token.transfer(actors[1], 1_000 ether);
        token.transfer(actors[2], 1_000 ether);
        token.approve(actors[3], 500 ether);
        vm.stopPrank();

        targetContract(address(handler));
    }

    function invariant_totalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY, "balances do not sum to the supply");
    }

    function invariant_zeroAddressHoldsNothing() public view {
        assertEq(token.balanceOf(address(0)), 0);
    }
}
