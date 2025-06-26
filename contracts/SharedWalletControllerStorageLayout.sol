// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { ISharedWalletControllerTypes } from "./interfaces/ISharedWalletController.sol";

/**
 * @title SharedWalletControllerStorageLayout contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the storage layout for the shared wallet controller smart-contract.
 */
abstract contract SharedWalletControllerStorageLayout is ISharedWalletControllerTypes {
    using EnumerableSet for EnumerableSet.AddressSet;

    // ------------------ Constants ------------------------------- //

    /// @dev The role of admin that is allowed to perform administrative operations.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @dev The maximum number of participants per wallet.
    uint256 public constant MAX_PARTICIPANTS_PER_WALLET = 100;

    /// @dev The accuracy factor to rounding down the shares of the participants during transfers.
    uint256 public constant ACCURACY_FACTOR = 10000;

    // ------------------ Storage layout -------------------------- //

    /*
     * ERC-7201: Namespaced Storage Layout
     * keccak256(abi.encode(uint256(keccak256("cloudwalk.storage.SharedWalletController")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 private constant SHARED_WALLET_CONTROLLER_STORAGE_LOCATION =
        0xe11e49cf5c86defdf380231d4bda7c92d28e7f1f0a1fd45e8b00ac3bd9182c00;

    /**
     * @dev Defines the contract storage structure.
     *
     * The fields:
     *
     * - wallets ---------------- The mapping of a shared wallet for a given wallet address.
     * - participantWallets ----- The mapping of a set of wallets for a given participant address.
     *
     * @custom:storage-location erc7201:cloudwalk.storage.SharedWalletController
     */
    struct SharedWalletControllerStorage {
        // Slot 1
        address token;
        // uint96 __reserved1; // Reserved for future use until the end of the storage slot

        // Slot 2
        mapping(address => SharedWallet) wallets;
        // No reserve until the end of the storage slot

        // Slot 3
        mapping(address => EnumerableSet.AddressSet) participantWallets;
        // No reserve until the end of the storage slot
    }

    // ------------------ Internal functions ---------------------- //

    /// @dev Returns the storage slot location for the `SharedWalletControllerStorage` struct.
    function _getSharedWalletControllerStorage() internal pure returns (SharedWalletControllerStorage storage $) {
        assembly {
            $.slot := SHARED_WALLET_CONTROLLER_STORAGE_LOCATION
        }
    }
}
