// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployHamsterToken} from "../script/DeployHamsterToken.s.sol";
import {HamsterToken} from "../src/HamsterToken.sol";

/// @notice Calls the deploy script's function directly, with no environment and no broadcast.
contract DeployHamsterTokenTest is Test {
    function test_deployMintsSupplyToTheCaller() public {
        DeployHamsterToken script = new DeployHamsterToken();
        HamsterToken token = script.deploy();
        // The script contract ran the constructor, so it is the deployer and holds the supply.
        assertEq(token.balanceOf(address(script)), token.TOTAL_SUPPLY());
        assertEq(token.INITIAL_HOLDER(), address(script));
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.name(), "HAMSTER");
        assertEq(token.symbol(), "HAMSTER");
        assertEq(token.decimals(), 18);
    }
}
