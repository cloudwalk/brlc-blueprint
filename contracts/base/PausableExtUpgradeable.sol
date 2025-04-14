// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { AccessControlExtUpgradeable } from "./AccessControlExtUpgradeable.sol";

/**
 * @title PausableExtUpgradeable base contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Extends the OpenZeppelin's {PausableUpgradeable} contract by adding the {PAUSER_ROLE} role and implementing
 *      the external pausing and unpausing functions.
 */
abstract contract PausableExtUpgradeable is AccessControlExtUpgradeable, PausableUpgradeable {
    /// @dev The role of pauser that is allowed to trigger the paused or unpaused state of the contract.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ------------------ Initializers ---------------------------- //

    /**
     * @dev Internal initializer of the upgradable contract.
     *
     * See details: https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable
     *
     * @param pauserRoleAdmin The admin for the {PAUSER_ROLE} role.
     */
    function __PausableExt_init(bytes32 pauserRoleAdmin) internal onlyInitializing {
        __Pausable_init_unchained();
        __PausableExt_init_unchained(pauserRoleAdmin);
    }

    /**
     * @dev Unchained internal initializer of the upgradable contract.
     *
     * See details: https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable
     *
     * @param pauserRoleAdmin The admin for the {PAUSER_ROLE} role.
     */
    function __PausableExt_init_unchained(bytes32 pauserRoleAdmin) internal onlyInitializing {
        _setRoleAdmin(PAUSER_ROLE, pauserRoleAdmin);
    }

    // ------------------ Transactional functions ----------------- //

    /**
     * @dev Triggers the paused state of the contract.
     *
     * Requirement: the caller must have the {PAUSER_ROLE} role.
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Triggers the unpaused state of the contract.
     *
     * Requirement: the caller must have the {PAUSER_ROLE} role.
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
