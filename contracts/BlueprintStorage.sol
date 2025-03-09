// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { IBlueprintTypes } from "./interfaces/IBlueprintTypes.sol";

/**
 * @title BlueprintStorage contract
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev Defines the storage layout for the reference smart-contract.
 *
 * See details about the contract in the comments of the {IBlueprint} interface.
 */
abstract contract BlueprintStorage is IBlueprintTypes {
    /// @dev The address of the underlying token.
    address internal _token;

    /**
     * @dev The address of the operational treasury.
     *
     * The operational treasury is used to deposit and withdraw tokens through special functions.
     */
    address internal _operationalTreasury;

    /// @dev The mapping of an operation structure for a given off-chain operation identifier.
    mapping(bytes32 opId => Operation operation) internal _operations;

    /// @dev The mapping of a balance for a given account.
    mapping(address account => uint256 balance) internal _balances;

    /**
     * @dev This empty reserved space is put in place to allow future versions
     *      to add new variables without shifting down storage in the inheritance chain.
     */
    uint256[46] private __gap;
}
