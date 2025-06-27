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
    // ------------------ Constants ------------------------------- //

    /// @dev The role of admin that is allowed to perform administrative operations.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @dev The maximum number of participants per wallet.
    uint256 public constant MAX_PARTICIPANTS_PER_WALLET = 100;

    /// @dev The accuracy factor to rounding down the shares of the participants during transfers.
    uint256 public constant ACCURACY_FACTOR = 10000;

    // ------------------ Storage layout -------------------------- //

    /**
     * @dev The storage location for the shared wallet controller.
     *
     * See: ERC-7201 "Namespaced Storage Layout" for more details.
     *
     * The value is the same as:
     *
     * ```solidity
     * string memory id = "cloudwalk.storage.SharedWalletController";
     * bytes32 location = keccak256(abi.encode(uint256(keccak256(id) - 1)) & ~bytes32(uint256(0xff));
     * ```
     */
    bytes32 private constant SHARED_WALLET_CONTROLLER_STORAGE_LOCATION =
        0xe11e49cf5c86defdf380231d4bda7c92d28e7f1f0a1fd45e8b00ac3bd9182c00;

    /**
     * @dev Defines the contract storage structure.
     *
     * The fields:
     *
     * - token --------------------- The address of the ERC20 token that is used in the shared wallets.
     * - walletCount --------------- The number of existing shared wallets.
     * - walletsAggregatedBalance -- The aggregated balance across all shared wallets.
     * - wallets ------------------- The mapping of a shared wallet for a given wallet address.
     * - participantWallets -------- The mapping of a set of wallets for a given participant address.
     *
     * @custom:storage-location erc7201:cloudwalk.storage.SharedWalletController
     */
    struct SharedWalletControllerStorage {
        // Slot 1
        address token;
        uint32 walletCount;
        uint64 aggregatedBalance;
        // No reserve until the end of the storage slot

        // Slot 2
        mapping(address wallet => SharedWallet) wallets;
        // No reserve until the end of the storage slot

        // Slot 3
        mapping(address participant => EnumerableSet.AddressSet) participantWallets;
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
