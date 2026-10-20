// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {HamsterToken} from "../src/HamsterToken.sol";

/// @title Local deployment of HamsterToken
/// @notice For local chains and review only. The IdentityMD launch deploys the token itself from
/// the built bytecode through its factory; nothing here is run for that launch and no key is read.
/// @dev The token takes no constructor arguments, so there is no configuration to pass. `deploy`
/// is the function the tests call directly; `run` only wraps it in a broadcast.
contract DeployHamsterToken is Script {
    /// @notice Deploys the token. Whoever calls this (the broadcaster, in `run`) receives the supply.
    function deploy() public returns (HamsterToken token) {
        token = new HamsterToken();
    }

    /// @notice Broadcast entry point: `forge script script/DeployHamsterToken.s.sol --broadcast`.
    function run() external returns (HamsterToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
