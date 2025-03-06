// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { UUPSExtUpgradeable } from "../../base/UUPSExtUpgradeable.sol";

/**
 * @title UUPSExtUpgradableMock contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev An implementation of the {UUPSExtUpgradable} contract for test purposes.
 */
contract UUPSExtUpgradeableMock is UUPSExtUpgradeable {
    /// @dev Emitted when the internal `_validateUpgrade()` function is called with the parameters of the function.
    event MockValidateUpgradeCall(address newImplementation);

    // ------------------ Initializers ---------------------------- //

    /**
     * @dev The initialize function of the upgradable contract.
     *
     * See details https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable.
     */
    function initialize() public initializer {
        __UUPSExt_init();

        // Only to provide the 100 % test coverage
        __UUPSExt_init_unchained();
    }

    // ------------------ Functions ------------------------------- //

    /**
     * @dev Needed to check that the initialize function of the ancestor contract
     * has the 'onlyInitializing' modifier.
     */
    function call_parent_initialize() public {
        __UUPSExt_init();
    }

    /**
     * @dev Needed to check that the unchained initialize function of the ancestor contract
     * has the 'onlyInitializing' modifier.
     */
    function call_parent_initialize_unchained() public {
        __UUPSExt_init_unchained();
    }

    /**
     * @dev Executes further validation steps of the upgrade including authorization and implementation address checks.
     * @param newImplementation The address of the new implementation.
     */
    function _validateUpgrade(address newImplementation) internal virtual override {
        emit MockValidateUpgradeCall(newImplementation);
    }
}
