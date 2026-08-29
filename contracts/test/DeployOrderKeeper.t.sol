// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployOrderKeeper} from "../script/DeployOrderKeeper.s.sol";

contract DeployOrderKeeperHarness is DeployOrderKeeper {
    function shouldWriteDeploymentRecord() external view returns (bool) {
        return _shouldWriteDeploymentRecord();
    }
}

/// @title DeployOrderKeeperTest
/// @notice Unit tests for deployment-script behavior that must be safe in a
///         local dry-run or test context.
contract DeployOrderKeeperTest is Test {
    /// @notice Confirms non-broadcast execution cannot overwrite the canonical
    ///         deployment record with simulated addresses.
    function test_DoesNotWriteDeploymentRecordOutsideBroadcastContext() public {
        DeployOrderKeeperHarness script = new DeployOrderKeeperHarness();

        assertFalse(script.shouldWriteDeploymentRecord());
    }
}
