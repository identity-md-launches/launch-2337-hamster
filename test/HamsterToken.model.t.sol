// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {HamsterToken} from "../src/HamsterToken.sol";

/// @notice Drives the token through random sequences of every state-changing call, with several
/// actors (including the deployer and the zero address as a would-be recipient or spender), and
/// keeps an independent ledger of what every balance and allowance should be. Each call is made
/// with try/catch, so whether it succeeded is checked against the ledger's prediction rather than
/// silently swallowed: a call that should succeed and reverts, or should revert and succeeds, fails
/// the run immediately.
contract HamsterModelHandler is Test {
    HamsterToken public immutable token;
    address[] internal actors;

    // Ghost ledger: the expected state, maintained from the ERC-20 specification alone.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    // Ghost counters for coverage and for the conservation invariants.
    uint256 public ghostMoved;
    uint256 public ghostSucceeded;
    uint256 public ghostExpectedReverts;
    /// @dev Number of times an observed outcome disagreed with the ledger. Must stay zero.
    uint256 public ghostMismatches;

    constructor(HamsterToken token_, address[] memory actors_, address deployer) {
        token = token_;
        actors = actors_;
        expectedBalance[deployer] = token_.TOTAL_SUPPLY();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev One in eight targets is the zero address, so the invalid-recipient and invalid-spender
    /// paths are exercised inside sequences, not only in isolation.
    function _target(uint256 seed) internal view returns (address) {
        if (seed % 8 == 0) return address(0);
        return _actor(seed >> 3);
    }

    /// @dev Amounts concentrate on the edges that matter: zero, the exact balance, one past it,
    /// the maximum, and otherwise anything up to a little past the balance.
    function _amount(uint256 seed, uint256 edge) internal pure returns (uint256) {
        uint256 pick = seed % 6;
        if (pick == 0) return 0;
        if (pick == 1) return edge;
        if (pick == 2) return edge == type(uint256).max ? edge : edge + 1;
        if (pick == 3) return type(uint256).max;
        uint256 hi = edge > type(uint256).max - 2 ? type(uint256).max : edge + 2;
        return bound(seed >> 3, 0, hi);
    }

    function _mismatch(bool cond) internal {
        if (cond) ghostMismatches++;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _target(toSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        bool shouldSucceed = to != address(0) && amount <= expectedBalance[from];

        vm.prank(from);
        try token.transfer(to, amount) returns (bool ok) {
            _mismatch(!shouldSucceed || !ok);
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
            ghostMoved += amount;
            ghostSucceeded++;
        } catch {
            _mismatch(shouldSucceed);
            ghostExpectedReverts++;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _target(spenderSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[owner]);
        bool shouldSucceed = spender != address(0);

        vm.prank(owner);
        try token.approve(spender, amount) returns (bool ok) {
            _mismatch(!shouldSucceed || !ok);
            expectedAllowance[owner][spender] = amount;
            ghostSucceeded++;
        } catch {
            _mismatch(shouldSucceed);
            ghostExpectedReverts++;
        }
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _target(toSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 held = expectedBalance[owner];
        uint256 amount = _amount(amountSeed, allowed < held ? allowed : held);
        bool shouldSucceed = to != address(0) && amount <= held && amount <= allowed;

        vm.prank(spender);
        try token.transferFrom(owner, to, amount) returns (bool ok) {
            _mismatch(!shouldSucceed || !ok);
            // An unlimited allowance is not decremented; any other is reduced by exactly `amount`.
            if (allowed != type(uint256).max) expectedAllowance[owner][spender] = allowed - amount;
            expectedBalance[owner] -= amount;
            expectedBalance[to] += amount;
            ghostMoved += amount;
            ghostSucceeded++;
        } catch {
            _mismatch(shouldSucceed);
            ghostExpectedReverts++;
        }
    }
}

contract HamsterTokenModelInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    HamsterToken internal token;
    HamsterModelHandler internal handler;
    address internal deployer = makeAddr("deployer");

    function setUp() public {
        vm.prank(deployer);
        token = new HamsterToken();

        address[] memory actors = new address[](6);
        actors[0] = deployer;
        actors[1] = makeAddr("alice");
        actors[2] = makeAddr("bob");
        actors[3] = makeAddr("carol");
        actors[4] = makeAddr("dave");
        actors[5] = address(token); // tokens sent to the token contract itself stay counted
        handler = new HamsterModelHandler(token, actors, deployer);

        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_everyOutcomeMatchesTheModel() public view {
        assertEq(handler.ghostMismatches(), 0, "a call succeeded or reverted against the specification");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesMatchTheModel() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            address a = handler.actorAt(i);
            assertEq(token.balanceOf(a), handler.expectedBalance(a), "balance diverged from the model");
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_allowancesMatchTheModel() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            for (uint256 j; j < n; ++j) {
                address o = handler.actorAt(i);
                address s = handler.actorAt(j);
                assertEq(token.allowance(o, s), handler.expectedAllowance(o, s), "allowance diverged from the model");
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_fixedSupplyIsFullyAccountedFor() public view {
        assertEq(token.totalSupply(), SUPPLY, "the supply changed");
        uint256 sum;
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            sum += token.balanceOf(handler.actorAt(i));
        }
        // Tokens only ever move between actors (or the call reverts), so the actors hold everything.
        assertEq(sum, SUPPLY, "balances do not sum to the supply");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_zeroAddressNeverHoldsOrSpends() public view {
        assertEq(token.balanceOf(address(0)), 0, "the zero address received tokens");
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            assertEq(token.allowance(handler.actorAt(i), address(0)), 0, "an allowance was granted to zero");
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_initialHolderIsFixed() public view {
        assertEq(token.INITIAL_HOLDER(), deployer);
    }
}
