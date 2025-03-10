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
     * See details: https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable
     */
    function initialize() public initializer {
        __UUPSExt_init(); // This is needed to avoid errors during coverage assessment only.

        // Only to provide the 100 % test coverage
        __UUPSExt_init_unchained();
    }

    // ------------------ Transactional functions ----------------- //

    /// @dev Calls the parent internal initializing function to verify the 'onlyInitializing' modifier.
    function callParentInitializer() external {
        __UUPSExt_init();
    }

    /// @dev Calls the parent internal unchained initializing function to verify the 'onlyInitializing' modifier.
    function callParentInitializerUnchained() external {
        __UUPSExt_init_unchained();
    }

    /**
     * @dev An implementation of the validateUpgrade function of the UUPSExtUpgradeable contract.
     *
     * Does not execute any validation steps, just emits an event with the parameter of the function.
     *
     * @param newImplementation The address of the new implementation.
     */
    function _validateUpgrade(address newImplementation) internal override {
        emit MockValidateUpgradeCall(newImplementation);
    }
}
