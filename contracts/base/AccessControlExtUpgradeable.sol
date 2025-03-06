// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title AccessControlExtUpgradeable base contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Extends the OpenZeppelin's {AccessControlUpgradeable} contract by adding the functions
 *      for granting and revoking roles in batch.
 */
abstract contract AccessControlExtUpgradeable is AccessControlUpgradeable {
    // ------------------ Initializers ---------------------------- //

    /**
     * @dev Internal initializer of the upgradable contract.
     *
     * See details: https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable
     */
    function __AccessControlExt_init() internal onlyInitializing {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();

        __AccessControlExt_init_unchained();
    }

    /**
     * @dev Unchained internal initializer of the upgradable contract.
     *
     * See details: https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable
     */
    function __AccessControlExt_init_unchained() internal onlyInitializing {}

    // ------------------ Transactional functions ----------------- //

    /**
     * @dev Grants a role to accounts in batch.
     *
     * Emits a {RoleGranted} event for each account that has not been granted the provided role previously.
     *
     * Requirement: the caller must have the role that is the admin for the role that is being granted.
     *
     * @param role The role to grant.
     * @param accounts The accounts to grant the role to.
     */
    function grantRoleBatch(bytes32 role, address[] memory accounts) public virtual onlyRole(getRoleAdmin(role)) {
        for (uint i = 0; i < accounts.length; i++) {
            _grantRole(role, accounts[i]);
        }
    }

    /**
     * @dev Revokes a role to accounts in batch.
     *
     * Emits a {RoleRevoked} event for each account that has the provided role previously.
     *
     * Requirement: the caller must have the role that is the admin for the role that is being revoked.
     *
     * @param role The role to revoke.
     * @param accounts The accounts to revoke the role from.
     */
    function revokeRoleBatch(bytes32 role, address[] memory accounts) public virtual onlyRole(getRoleAdmin(role)) {
        for (uint i = 0; i < accounts.length; i++) {
            _revokeRole(role, accounts[i]);
        }
    }
}
